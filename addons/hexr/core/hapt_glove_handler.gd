class_name HaptGloveHandler
extends Node
## One glove: its Bluetooth connection, the commands sent to it and the readings it sends back.
## Port of the Unity package's HaptGloveHandler. Reach them as [code]HexR.left_hand[/code] and
## [code]HexR.right_hand[/code].
##
## Connecting runs a campaign: it scans (or connects straight to the remembered glove), and
## when an attempt fails it retries after 1, 2, 4, 8, 8... seconds, giving up after 60 s. A
## glove that drops reopens a campaign by itself. Calling [method bt_connection] while a
## campaign runs cancels it; on a connected glove it disconnects.
##
## Before the link closes, on pause and on quit, every channel is released: once disconnected
## the glove keeps whatever it was last told.

## Which hand a glove, controller or touch point belongs to.
enum HandType { LEFT, RIGHT }

## The glove's battery, from its battery level.
enum BatteryState { FULL, MEDIUM, LOW }

## The link is up (Unity [code]onBluetoothConnected[/code]).
signal bluetooth_connected(hand: int)
## The link went down, whether asked for or lost. [method is_connecting] tells them apart: it is
## true after a drop, because a reconnect campaign has started.
signal bluetooth_disconnected(hand: int)
## One connect attempt failed. More may follow; see [signal connect_campaign_ended].
signal bluetooth_connection_failed(hand: int)
## The connect campaign ended without a connection (gave up, cancelled or not permitted).
signal connect_campaign_ended(hand: int)
## The air pump started or stopped (Unity [code]onPumpAction[/code]).
signal pump_changed(hand: int, on: bool)
signal battery_state_changed(hand: int, state: int)
## A glove for this hand was seen during a scan (Unity [code]onDeviceFound[/code]).
signal device_found(id: String, device_name: String)
## [member status_text] changed.
signal status_changed(hand: int, text: String)

const RETRY_BACKOFF_S: Array[float] = [1.0, 2.0, 4.0, 8.0]
const RETRY_GIVE_UP_MS := 60000
const ATTEMPT_TIMEOUT_MS := 20000
const SCAN_TIMEOUT_MS := 8000
const PUMP_START_DELAY_MS := 2000
const BATTERY_CHECK_MS := 1000
## Notifications need MTU 77 to carry the glove's 74-byte bundle.
const TELEMETRY_MIN_MTU := 77

## Which hand this glove is.
var which_hand: HandType = HandType.LEFT
## Builds the commands and records the last one per channel.
var haptics := Haptics.new()
## The glove's latest readings.
var decoder := HexRFrameDecoder.new()
## Batches commands into at most one write per interval.
var coalescer := HexRWriteCoalescer.new()

## Release every channel when the app is paused (on a headset, when it is taken off). A paused
## app cannot release anything itself, so without this the glove keeps pressing until it resumes.
var release_when_paused := true:
	set(v):
		release_when_paused = v
		_update_pause_frame()
## Match [member optional_custom_device_name] instead of "HaptGloveAR Left/Right".
var use_custom_device_name := false
var optional_custom_device_name := ""
## Air source pressure sent with the pump command.
var source_pressure := 80
## Send the pump command 2 s after connecting, as the Unity package does.
var auto_start_pump := true
## Log connection steps.
var verbose := false

## True while the link is up.
var ble_connected := false
## The connected glove's id.
var device_id := ""
## The negotiated MTU while connected.
var mtu := 0
## Human-readable connection status, for menus.
var status_text := ""
var battery_state: int = HaptGloveHandler.BatteryState.FULL

var _transport: HexRBleTransport
var _store: HexRDeviceStore
var _hub: Object  # HexRManager
var _now_ms := 0
var _connect_requested := false
var _retry_at_ms := -1
var _retry_attempt := 0
var _campaign_started_ms := 0
var _watchdog_at_ms := -1
var _awaiting_scan := false
var _connecting_id := ""
var _direct_attempt := false
var _pump_at_ms := -1
var _pump_started := false
var _battery_check_at_ms := 0
var _battery_known := false
var _battery_interval_ms := BATTERY_CHECK_MS

static var _release_bytes := PackedByteArray()


func setup(p_hand: int, hub: Object, transport: HexRBleTransport, store: HexRDeviceStore) -> void:
	which_hand = p_hand as HandType
	_hub = hub
	_transport = transport
	_store = store
	_now_ms = Time.get_ticks_msec()
	name = "%sGlove" % HexRTypes.hand_name(which_hand)
	var interval := 100 if transport.get_kind() in ["android", "simulated"] else 0
	coalescer.min_interval_ms = int(ProjectSettings.get_setting("hexr/bluetooth/min_write_interval_ms", interval))


