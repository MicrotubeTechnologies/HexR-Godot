class_name HexRManager
extends Node
## The HexR autoload, [code]HexR[/code]: both gloves, their Bluetooth link and the scene's
## Pressure Controllers. Port of the Unity package's HexRManager.
##
## [codeblock]
## HexR.connect_hand(HexRTypes.Hand.LEFT)
## HexR.glove_connected.connect(func(hand): print(HexRTypes.hand_name(hand), " connected"))
## HexR.controller(HexRTypes.Hand.LEFT).single_index_haptic(0.8)
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
const VERSION := "0.1.0"
## The HexR Remote protocol level this addon implements (the Unity package version it matches).
const PROTOCOL_VERSION := "0.10.5"

var transport: HexRBleTransport
var device_store: HexRDeviceStore
var left: HexRGlove
var right: HexRGlove
## The scene's Pressure Controllers, set when they enter the tree.
var left_controller: HexRPressureController
var right_controller: HexRPressureController
## The scene's tracked hands, set when they enter the tree.
var left_hand: HexRTrackedHand
var right_hand: HexRTrackedHand
## When false, nothing advances until [method tick] is called (tests drive time themselves).
var drive_from_process := true

static var _instance: HexRManager

var _scan_waiters: Array[HexRGlove] = []
var _permission_waiters: Array[HexRGlove] = []
var _awaiting_permission := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000


## The running HexR manager: the HexR autoload, or one made current with [method make_current].
## Addon scripts use this rather than the autoload's name.
static func get_instance() -> HexRManager:
	return _instance if is_instance_valid(_instance) else null


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
		_:
			return false
	return true


func _report_to_debugger(now_ms: int) -> void:
	if now_ms < _debugger_report_at:
		return
	_debugger_report_at = now_ms + 250
	var hands := []
	for g in [left, right]:
		hands.append([g.ble_connected, is_hand_connecting(g.hand), g.status_text, g.get_battery_level(), g.mtu,
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
	if left == null:
		left = _make_glove(HexRTypes.Hand.LEFT)
		right = _make_glove(HexRTypes.Hand.RIGHT)
	for g in [left, right]:
		g.setup(g.hand, self, transport, store)
	transport.device_found.connect(_on_device_found)
	transport.scan_finished.connect(_on_scan_finished)
	transport.connected.connect(_on_connected)
	transport.connect_failed.connect(_on_connect_failed)
	transport.disconnected.connect(_on_disconnected)
	transport.notified.connect(_on_notified)
	transport.permissions_result.connect(_on_permissions_result)


func _make_glove(hand: int) -> HexRGlove:
	var g := HexRGlove.new()
	g.hand = hand
	add_child(g)
	g.bluetooth_connected.connect(func() -> void: glove_connected.emit(hand))
	g.bluetooth_disconnected.connect(func() -> void: glove_disconnected.emit(hand))
	g.bluetooth_connection_failed.connect(func() -> void: glove_connect_failed.emit(hand))
	g.connect_campaign_ended.connect(func() -> void: connect_attempt_ended.emit(hand))
	g.battery_state_changed.connect(func(s: int) -> void: battery_state_changed.emit(hand, s))
	g.pump_changed.connect(func(on: bool) -> void: pump_changed.emit(hand, on))
	g.status_changed.connect(func(t: String) -> void: status_changed.emit(hand, t))
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
	left.tick(now_ms)
	right.tick(now_ms)
	if EngineDebugger.is_active() and not Engine.is_editor_hint():
		_report_to_debugger(now_ms)


# -- connecting -----------------------------------------------------------------------------

func glove(hand: int) -> HexRGlove:
	return left if hand == HexRTypes.Hand.LEFT else right


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
		g.connect_toggle()
	elif g.is_connecting():
		g.cancel_connect()


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


func _begin(g: HexRGlove) -> void:
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
	g.connect_toggle()


func _on_permissions_result(granted: bool) -> void:
	_awaiting_permission = false
	var waiters := _permission_waiters.duplicate()
	_permission_waiters.clear()
	for g: HexRGlove in waiters:
		if granted:
			g.connect_toggle()
		else:
			g._permission_denied()


# -- scanning (one scan serves both hands) --------------------------------------------------

func _request_scan(g: HexRGlove) -> void:
	if not _scan_waiters.has(g):
		_scan_waiters.append(g)
	if not transport.is_scanning():
		transport.start_scan(HexRGlove.SCAN_TIMEOUT_MS)


func _cancel_scan(g: HexRGlove) -> void:
	_scan_waiters.erase(g)
	if _scan_waiters.is_empty() and transport.is_scanning():
		transport.stop_scan()


func _on_device_found(id: String, device_name: String, rssi: int) -> void:
	device_found.emit(id, device_name, rssi)
	for g in [left, right]:
		if HexRTypes.hand_from_device_name(device_name) == g.hand:
			g.device_found.emit(id, device_name)
	for g: HexRGlove in _scan_waiters.duplicate():
		if g._offer_device(id, device_name):
			_scan_waiters.erase(g)
	if _scan_waiters.is_empty() and transport.is_scanning():
		transport.stop_scan()


func _on_scan_finished(error: String) -> void:
	var waiters := _scan_waiters.duplicate()
	_scan_waiters.clear()
	for g: HexRGlove in waiters:
		g._on_scan_ended(error)


# -- transport events -----------------------------------------------------------------------

func _glove_for_id(id: String) -> HexRGlove:
	if left._owns(id):
		return left
	if right._owns(id):
		return right
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
func controller(hand: int) -> HexRPressureController:
	return left_controller if hand == HexRTypes.Hand.LEFT else right_controller


## The tracked hand for [param hand], or null if the scene has none.
func tracked_hand(hand: int) -> HexRTrackedHand:
	return left_hand if hand == HexRTypes.Hand.LEFT else right_hand


## How curled each finger of [param hand] is, or null without a tracked hand.
func finger_use(hand: int) -> HexRFingerUseTracking:
	var h := tracked_hand(hand)
	return h.finger_use if h else null


func _register_hand(h: HexRTrackedHand) -> void:
	if h.hand == HexRTypes.Hand.LEFT:
		left_hand = h
	else:
		right_hand = h


func _unregister_hand(h: HexRTrackedHand) -> void:
	if left_hand == h:
		left_hand = null
	if right_hand == h:
		right_hand = null


func _register_controller(c: HexRPressureController, hand: int) -> void:
	if hand == HexRTypes.Hand.LEFT:
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
	for g in [left, right]:
		if g != null:
			g.shutdown("quit")
	_scan_waiters.clear()
	_permission_waiters.clear()
