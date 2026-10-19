class_name HexRAndroidTransport
extends HexRBleTransport
## Bluetooth through the HexRBle Android plugin (addons/hexr/android/bin/hexr-ble-*.aar).
##
## The plugin is a GATT client written for the glove: it subscribes once per connection, writes
## with response one at a time, cuts writes to the negotiated MTU, and writes the pause-release
## frame itself when the app is paused (scripts do not run then). Its signals arrive on the main
## thread; this class re-emits them.

var _plugin: Object
var _scanning := false


func _init(plugin: Object) -> void:
	_plugin = plugin
	_plugin.connect("device_found", func(id: String, n: String, rssi: int) -> void: device_found.emit(id, n, rssi))
	_plugin.connect("scan_finished", _on_scan_finished)
	_plugin.connect("connected", func(id: String, mtu: int) -> void: connected.emit(id, mtu))
	_plugin.connect("connect_failed", func(id: String, why: String) -> void: connect_failed.emit(id, why))
	_plugin.connect("disconnected", func(id: String, why: String) -> void: disconnected.emit(id, why))
	_plugin.connect("notified", func(id: String, data: PackedByteArray) -> void: notified.emit(id, data))
	_plugin.connect("permissions_result", func(granted: bool) -> void: permissions_result.emit(granted))


func _on_scan_finished(error: String) -> void:
	_scanning = false
	scan_finished.emit(error)


func get_kind() -> String:
	return "android"


func is_available() -> bool:
	return _plugin.isAdapterEnabled()


func get_unavailable_reason() -> String:
	return "Bluetooth is off" if not _plugin.isAdapterEnabled() else ""


func needs_permissions() -> bool:
	return not _plugin.hasPermissions()


func request_permissions() -> void:
	_plugin.requestPermissions()


func start_scan(timeout_ms: int = 8000) -> void:
	_scanning = true
	_plugin.startScan(timeout_ms)


func stop_scan() -> void:
	_plugin.stopScan()


func is_scanning() -> bool:
	return _scanning


func connect_device(id: String) -> void:
	_plugin.connectDevice(id)


func disconnect_device(id: String) -> void:
	_plugin.disconnectDevice(id)


func is_device_connected(id: String) -> bool:
	return _plugin.isConnected(id)


func write(id: String, data: PackedByteArray, purge: bool = false) -> bool:
	return _plugin.write(id, data, purge)


func get_mtu(id: String) -> int:
	return _plugin.getMtu(id)


func set_pause_release_frame(id: String, data: PackedByteArray) -> void:
	_plugin.setPauseReleaseFrame(id, data)


func clock_us() -> int:
	return _plugin.clockUs()


func shutdown() -> void:
	_plugin.shutdown()
