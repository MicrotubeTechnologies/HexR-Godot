class_name HexRManager
extends Node
## The HexR autoload, [code]HexR[/code]: both gloves, their Bluetooth link and the scene's
## Pressure Controllers. Port of the Unity package's HexRManager.
##
## [codeblock]
## HexR.connect_hand(HaptGloveHandler.HandType.LEFT)
## HexR.glove_connected.connect(func(hand): print(HexRTypes.hand_name(hand), " connected"))
## HexR.controller(HaptGloveHandler.HandType.LEFT).single_index_haptic(0.8)
## [/codeblock]
##
## It survives scene changes, as autoloads do. Scenes bring their own rig (tracked hands and
## Pressure Controllers), which registers itself here.

signal glove_connected(hand: int)
## A glove's link went down. [method is_hand_connecting] is true if it is reconnecting by itself.
signal glove_disconnected(hand: int)
## One connect attempt failed; the campaign may still retry.
signal glove_connect_failed(hand: int)
## A connect campaign ended without a connection: it gave up, was cancelled or was not permitted.
signal connect_attempt_ended(hand: int)
signal battery_state_changed(hand: int, state: int)
signal pump_changed(hand: int, on: bool)
## A glove's status text changed (what the floating menu shows).
signal status_changed(hand: int, text: String)
## A device was seen during a scan. For building a device picker.
signal device_found(id: String, device_name: String, rssi: int)
## A Pressure Controller registered or unregistered.
signal controllers_changed

## The addon's version.
const VERSION := "0.2.0"
## The HexR Remote protocol level this addon implements (the Unity package version it matches).
const PROTOCOL_VERSION := "0.10.5"

var transport: HexRBleTransport
var device_store: HexRDeviceStore
## The gloves (Unity [code]leftHand[/code] / [code]rightHand[/code]).
var left_hand: HaptGloveHandler
var right_hand: HaptGloveHandler
## The scene's Pressure Controllers, set when they enter the tree.
var left_controller: PressureTrackerMain
var right_controller: PressureTrackerMain
## The scene's tracked hands, set when they enter the tree.
var left_tracked_hand: HexRTrackedHand
var right_tracked_hand: HexRTrackedHand
## Shows or hides the touch points on both hands (the floating menu's Show Colliders).
var colliders_visualizer: HaptGloveCollidersVisualizer
## When false, nothing advances until [method tick] is called (tests drive time themselves).
var drive_from_process := true

static var _instance: HexRManager
## The running HexR manager (Unity [code]HexRManager.Instance[/code]): the HexR autoload, or one
## made current with [method make_current]. Null when there is none.
static var instance: HexRManager:
	get:
		return _instance if is_instance_valid(_instance) else null
	set(_value):
		push_error("HexRManager.instance is read-only; call make_current() instead.")

var _scan_waiters: Array[HaptGloveHandler] = []
var _permission_waiters: Array[HaptGloveHandler] = []
var _awaiting_permission := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	colliders_visualizer = HaptGloveCollidersVisualizer.new()
	colliders_visualizer.name = "HaptGloveCollidersVisualizer"
	add_child(colliders_visualizer)


## The running HexR manager: the HexR autoload, or one made current with [method make_current].
## Addon scripts use this rather than the autoload's name.
static func get_instance() -> HexRManager:
	return instance


## Makes this manager the one components talk to (tests, editor tools).
func make_current() -> void:
	_instance = self


func _enter_tree() -> void:
	if get_instance() == null:
		_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	if transport == null:
		setup(HexRBleTransport.create(), HexRDeviceStore.new())
	# The editor's HexR dock can drive the gloves of a running game (also on a headset) through
	# the debugger connection.
	if EngineDebugger.is_active() and not Engine.is_editor_hint():
		EngineDebugger.register_message_capture("hexr", _on_debugger_message)


var _debugger_report_at := 0


func _on_debugger_message(message: String, data: Array) -> bool:
	match message:
		"toggle":
			toggle_hand(data[0])
		"press":
			var g := glove(data[0])
			g.bt_send(g.haptics.hexr_pressure(data[1], true, data[2], 1.0))
		"vibrate":
			var g := glove(data[0])
			g.bt_send(g.haptics.hexr_vibration(data[1], true, data[2], data[3]))
		"release":
			glove(data[0]).release_all_channels()
		# The Haptics Tester's call: [hand, finger, vibration, on, intensity, speed or Hz, bypass]
		"custom":
			_tester_call(data[0], data[1], data[2], data[3], data[4], data[5], data[6])
		"all_off":
			var c := controller(data[0])
			if c:
				c.remove_all_haptics()
				c.remove_all_vibrations()
			else:
				glove(data[0]).release_all_channels()
		_:
			return false
	return true