## The advertised name this glove matches.
func target_device_name() -> String:
	if use_custom_device_name and not optional_custom_device_name.is_empty():
		return optional_custom_device_name
	return HexRTypes.default_device_name(which_hand)


func side() -> String:
	return HexRTypes.hand_name(which_hand)


# -- connection -----------------------------------------------------------------------------

## Connects, cancels a campaign in progress, or disconnects, depending on the state (Unity
## [code]BTConnection[/code]). Prefer [method HexRManager.connect_hand], which also asks for
## Bluetooth permission.
func bt_connection() -> void:
	if ble_connected:
		_log("disconnect requested")
		_connect_requested = false
		_retry_attempt = 0
		_retry_at_ms = -1
		_watchdog_at_ms = -1
		_release_all_now("disconnect")
		var id := device_id
		_transport.set_pause_release_frame(id, PackedByteArray())
		_link_down()
		_transport.disconnect_device(id)
		_set_status("%s disconnected" % side())
		bluetooth_disconnected.emit(which_hand)
	elif is_connecting():
		cancel_connect()
	else:
		_start_attempt()


## Releases every channel and closes the link, or stops a connect campaign in progress
## (Unity [code]BTDisconnection[/code]). Does nothing when idle.
func bt_disconnection() -> void:
	if ble_connected:
		bt_connection()
	elif is_connecting():
		cancel_connect()


## How often the battery level is checked, in seconds (Unity
## [code]SetBatteryLevelUpdateInterval[/code]).
func set_battery_level_update_interval(seconds: float) -> void:
	_battery_interval_ms = maxi(100, int(seconds * 1000.0))
	_battery_check_at_ms = mini(_battery_check_at_ms, _now_ms + _battery_interval_ms)


## Stops a connect campaign. Does nothing when connected or idle.
func cancel_connect() -> void:
	if ble_connected or not is_connecting():
		return
	_log("connect cancelled")
	_abort_in_flight()
	_connect_requested = false
	_retry_at_ms = -1
	_watchdog_at_ms = -1
	_retry_attempt = 0
	_set_status("Cancelled, tap to retry")
	connect_campaign_ended.emit(which_hand)


## True while a connect campaign is under way: scanning, connecting or waiting to retry.
func is_connecting() -> bool:
	if ble_connected:
		return false
	return _connect_requested or _retry_at_ms >= 0 or _awaiting_scan or not _connecting_id.is_empty()


func get_remembered_device_id() -> String:
	return _store.get_device(_transport.get_kind(), which_hand) if _store else ""


## Targets this physical glove from now on (for example one picked from [signal device_found]).
func remember_device(id: String) -> void:
	if _store:
		_store.set_device(_transport.get_kind(), which_hand, id)


func forget_device() -> void:
	if _store:
		_store.set_device(_transport.get_kind(), which_hand, "")


## Remembers [param id] and connects to it.
func connect_to_device(id: String) -> void:
	remember_device(id)
	if not ble_connected and not is_connecting():
		bt_connection()


func _start_attempt() -> void:
	if not _connect_requested:
		_retry_attempt = 0  # a fresh campaign, not a scheduled retry
	_connect_requested = true
	_watchdog_at_ms = _now_ms + ATTEMPT_TIMEOUT_MS
	var remembered := get_remembered_device_id()
	if not remembered.is_empty():
		# Straight to the glove seen before: no scan, which is most of the reconnect time.
		_set_status("Connecting to %s…" % target_device_name())
		_direct_attempt = true
		_begin_connect(remembered)
	else:
		_start_scan()


func _start_scan() -> void:
	_log("scanning for \"%s\"" % target_device_name())
	_set_status("Searching for HexR %s…" % side())
	_awaiting_scan = true
	_hub._request_scan(self)


func _begin_connect(id: String) -> void:
	_log("connecting to " + id)
	_connecting_id = id
	_transport.connect_device(id)


func _abort_in_flight() -> void:
	if _awaiting_scan:
		_awaiting_scan = false
		_hub._cancel_scan(self)
	if not _connecting_id.is_empty():
		_transport.disconnect_device(_connecting_id)
		_connecting_id = ""
	_direct_attempt = false


## Offered each device the scan finds. Returns true if this glove takes it.
func _offer_device(id: String, device_name: String) -> bool:
	if not _awaiting_scan:
		return false
	var remembered := get_remembered_device_id()
	var hit := id == remembered if not remembered.is_empty() else device_name.contains(target_device_name())
	if not hit:
		return false
	_awaiting_scan = false
	_begin_connect(id)
	return true


