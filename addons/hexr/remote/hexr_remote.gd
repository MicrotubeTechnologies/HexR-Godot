class_name HexRRemote
extends Node
## HexR Remote: lets a phone running the HexR Companion (Headsets tab) find this app on the local
## Wi-Fi, connect and release its gloves, read their state, switch scenes, run commands, and
## watch the headset's view and sound. Port of the Unity package's HexRRemote, speaking the same
## protocol (docs/RemoteProtocol.md), so the same phone app works with both.
##
## Add one to the first scene (Project > Tools > HexR > Add HexR Remote). It is local-network
## only and not authenticated: anyone on the same Wi-Fi with a HexR Remote client can control
## the gloves. Bring a dedicated router to events.
##
## [codeblock]
## HexRRemote.register_command("reset", "Reset demo", reset_demo)
## [/codeblock]

## The Unity package version this matches: what phones check before offering features.
const HEXR_VERSION := HexRManager.PROTOCOL_VERSION
const STALE_REQUEST_MS := 5000

static var instance: HexRRemote
static var _commands: Dictionary = {}
static var _command_order: PackedStringArray = []

@export_group("What a phone may do")
## Connect and disconnect the gloves, and release their haptics.
@export var allow_glove_control := true
## Share the headset view. The wearer still has to accept Android's prompt each session.
@export var allow_video := true
## Show the phone the scenes in the project setting [code]hexr/scenes[/code] (Godot's stand-in
## for Unity's Build Settings, see [SceneLoader]) and let it switch between them.
@export var expose_scenes := false

@export_group("Sharing the view")
## Encoded size, rounded to a multiple of 16. Quest's compositor delivers a square view.
@export var video_width := 1024
@export var video_height := 1024
@export_range(500, 20000) var video_bitrate_kbps := 4000
@export_range(10, 60) var video_fps := 30
## End sharing if the app stays in the background this long.
@export var stop_video_after_background_seconds := 20
## Share the app's own sound with its view. Android guards any audio capture with the
## microphone permission, so the wearer is asked for it once; the build gets that permission
## only while a Remote shares sound.
@export var share_sound := true

@export_group("Network")
@export var discovery_port := HexRRemoteProtocol.DEFAULT_DISCOVERY_PORT
## If taken, the next free port is used and announced.
@export var control_port := HexRRemoteProtocol.DEFAULT_CONTROL_PORT
@export var video_port := HexRRemoteProtocol.DEFAULT_VIDEO_PORT
@export var audio_port := HexRRemoteProtocol.DEFAULT_AUDIO_PORT
@export_range(1, 20) var status_per_second := 5.0

## Where the announcement is sent (tests set 127.0.0.1).
var announce_address := "255.255.255.255"

var _server: HexRRemoteServer
var _stream: HexRRemoteStream
var _viewers := 0
# A 0.1 scene's own scene list; used only while hexr/scenes is empty.
var _scenes_0_1: Array[String] = []

const _SceneLoader := preload("res://addons/hexr/core/scene_loader.gd")
var _handler: HexRRemoteCommands
var _haptics: HexRRemoteHaptics
var _paused := false
var _next_status_ms := 0
var _announced_video_port := -1
var _identity: Dictionary = {}
var _moving := false


# -- commands -------------------------------------------------------------------------------

## Lets a phone run [param action] by [param id]; it is listed by [param label].
static func register_command(id: String, label: String, action: Callable) -> void:
	assert(not id.is_empty() and action.is_valid(), "A remote command needs an id and an action.")
	if not _commands.has(id):
		_command_order.append(id)
	_commands[id] = {"label": label if not label.is_empty() else id, "action": action}


static func unregister_command(id: String) -> void:
	if _commands.erase(id):
		var i := _command_order.find(id)
		if i >= 0:
			_command_order.remove_at(i)


static func has_command(id: String) -> bool:
	return _commands.has(id)


## The command's action, or an invalid Callable (unknown id, or its object was freed).
static func get_command(id: String) -> Callable:
	var entry: Dictionary = _commands.get(id, {})
	var action: Callable = entry.get("action", Callable())
	return action if action.is_valid() else Callable()


static func command_list() -> Array:
	var out := []
	for id in _command_order:
		out.append(HexRRemoteProtocol.command_info(id, _commands[id]["label"]))
	return out


