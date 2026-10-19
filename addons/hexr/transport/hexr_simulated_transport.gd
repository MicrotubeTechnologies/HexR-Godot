class_name HexRSimulatedTransport
extends HexRBleTransport
## A transport with simulated gloves instead of a radio. Used by the tests, in CI, and in the
## editor or on platforms without the native Bluetooth layer.
##
## Out of the box it has no gloves, so connecting fails the way it does with the gloves switched
## off. Call [method add_glove] (or set the project setting hexr/bluetooth/simulated_gloves) to
## have gloves to connect to.

const PROJECT_SETTING_SIMULATED_GLOVES := "hexr/bluetooth/simulated_gloves"

var gloves: Dictionary = {}  # id -> HexRSimulatedGlove
## How long a scan takes to report advertising gloves.
var scan_report_delay_ms := 200

var _scanning := false
var _scan_started_ms := -1
var _scan_timeout_ms := 8000
var _scan_reported: Dictionary = {}
var _pending_connects: Dictionary = {}  # id -> due ms
var _pause_frames: Dictionary = {}
var _now_ms := 0


func _init() -> void:
	if ProjectSettings.get_setting(PROJECT_SETTING_SIMULATED_GLOVES, false):
		add_glove(HexRSimulatedGlove.new("SIM:LEFT", HexRTypes.NAME_LEFT))
		add_glove(HexRSimulatedGlove.new("SIM:RIGHT", HexRTypes.NAME_RIGHT))


func add_glove(glove: HexRSimulatedGlove) -> HexRSimulatedGlove:
	gloves[glove.id] = glove
	return glove


func get_kind() -> String:
	return "simulated"


func is_available() -> bool:
	return true


func start_scan(timeout_ms: int = 8000) -> void:
	_scanning = true
	_scan_started_ms = -1
	_scan_timeout_ms = timeout_ms
	_scan_reported.clear()


func stop_scan() -> void:
	if _scanning:
		_scanning = false
		scan_finished.emit("")


func is_scanning() -> bool:
	return _scanning


func connect_device(id: String) -> void:
	_pending_connects[id] = -1  # due time is set on the next poll


func disconnect_device(id: String) -> void:
	_pending_connects.erase(id)
	var g: HexRSimulatedGlove = gloves.get(id)
	if g and g.connected:
		g.on_disconnected()


func is_device_connected(id: String) -> bool:
	var g: HexRSimulatedGlove = gloves.get(id)
	return g != null and g.connected


func write(id: String, data: PackedByteArray, _purge: bool = false) -> bool:
	var g: HexRSimulatedGlove = gloves.get(id)
	if g == null or not g.connected:
		return false
	for chunk in HexRFrames.chunk_for_mtu(data, g.mtu - 3):
		g.receive_write(chunk)
	return true


func get_mtu(id: String) -> int:
	var g: HexRSimulatedGlove = gloves.get(id)
	return g.mtu if g != null and g.connected else 0


func set_pause_release_frame(id: String, data: PackedByteArray) -> void:
	_pause_frames[id] = data


## What the platform layer would write on pause. For tests.
func get_pause_release_frame(id: String) -> PackedByteArray:
	return _pause_frames.get(id, PackedByteArray())


func poll(now_ms: int) -> void:
	_now_ms = now_ms
	if _scanning:
		if _scan_started_ms < 0:
			_scan_started_ms = now_ms
		if now_ms - _scan_started_ms >= scan_report_delay_ms:
			for g: HexRSimulatedGlove in gloves.values():
				if g.advertising and not g.connected and not _scan_reported.has(g.id):
					_scan_reported[g.id] = true
					device_found.emit(g.id, g.device_name, g.rssi)
					if not _scanning:
						break
		if _scanning and now_ms - _scan_started_ms >= _scan_timeout_ms:
			_scanning = false
			scan_finished.emit("")

	for id in _pending_connects.keys():
		var g: HexRSimulatedGlove = gloves.get(id)
		var due: int = _pending_connects[id]
		if due < 0:
			_pending_connects[id] = now_ms + (g.connect_delay_ms if g else 300)
			continue
		if now_ms < due:
			continue
		_pending_connects.erase(id)
		if g == null or not g.advertising:
			connect_failed.emit(id, "not found")
		elif g.fail_next_connects > 0:
			g.fail_next_connects -= 1
			connect_failed.emit(id, "GATT error 133")
		else:
			g.on_connected()
			g.on_subscribed()  # subscribed once, as part of connecting
			connected.emit(id, g.mtu)

	for g: HexRSimulatedGlove in gloves.values():
		if g.connected and g.drop_at_ms >= 0 and now_ms >= g.drop_at_ms:
			g.drop_at_ms = -1
			g.on_disconnected()
			disconnected.emit(g.id, "link lost")
			continue
		for n in g.tick(now_ms):
			notified.emit(g.id, n)


func clock_us() -> int:
	return _now_ms * 1000