func _on_scan_ended(error: String) -> void:
	if not _awaiting_scan:
		return
	_awaiting_scan = false
	_attempt_failed(error if not error.is_empty() else "not found")


func _owns(id: String) -> bool:
	return id == _connecting_id or (ble_connected and id == device_id)


func _on_transport_connected(id: String, p_mtu: int) -> void:
	_log("connected to %s, MTU %d" % [id, p_mtu])
	_connecting_id = ""
	_direct_attempt = false
	ble_connected = true
	device_id = id
	mtu = p_mtu
	remember_device(id)
	_connect_requested = false
	_retry_attempt = 0
	_retry_at_ms = -1
	_watchdog_at_ms = -1
	decoder.reset()
	coalescer.clear()
	_pump_started = false
	_battery_known = false
	_pump_at_ms = _now_ms + PUMP_START_DELAY_MS if auto_start_pump else -1
	_update_pause_frame()
	if p_mtu > 0 and p_mtu < TELEMETRY_MIN_MTU:
		push_warning("[HexR] %s glove link has MTU %d: haptics work, but pressure and battery readings will be cut short." % [side(), p_mtu])
	_set_status("%s connected — starting up…" % side())
	bluetooth_connected.emit(which_hand)


func _on_transport_connect_failed(_id: String, reason: String) -> void:
	_connecting_id = ""
	if _direct_attempt:
		# The remembered glove did not answer (switched off, or out of range). Scan instead.
		_direct_attempt = false
		_log("direct connect failed (%s), scanning" % reason)
		if _connect_requested:
			_start_scan()
		return
	_attempt_failed(reason)


func _on_transport_disconnected(id: String, reason: String) -> void:
	if not ble_connected or id != device_id:
		return
	_log("link lost: " + reason)
	_link_down()
	# Reopen a campaign before telling anyone, so listeners see is_connecting() == true.
	_connect_requested = true
	_retry_attempt = 0
	_set_status("%s disconnected — reconnecting…" % side())
	bluetooth_disconnected.emit(which_hand)
	_schedule_retry("")


func _on_notified(data: PackedByteArray) -> void:
	decoder.feed(data)


func _attempt_failed(reason: String) -> void:
	_log("attempt failed: " + reason)
	ble_connected = false
	bluetooth_connection_failed.emit(which_hand)
	_schedule_retry("%s not found" % side())


## Arms the next attempt. [param why] prefixes the status ("… — retrying in 2 s"); empty keeps
## the status as it is.
func _schedule_retry(why: String) -> void:
	if not _connect_requested:
		return
	_retry_at_ms = -1
	if _retry_attempt == 0:
		_campaign_started_ms = _now_ms
	elif _now_ms - _campaign_started_ms >= RETRY_GIVE_UP_MS:
		_log("giving up after %d s" % (RETRY_GIVE_UP_MS / 1000))
		_connect_requested = false
		_retry_attempt = 0
		_watchdog_at_ms = -1
		_set_status("%s not found — check Bluetooth permissions, then try again" % side())
		connect_campaign_ended.emit(which_hand)
		return
	var delay: float = RETRY_BACKOFF_S[mini(_retry_attempt, RETRY_BACKOFF_S.size() - 1)]
	_retry_attempt += 1
	_retry_at_ms = _now_ms + int(delay * 1000.0)
	if not why.is_empty():
		_set_status("%s — retrying in %d s…" % [why, int(delay)])


func _permission_denied() -> void:
	_connect_requested = false
	_set_status("%s blocked — allow %s in system settings, then try again"
			% [side(), _transport.permission_name() if _transport else "Bluetooth"])
	bluetooth_connection_failed.emit(which_hand)
	connect_campaign_ended.emit(which_hand)


func _unavailable(reason: String) -> void:
	_connect_requested = false
	_set_status("Bluetooth unavailable" + ("" if reason.is_empty() else ": " + reason))
	bluetooth_connection_failed.emit(which_hand)
	connect_campaign_ended.emit(which_hand)


func _link_down() -> void:
	ble_connected = false
	mtu = 0
	coalescer.clear()
	_pump_at_ms = -1
	if _pump_started:
		_pump_started = false
		pump_changed.emit(which_hand, false)


# -- per frame ------------------------------------------------------------------------------