## What the HexR Tools Haptics Tester sends: through the hand's Pressure Controller when the scene
## has one (so the hand-near check applies unless bypassed), straight to the glove otherwise.
func _tester_call(hand: int, finger: int, vibration: bool, on: bool, intensity: float, value: float, bypass: bool) -> void:
	var c := controller(hand)
	if c:
		if vibration:
			c.custom_single_vibrations(finger, on, intensity, value, bypass)
		else:
			c.custom_single_haptics(finger, on, intensity, value, bypass)
		return
	var g := glove(hand)
	if vibration:
		g.bt_send(g.haptics.hexr_vibration(finger, on, value, intensity))
	else:
		g.bt_send(g.haptics.hexr_pressure(finger, on, intensity, value))


func _report_to_debugger(now_ms: int) -> void:
	if now_ms < _debugger_report_at:
		return
	_debugger_report_at = now_ms + 250
	var hands := []
	for g in [left_hand, right_hand]:
		hands.append([g.ble_connected, is_hand_connecting(g.which_hand), g.status_text, g.get_battery_level(), g.mtu,
				Array(g.get_air_pressure_kpa()), g.decoder.bad_frames])
	EngineDebugger.send_message("hexr:status", [transport.get_kind(), hands])


## Uses [param p_transport] for both gloves. Called automatically with the platform's transport;
## call it first to supply another (tests, simulated gloves).
func setup(p_transport: HexRBleTransport, store: HexRDeviceStore) -> void:
	if transport != null:
		shutdown()
		_disconnect_transport()
	transport = p_transport
	device_store = store
	if left_hand == null:
		left_hand = _make_glove(HaptGloveHandler.HandType.LEFT)
		right_hand = _make_glove(HaptGloveHandler.HandType.RIGHT)
	for g in [left_hand, right_hand]:
		g.setup(g.which_hand, self, transport, store)
	transport.device_found.connect(_on_device_found)
	transport.scan_finished.connect(_on_scan_finished)
	transport.connected.connect(_on_connected)
	transport.connect_failed.connect(_on_connect_failed)
	transport.disconnected.connect(_on_disconnected)
	transport.notified.connect(_on_notified)
	transport.permissions_result.connect(_on_permissions_result)


func _make_glove(hand: int) -> HaptGloveHandler:
	var g := HaptGloveHandler.new()
	g.which_hand = hand as HaptGloveHandler.HandType
	add_child(g)
	g.bluetooth_connected.connect(glove_connected.emit)
	g.bluetooth_disconnected.connect(glove_disconnected.emit)
	g.bluetooth_connection_failed.connect(glove_connect_failed.emit)
	g.connect_campaign_ended.connect(connect_attempt_ended.emit)
	g.battery_state_changed.connect(battery_state_changed.emit)
	g.pump_changed.connect(pump_changed.emit)
	g.status_changed.connect(status_changed.emit)
	return g


