class_name HexRSimulatedGlove
extends RefCounted
## A software glove that behaves like the firmware, for tests and for working without hardware.
##
## It enforces what the real glove enforces: writes longer than MTU - 3 are ignored, frames are
## walked by their length byte and the walk stops at an impossible length, and notifications are
## a 74-byte bundle 50 times a second once subscribed. It also counts subscriptions, because
## subscribing twice leaks a timer on the real glove.

var id: String
var device_name: String
## Whether it advertises (is "switched on").
var advertising := true
var mtu := 247
var battery := 0.8
## Advertised RSSI.
var rssi := -55

## Fault injection.
var fail_next_connects := 0
var drop_at_ms := -1
var connect_delay_ms := 150

var connected := false
var subscriptions_this_connection := 0
var total_subscriptions := 0
var connections := 0
## Every frame the glove accepted, in order.
var received_frames: Array[PackedByteArray] = []
## Writes ignored for being longer than MTU - 3.
var dropped_long_writes := 0

## Target kPa per channel (0 = off), and the pressure the "pump" has reached.
var target_kpa := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var pressure_kpa := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var vibrating := [false, false, false, false, false, false]
var finger_position := PackedInt32Array([1200, 1300, 1400, 1500, 1600])
## Source (tank) pressure.
var source_kpa := 80.0

var _last_tick_ms := -1
var _notify_accum_ms := 0


func _init(p_id: String = "", p_name: String = "") -> void:
	id = p_id
	device_name = p_name


func on_connected() -> void:
	connected = true
	connections += 1
	subscriptions_this_connection = 0


func on_subscribed() -> void:
	subscriptions_this_connection += 1
	total_subscriptions += 1


func on_disconnected() -> void:
	connected = false


## A write arriving over the air. Returns false if the glove ignored it.
func receive_write(data: PackedByteArray) -> bool:
	if data.size() > mtu - 3:
		dropped_long_writes += 1
		return false
	for frame in HexRFrames.split_frames(data):
		received_frames.append(frame)
		_apply(frame)
	return true


func _apply(frame: PackedByteArray) -> void:
	if frame.size() < 2:
		return
	var op := frame[1]
	if op == HexRTypes.Op.SET_PRESSURE and frame.size() >= 18:
		var ch := frame[8]
		var state := frame[10]
		var kpa := frame.decode_float(12)
		if ch < 6:
			target_kpa[ch] = kpa if state == HexRTypes.STATE_ENTER and kpa >= 15.0 else 0.0
	elif (op == HexRTypes.Op.SET_VIBRATION or op == HexRTypes.Op.SET_PULSE
			or op == HexRTypes.Op.SET_VIB_SPEED or op == HexRTypes.Op.SET_PULSE_SPEED) and frame.size() >= 18:
		var ch := frame[8]
		if ch < 6:
			vibrating[ch] = frame[10] == HexRTypes.STATE_ENTER


## Frames received with function [param op].
func frames_with_op(op: int) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for f in received_frames:
		if f[1] == op:
			out.append(f)
	return out


func any_channel_on() -> bool:
	for i in 6:
		if target_kpa[i] > 0.0 or vibrating[i]:
			return true
	return false


## Advances the model. Returns the notifications sent in this step.
func tick(now_ms: int) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if _last_tick_ms < 0:
		_last_tick_ms = now_ms
	var dt := now_ms - _last_tick_ms
	_last_tick_ms = now_ms
	# Ramp toward the target: about 60 ms per 10 kPa at full speed.
	for i in 6:
		var step := dt / 6.0
		pressure_kpa[i] = move_toward(pressure_kpa[i], target_kpa[i], step)
	if connected and subscriptions_this_connection > 0:
		_notify_accum_ms += dt
		while _notify_accum_ms >= 20:
			_notify_accum_ms -= 20
			var bundle := build_bundle()
			out.append(bundle.slice(0, mini(bundle.size(), mtu - 3)))
	return out


## The firmware's 74-byte notification: positions, pressures, battery.
func build_bundle() -> PackedByteArray:
	var p := PackedByteArray()
	for v in finger_position:
		p.append_array(HexRTlv.i32(v))
	var out := HexRFrameDecoder.build_inbound(HexRTypes.InOp.MICROTUBE, p)
	p = PackedByteArray()
	for i in 6:
		p.append_array(HexRTlv.f32(pressure_kpa[i]))
	p.append_array(HexRTlv.f32(source_kpa))
	out.append_array(HexRFrameDecoder.build_inbound(HexRTypes.InOp.PRESSURE, p))
	out.append_array(HexRFrameDecoder.build_inbound(HexRTypes.InOp.BATTERY, HexRTlv.f32(battery)))
	return out
