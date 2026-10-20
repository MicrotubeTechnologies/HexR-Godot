class_name HexRRemoteCommands
extends RefCounted
## Runs a phone's requests against the gloves and the app (port of the Unity package's
## RemoteCommands). Returns "" when a request was done, or the error to send back. The wording
## matches the Unity package, so the phone shows the same messages for both.

var allow_glove_control := true
var allow_video := true
var expose_scenes := false

var _manager: Callable  # () -> HexRManager
var _stream: Object  # start(), stop(), read() -> Dictionary
var _scene_count: Callable  # () -> int
var _load_scene: Callable  # (int) -> void


func _init(manager: Callable, stream: Object, scene_count: Callable, load_scene: Callable) -> void:
	_manager = manager
	_stream = stream
	_scene_count = scene_count
	_load_scene = load_scene


func handle(req: Dictionary) -> String:
	match req["type"]:
		"glove":
			return _glove(req)
		"release":
			return _release(req)
		"scene":
			return _scene(req)
		"command":
			return _command(req)
		"stream":
			return _stream_request(req)
	return "This headset does not know the request \"%s\"." % req["type"]


func _glove(req: Dictionary) -> String:
	if not allow_glove_control:
		return "This app does not let a phone connect its gloves."
	var hand := HexRRemoteProtocol.parse_hand(req["hand"])
	if hand < 0:
		return "Say which glove: \"left\" or \"right\"."
	var hub: HexRManager = _manager.call()
	if hub == null:
		return "There is no HexR rig in this scene."
	match req["action"]:
		"connect":
			hub.connect_hand(hand)
			return ""
		"disconnect":
			if not hub.is_hand_connected(hand):
				if hub.is_hand_connecting(hand):
					return "The %s glove is still connecting. Try again once it has." % HexRRemoteProtocol.hand_name(hand)
				return ""
			hub.disconnect_hand(hand)
			return ""
	return "A glove request needs \"connect\" or \"disconnect\"."


func _release(req: Dictionary) -> String:
	if not allow_glove_control:
		return "This app does not let a phone control its gloves."
	var hub: HexRManager = _manager.call()
	if hub == null:
		return "There is no HexR rig in this scene."
	var any_hand: bool = String(req["hand"]).is_empty()
	var only := HexRRemoteProtocol.parse_hand(req["hand"])
	if not any_hand and only < 0:
		return "Say which glove: \"left\", \"right\", or neither for both."
	for hand in [HaptGloveHandler.HandType.LEFT, HaptGloveHandler.HandType.RIGHT]:
		if not any_hand and hand != only:
			continue
		var g := hub.glove(hand)
		if g and g.ble_connected:
			g.release_all_channels()
	return ""


func _scene(req: Dictionary) -> String:
	if not expose_scenes:
		return "This app does not let a phone change its scene."
	var count: int = _scene_count.call()
	var index: int = req["index"]
	if index < 0 or index >= count:
		return "This app has no scene %d." % index
	_load_scene.call(index)
	return ""


func _command(req: Dictionary) -> String:
	var action: Callable = HexRRemote.get_command(req["id"])
	if not action.is_valid():
		if HexRRemote.has_command(req["id"]):
			return "That command belonged to something no longer in the scene."
		return "This app has no command \"%s\"." % req["id"]
	# GDScript has no exceptions to catch; a command that errors logs it and the request still
	# counts as handled.
	action.call()
	return ""


func _stream_request(req: Dictionary) -> String:
	match req["action"]:
		"start":
			if not allow_video:
				return "This app does not share its view."
			_stream.start()
			return ""
		"stop":
			_stream.stop()
			return ""
	return "A stream request needs \"start\" or \"stop\"."


## Both gloves' status lines, left then right.
static func glove_status(hub: HexRManager) -> Array:
	var out := []
	for hand in [HaptGloveHandler.HandType.LEFT, HaptGloveHandler.HandType.RIGHT]:
		var side := HexRRemoteProtocol.hand_name(hand)
		if hub == null or hub.glove(hand) == null:
			out.append(HexRRemoteProtocol.glove_status(side))
			continue
		var g := hub.glove(hand)
		var connected := hub.is_hand_connected(hand)
		var state := HexRRemoteProtocol.STATE_CONNECTED if connected else (
				HexRRemoteProtocol.STATE_CONNECTING if hub.is_hand_connecting(hand) else HexRRemoteProtocol.STATE_DISCONNECTED)
		if not connected:
			out.append(HexRRemoteProtocol.glove_status(side, state, g.status_text))
			continue
		var battery := g.get_battery_level()
		var pct := clampi(HexRRemoteProtocol.round_half_even(battery * 100.0), 0, 100) if battery > 0.0 else -1
		var pressure := []
		for raw in g.decoder.pressure_raw:
			pressure.append(HexRRemoteProtocol.to_deci_kpa(raw))
		out.append(HexRRemoteProtocol.glove_status(side, state, g.status_text, pct, pressure))
	return out