func _disconnect_transport() -> void:
	for pair in [[transport.device_found, _on_device_found], [transport.scan_finished, _on_scan_finished],
			[transport.connected, _on_connected], [transport.connect_failed, _on_connect_failed],
			[transport.disconnected, _on_disconnected], [transport.notified, _on_notified],
			[transport.permissions_result, _on_permissions_result]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _process(_delta: float) -> void:
	if drive_from_process:
		tick(Time.get_ticks_msec())


## Advances the transport and both gloves to [param now_ms].
func tick(now_ms: int) -> void:
	if transport == null:
		return
	transport.poll(now_ms)
	left_hand.tick(now_ms)
	right_hand.tick(now_ms)
	if EngineDebugger.is_active() and not Engine.is_editor_hint():
		_report_to_debugger(now_ms)


# -- connecting -----------------------------------------------------------------------------

func glove(hand: int) -> HaptGloveHandler:
	return left_hand if hand == HaptGloveHandler.HandType.LEFT else right_hand


## Connects that hand's glove, asking for Bluetooth permission first where the platform needs it.
## Does nothing if it is connected or already connecting, so it is safe to call at any time.
func connect_hand(hand: int) -> void:
	var g := glove(hand)
	if g.ble_connected or is_hand_connecting(hand):
		return
	_begin(g)


## Releases every channel on that hand's glove and disconnects it, or cancels a connect in
## progress.
func disconnect_hand(hand: int) -> void:
	var g := glove(hand)
	if _permission_waiters.has(g):
		_permission_waiters.erase(g)
		g._permission_denied()
	elif g.ble_connected:
		g.bt_connection()
	elif g.is_connecting():
		g.cancel_connect()


## Starts connecting that hand's glove, asking for Bluetooth permission first where the platform
## needs it (Unity [code]BeginConnect[/code]). [method connect_hand] is the safe version: it does
## nothing for a glove that is connected or connecting.
func begin_connect(hand: int) -> void:
	_begin(glove(hand))


## What the menu's left glove button does: connect, cancel a connect in progress, or disconnect
## (Unity [code]ConnectLeftBT[/code]).
func connect_left_bt() -> void:
	toggle_hand(HaptGloveHandler.HandType.LEFT)


## What the menu's right glove button does (Unity [code]ConnectRightBT[/code]).
func connect_right_bt() -> void:
	toggle_hand(HaptGloveHandler.HandType.RIGHT)


## What a menu's Connect button does: connect, cancel a connect in progress, or disconnect.
func toggle_hand(hand: int) -> void:
	var g := glove(hand)
	if g.ble_connected or g.is_connecting() or _permission_waiters.has(g):
		disconnect_hand(hand)
	else:
		_begin(g)


func is_hand_connected(hand: int) -> bool:
	return glove(hand).ble_connected


## True while waiting for permission, scanning, connecting or waiting to retry.
func is_hand_connecting(hand: int) -> bool:
	var g := glove(hand)
	return _permission_waiters.has(g) or g.is_connecting()


func _begin(g: HaptGloveHandler) -> void:
	if not transport.is_available():
		g._unavailable(transport.get_unavailable_reason())
		return
	if transport.needs_permissions():
		if not _permission_waiters.has(g):
			_permission_waiters.append(g)
		g._set_status("Waiting for Bluetooth permission…")
		if not _awaiting_permission:
			_awaiting_permission = true
			transport.request_permissions()
		return
	g.bt_connection()


func _on_permissions_result(granted: bool) -> void:
	_awaiting_permission = false
	var waiters := _permission_waiters.duplicate()
	_permission_waiters.clear()
	for g: HaptGloveHandler in waiters:
		if granted:
			g.bt_connection()
		else:
			g._permission_denied()


# -- scanning (one scan serves both hands) --------------------------------------------------

func _request_scan(g: HaptGloveHandler) -> void:
	if not _scan_waiters.has(g):
		_scan_waiters.append(g)
	if not transport.is_scanning():
		transport.start_scan(HaptGloveHandler.SCAN_TIMEOUT_MS)


func _cancel_scan(g: HaptGloveHandler) -> void:
	_scan_waiters.erase(g)
	if _scan_waiters.is_empty() and transport.is_scanning():
		transport.stop_scan()


func _on_device_found(id: String, device_name: String, rssi: int) -> void:
	device_found.emit(id, device_name, rssi)
	for g in [left_hand, right_hand]:
		if HexRTypes.hand_from_device_name(device_name) == g.which_hand:
			g.device_found.emit(id, device_name)
	for g: HaptGloveHandler in _scan_waiters.duplicate():
		if g._offer_device(id, device_name):
			_scan_waiters.erase(g)
	if _scan_waiters.is_empty() and transport.is_scanning():
		transport.stop_scan()


func _on_scan_finished(error: String) -> void:
	var waiters := _scan_waiters.duplicate()
	_scan_waiters.clear()
	for g: HaptGloveHandler in waiters:
		g._on_scan_ended(error)


# -- transport events -----------------------------------------------------------------------

func _glove_for_id(id: String) -> HaptGloveHandler:
	if left_hand._owns(id):
		return left_hand
	if right_hand._owns(id):
		return right_hand
	return null


func _on_connected(id: String, mtu: int) -> void:
	var g := _glove_for_id(id)
	if g == null:
		# Nobody is waiting for this link any more (cancelled while it was being made).
		transport.disconnect_device(id)
		return
	g._on_transport_connected(id, mtu)


func _on_connect_failed(id: String, reason: String) -> void:
	var g := _glove_for_id(id)
	if g:
		g._on_transport_connect_failed(id, reason)


func _on_disconnected(id: String, reason: String) -> void:
	var g := _glove_for_id(id)
	if g:
		g._on_transport_disconnected(id, reason)


func _on_notified(id: String, data: PackedByteArray) -> void:
	var g := _glove_for_id(id)
	if g:
		g._on_notified(data)


# -- Pressure Controllers -------------------------------------------------------------------

## The Pressure Controller for [param hand], or null if the scene has none.
func controller(hand: int) -> PressureTrackerMain:
	return left_controller if hand == HaptGloveHandler.HandType.LEFT else right_controller


## The tracked hand for [param hand], or null if the scene has none.
func tracked_hand(hand: int) -> HexRTrackedHand:
	return left_tracked_hand if hand == HaptGloveHandler.HandType.LEFT else right_tracked_hand


## How curled each finger of [param hand] is, or null without a tracked hand.
func finger_use(hand: int) -> FingerUseTracking:
	var h := tracked_hand(hand)
	return h.finger_use if h else null


func _register_hand(h: HexRTrackedHand) -> void:
	if h.hand_type == HaptGloveHandler.HandType.LEFT:
		left_tracked_hand = h
	else:
		right_tracked_hand = h


func _unregister_hand(h: HexRTrackedHand) -> void:
	if left_tracked_hand == h:
		left_tracked_hand = null
	if right_tracked_hand == h:
		right_tracked_hand = null


func _register_controller(c: PressureTrackerMain, hand: int) -> void:
	if hand == HaptGloveHandler.HandType.LEFT:
		left_controller = c
	else:
		right_controller = c
	controllers_changed.emit()


func _unregister_controller(c: Node) -> void:
	if left_controller == c:
		left_controller = null
	if right_controller == c:
		right_controller = null
	controllers_changed.emit()


# -- shutdown -------------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		shutdown()


## Releases and disconnects both gloves.
func shutdown() -> void:
	if transport == null:
		return
	for g in [left_hand, right_hand]:
		if g != null:
			g.shutdown("quit")
	_scan_waiters.clear()
	_permission_waiters.clear()