## Advances timers and flushes queued commands. HexR calls this every frame.
func tick(now_ms: int) -> void:
	_now_ms = now_ms
	if _retry_at_ms >= 0 and now_ms >= _retry_at_ms:
		_retry_at_ms = -1
		_start_attempt()
	if _watchdog_at_ms >= 0 and now_ms >= _watchdog_at_ms:
		_watchdog_at_ms = -1
		# Nothing resolved this attempt in 20 s: the platform went silent. Start again.
		if _connect_requested and not ble_connected and _retry_at_ms < 0:
			_log("attempt timed out")
			_abort_in_flight()
			_schedule_retry("Connection attempt timed out")
	if not ble_connected:
		return
	var due := coalescer.take_due(now_ms)
	if not due.is_empty():
		_transport.write(device_id, due)
	if _pump_at_ms >= 0 and now_ms >= _pump_at_ms:
		_pump_at_ms = -1
		_start_pump()
	if now_ms >= _battery_check_at_ms:
		_battery_check_at_ms = now_ms + _battery_interval_ms
		_check_battery()


func _check_battery() -> void:
	if decoder.battery < 0.0:
		return
	var level := decoder.battery
	var state: int
	if level >= 1.0:
		state = HaptGloveHandler.BatteryState.FULL
	elif level >= 0.2:
		state = HaptGloveHandler.BatteryState.MEDIUM
	else:
		state = HaptGloveHandler.BatteryState.LOW
	if not _battery_known or state != battery_state:
		_battery_known = true
		battery_state = state
		battery_state_changed.emit(which_hand, state)


# -- commands -------------------------------------------------------------------------------

## Sends frames built by [member haptics] (or [Haptics] directly). Queued and batched
## where the platform needs it. Dropped while disconnected: a command for a grab that is over
## is better lost than delivered late.
func bt_send(data: PackedByteArray) -> bool:
	if not ble_connected:
		coalescer.clear()
		return false
	if coalescer.min_interval_ms > 0:
		coalescer.push(data)
		return true
	return _transport.write(device_id, data)


## Releases every channel.
func release_all_channels() -> void:
	release_channels(HexRTypes.ALL_FINGERS)


## Releases [param fingers] on both the pressure and the vibration path.
func release_channels(fingers: Array) -> void:
	if not ble_connected or fingers.is_empty():
		return
	bt_send(haptics.build_release(fingers))


## Starts the air pump, or stops it if started (as the Unity package's AirPressureSourceControl).
func air_pressure_source_control() -> void:
	if not ble_connected:
		return
	if not _pump_started:
		_start_pump()
	else:
		bt_send(Haptics.pump_control(false))
		_pump_started = false
		pump_changed.emit(which_hand, false)


func _start_pump() -> void:
	if _pump_started:
		return
	bt_send(Haptics.pump_control(true, source_pressure))
	_pump_started = true
	pump_changed.emit(which_hand, true)
	var pct := get_battery_level()
	_set_status("%s ready" % side() if pct <= 0.0 else "%s ready · %d%%" % [side(), roundi(pct * 100.0)])


## Releases immediately, skipping the batching queue. Used before disconnect, on pause and quit.
func _release_all_now(why: String) -> void:
	if not ble_connected:
		return
	coalescer.clear()
	_transport.write(device_id, haptics.build_release(), true)
	_log("released every channel (%s)" % why)


func _update_pause_frame() -> void:
	if _transport == null or not ble_connected:
		return
	if _release_bytes.is_empty():
		_release_bytes = Haptics.new().build_release()
	_transport.set_pause_release_frame(device_id, _release_bytes if release_when_paused else PackedByteArray())


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			if release_when_paused:
				_release_all_now("pause")
		NOTIFICATION_WM_CLOSE_REQUEST:
			shutdown("quit")


## Releases the glove and closes the link. HexR calls this on quit.
func shutdown(why: String = "shutdown") -> void:
	if ble_connected:
		_release_all_now(why)
		var id := device_id
		_link_down()
		_transport.disconnect_device(id)
	else:
		_abort_in_flight()
	_connect_requested = false
	_retry_at_ms = -1
	_watchdog_at_ms = -1


# -- readings -------------------------------------------------------------------------------

## Battery as a 0..1 fraction; 0 until the glove reports it.
func get_battery_level() -> float:
	return maxf(decoder.battery, 0.0)


## Raw pressure readings as whole numbers (Thumb..Palm, then the air source), as the Unity
## package returns them.
func get_air_pressure() -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in decoder.pressure_raw:
		out.append(int(v))
	return out


## Pressure readings in gauge kPa (Thumb..Palm, then the air source).
func get_air_pressure_kpa() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in decoder.pressure_raw:
		out.append(HexRFrameDecoder.raw_to_kpa(v))
	return out


## Finger position sensor readings, Thumb..Pinky.
func get_finger_position() -> PackedInt32Array:
	return decoder.finger_position


func _set_status(text: String) -> void:
	if text == status_text:
		return
	status_text = text
	status_changed.emit(which_hand, text)


func _log(message: String) -> void:
	if verbose:
		print("[HexR-BLE][%s] %s" % [side(), message])
