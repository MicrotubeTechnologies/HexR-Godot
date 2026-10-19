class_name HexRBleTransport
extends RefCounted
## The Bluetooth LE link to the gloves. One transport serves both hands.
##
## [method create] picks the implementation for the platform: the HexRBle Android plugin, the
## HexRBleWinRT GDExtension on Windows, or [HexRSimulatedTransport] where neither exists. Every
## implementation follows the same rules, which the glove's firmware depends on:
## [br]- subscribe to notifications exactly once per connection, as part of connecting;
## [br]- write with response, and cut each write on frame boundaries to fit MTU - 3;
## [br]- [signal disconnected] fires only for a link lost on its own, never for
## [method disconnect_device].
##
## All signals are emitted on the main thread, from [method poll] or from the platform's own
## main-thread callback.

## A device advertised during a scan. [param id] is what [method connect_device] takes.
signal device_found(id: String, device_name: String, rssi: int)
## The scan stopped. [param error] is empty when it ran its course or was stopped.
signal scan_finished(error: String)
## The link is up and notifications are subscribed.
signal connected(id: String, mtu: int)
## A connect attempt ended without a link.
signal connect_failed(id: String, reason: String)
## An established link was lost without [method disconnect_device].
signal disconnected(id: String, reason: String)
## A notification arrived from the glove.
signal notified(id: String, data: PackedByteArray)
## The answer to [method request_permissions].
signal permissions_result(granted: bool)

const PROJECT_SETTING_FORCE_SIMULATED := "hexr/bluetooth/force_simulated"


## Picks the transport for this platform. Native classes are looked up by name so this script
## still loads where they are missing.
static func create() -> HexRBleTransport:
	if ProjectSettings.get_setting(PROJECT_SETTING_FORCE_SIMULATED, false):
		return HexRSimulatedTransport.new()
	if OS.get_name() == "Android" and Engine.has_singleton("HexRBle"):
		return HexRAndroidTransport.new(Engine.get_singleton("HexRBle"))
	if OS.get_name() == "Windows" and ClassDB.class_exists("HexRBleWinRT"):
		var native: Object = ClassDB.instantiate("HexRBleWinRT")
		if native != null:
			return HexRWindowsTransport.new(native)
	return HexRSimulatedTransport.new()


## "android", "windows" or "simulated".
func get_kind() -> String:
	return "none"


## False when the platform has no usable Bluetooth (no adapter, or it is switched off).
func is_available() -> bool:
	return false


## Why [method is_available] is false, for status text.
func get_unavailable_reason() -> String:
	return ""


## True if [method request_permissions] must be answered before scanning.
func needs_permissions() -> bool:
	return false


func request_permissions() -> void:
	permissions_result.emit(true)


func start_scan(_timeout_ms: int = 8000) -> void:
	pass


func stop_scan() -> void:
	pass


func is_scanning() -> bool:
	return false


func connect_device(_id: String) -> void:
	pass


## Writes any queued commands, then closes the link. Emits nothing.
func disconnect_device(_id: String) -> void:
	pass


func is_device_connected(_id: String) -> bool:
	return false


## Sends [param data] (one or more frames) with response, cut to fit the MTU. With
## [param purge], anything still queued for that device is dropped first (used for release).
func write(_id: String, _data: PackedByteArray, _purge: bool = false) -> bool:
	return false


## The negotiated ATT MTU, or 0 when not connected.
func get_mtu(_id: String) -> int:
	return 0


## Bytes the platform writes by itself when the app is paused (Android cannot run scripts then).
## Set it to the release frame while connected and to an empty array otherwise.
func set_pause_release_frame(_id: String, _data: PackedByteArray) -> void:
	pass


## Called every frame by HexR to deliver events.
func poll(_now_ms: int) -> void:
	pass


## Microseconds on the clock HexR Remote shares with its video and sound
## (CLOCK_MONOTONIC on Android). Any steady clock elsewhere.
func clock_us() -> int:
	return Time.get_ticks_usec()


func shutdown() -> void:
	pass