# -- lifecycle ------------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if instance != null and instance != self and is_instance_valid(instance):
		queue_free()
		return
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After every other script, so the haptics feed sees everything sent this frame.
	process_priority = 1000
	begin()
	# Outlive scene changes, as the Unity component does with DontDestroyOnLoad: switching
	# scenes is one of the things a phone asks for, and the phone should stay connected.
	if get_parent() != get_tree().root:
		_moving = true
		reparent.call_deferred(get_tree().root)
		_finish_move.call_deferred()


func _finish_move() -> void:
	_moving = false


func _exit_tree() -> void:
	if _moving:
		return
	shutdown()
	if instance == self:
		instance = null


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_set_paused(true)
		NOTIFICATION_APPLICATION_RESUMED:
			_set_paused(false)


func is_running() -> bool:
	return _server != null and _server.is_running()


## The control port in use (it moves up if the preferred one is taken).
func get_control_port() -> int:
	return _server.port if _server else 0


func phones_connected() -> int:
	return _server.client_count() if _server else 0


## How many phones are watching the headset's view right now (Unity [code]PhonesWatching[/code]).
func phones_watching() -> int:
	return _viewers


## The scenes a phone can switch to: [code]hexr/scenes[/code].
func scenes() -> PackedStringArray:
	var list := _SceneLoader.scenes()
	return list if not list.is_empty() else PackedStringArray(_scenes_0_1)


# Scenes saved with HexR 0.1 carry their own scene list.
func _set(property: StringName, value: Variant) -> bool:
	if property != &"scenes":
		return false
	_scenes_0_1.assign(value)
	HexRTypes.warn_renamed(self, "scenes", "the hexr/scenes project setting")
	return true


func begin() -> void:
	if is_running():
		return
	_identity = _make_identity()
	_haptics = HexRRemoteHaptics.new(clock_us)
	_stream = HexRRemoteStream.create(self)
	_handler = HexRRemoteCommands.new(HexRManager.get_instance, _stream, func() -> int: return scenes().size(), _load_scene)
	_server = HexRRemoteServer.new()
	_server.announce_address = announce_address
	if OS.get_name() == "Android" and Engine.has_singleton("HexRBle"):
		_server.pause_probe = Callable(Engine.get_singleton("HexRBle"), "isAppPaused")
	if not _server.start(control_port, discovery_port):
		push_error("[HexR] Remote: could not open its network ports, so phones cannot reach this app.")
		_server = null
		return
	_update_announce(video_port)
	_server.set_snapshot(_haptics.snapshot())
	_publish_status()
	print("[HexR] Remote: phones can connect on port %d (announcing on UDP %d)." % [_server.port, discovery_port])


func shutdown() -> void:
	if _stream:
		_stream.stop()
	if _server:
		_server.stop()
	_server = null


func _set_paused(paused: bool) -> void:
	_paused = paused
	if _server:
		_server.set_paused(paused)
		_publish_status()


# -- every frame ----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _server == null:
		return
	_handler.allow_glove_control = allow_glove_control
	_handler.allow_video = allow_video
	_handler.expose_scenes = expose_scenes
	var now := Time.get_ticks_msec()
	for item: Dictionary in _server.take_requests(16):
		var req: Dictionary = item["request"]
		if now - int(item["received_ms"]) > STALE_REQUEST_MS:
			_server.reply(item["client"], HexRRemoteProtocol.error_line(req["type"],
					"The headset was busy and this request expired. Try again."))
			continue
		var error := _handler.handle(req)
		if not error.is_empty():
			_server.reply(item["client"], HexRRemoteProtocol.error_line(req["type"], error))
		else:
			_next_status_ms = 0
	if now >= _next_status_ms:
		_next_status_ms = now + int(1000.0 / maxf(1.0, status_per_second))
		_publish_status()
	var lines := []
	_haptics.poll(HexRManager.get_instance(), lines)
	if not lines.is_empty():
		for line in lines:
			_server.publish_event(line)
		_server.set_snapshot(_haptics.snapshot())


