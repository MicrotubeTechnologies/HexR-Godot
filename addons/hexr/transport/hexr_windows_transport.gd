class_name HexRWindowsTransport
extends HexRBleTransport
## Bluetooth through the HexRBleWinRT GDExtension (addons/hexr/bin/windows). Works in the editor
## and in Windows builds.
##
## WinRT reports from its own threads, so the extension queues events and [method poll] drains
## them here, on the main thread.

var _native: Object
var _scanning := false


func _init(native: Object) -> void:
	_native = native


func get_kind() -> String:
	return "windows"


func is_available() -> bool:
	return _native.is_available()


func get_unavailable_reason() -> String:
	return _native.get_last_error()


func start_scan(timeout_ms: int = 8000) -> void:
	_scanning = true
	_native.start_scan(timeout_ms)


func stop_scan() -> void:
	_native.stop_scan()


func is_scanning() -> bool:
	return _scanning


func connect_device(id: String) -> void:
	_native.connect_device(id)


func disconnect_device(id: String) -> void:
	_native.disconnect_device(id)


func is_device_connected(id: String) -> bool:
	return _native.is_device_connected(id)


func write(id: String, data: PackedByteArray, purge: bool = false) -> bool:
	return _native.write(id, data, purge)


func get_mtu(id: String) -> int:
	return _native.get_mtu(id)


func poll(_now_ms: int) -> void:
	for e: Dictionary in _native.poll_events():
		match e.get("type", ""):
			"device_found":
				device_found.emit(e["id"], e.get("name", ""), int(e.get("rssi", 0)))
			"scan_finished":
				_scanning = false
				scan_finished.emit(e.get("error", ""))
			"connected":
				connected.emit(e["id"], int(e.get("mtu", 23)))
			"connect_failed":
				connect_failed.emit(e["id"], e.get("reason", ""))
			"disconnected":
				disconnected.emit(e["id"], e.get("reason", ""))
			"notified":
				notified.emit(e["id"], e["data"])


func shutdown() -> void:
	_native.shutdown()