func _publish_status() -> void:
	if _server == null:
		return
	var stream := _stream.read()
	_viewers = int(stream.get("viewers", 0))
	if not allow_video and stream["state"] != HexRRemoteProtocol.STREAM_LIVE:
		stream["state"] = HexRRemoteProtocol.STREAM_UNSUPPORTED
		stream["message"] = "This app does not share its view."
	if (not allow_video or not share_sound) and stream["audio"]["state"] != HexRRemoteProtocol.STREAM_LIVE:
		stream["audio"]["state"] = HexRRemoteProtocol.STREAM_UNSUPPORTED
		stream["audio"]["message"] = "This app does not share its sound."
	if int(stream["port"]) > 0 and int(stream["port"]) != _announced_video_port:
		_update_announce(stream["port"])
	var listed := []
	if expose_scenes:
		var list := scenes()
		for i in list.size():
			listed.append(HexRRemoteProtocol.scene_info(i, HexRRemoteProtocol.scene_display_name(list[i])))
	_server.publish_status(HexRRemoteProtocol.status(_identity["id"], _identity["name"], _identity["model"],
			_identity["platform"], _identity["app"], _identity["app_version"], HEXR_VERSION, _paused,
			_headset_battery(), _current_scene(), listed, HexRRemoteCommands.glove_status(HexRManager.get_instance()),
			stream, command_list(), allow_glove_control, allow_video, expose_scenes, _server.client_count(), clock_us()))


func _update_announce(video: int) -> void:
	_announced_video_port = video
	_server.set_announce(HexRRemoteProtocol.announce(_identity["id"], _identity["name"], _identity["model"],
			_identity["platform"], _identity["app"], _identity["app_id"], HEXR_VERSION, _server.port, video,
			_identity["started_at"]))
	_server.set_welcome(HexRRemoteProtocol.to_line(HexRRemoteProtocol.welcome(_identity["id"], _server.port, video)))


## Microseconds on the clock the video and sound are stamped with (CLOCK_MONOTONIC on Android).
func clock_us() -> int:
	var hub := HexRManager.get_instance()
	if hub and hub.transport:
		return hub.transport.clock_us()
	return Time.get_ticks_usec()


# -- identity and scenes --------------------------------------------------------------------

func _make_identity() -> Dictionary:
	var ble: Object = Engine.get_singleton("HexRBle") if OS.get_name() == "Android" and Engine.has_singleton("HexRBle") else null
	var model := ""
	var device_name := ""
	var app_id := ""
	if ble:
		model = "%s %s" % [ble.getDeviceManufacturer(), ble.getDeviceModel()]
		device_name = ble.getDeviceName()
		if device_name.is_empty():
			device_name = ble.getDeviceModel()
		app_id = ble.getPackageName()
	else:
		model = OS.get_model_name() if OS.get_model_name() != "GenericDevice" else OS.get_name()
		device_name = OS.get_environment("COMPUTERNAME") if OS.has_environment("COMPUTERNAME") else OS.get_environment("HOSTNAME")
		if device_name.is_empty():
			device_name = OS.get_name()
	var platform := "desktop"
	if OS.has_feature("editor"):
		platform = "editor"
	elif OS.get_name() == "Android":
		var m := model.to_lower()
		platform = "quest" if (m.contains("oculus") or m.contains("quest") or m.contains("meta")) else ("pico" if m.contains("pico") else "android")
	return {
		"id": OS.get_unique_id(),
		"name": device_name,
		"model": model,
		"platform": platform,
		"app": String(ProjectSettings.get_setting("application/config/name", "")),
		"app_version": String(ProjectSettings.get_setting("application/config/version", "")),
		"app_id": app_id,
		"started_at": int(Time.get_unix_time_from_system() * 1000.0),
	}


func _headset_battery() -> int:
	if OS.get_name() == "Android" and Engine.has_singleton("HexRBle"):
		return Engine.get_singleton("HexRBle").getBatteryPct()
	return -1


func _current_scene() -> Dictionary:
	var current := get_tree().current_scene
	if current == null:
		return HexRRemoteProtocol.scene_info(-1, "")
	var path := current.scene_file_path
	var index := scenes().find(path)
	if index >= 0:
		return HexRRemoteProtocol.scene_info(index, HexRRemoteProtocol.scene_display_name(path))
	return HexRRemoteProtocol.scene_info(-1, HexRRemoteProtocol.scene_display_name(path) if not path.is_empty() else String(current.name))


## The floating menu's rule: switching to the scene already open does nothing.
func _load_scene(index: int) -> void:
	var list := scenes()
	var current := get_tree().current_scene
	if current and current.scene_file_path == list[index]:
		return
	get_tree().change_scene_to_file(list[index])
