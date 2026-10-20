class_name Haptics
extends RefCounted
## Builds the glove's haptic command frames (port of the Unity package's HaptGlove.Haptics).
##
## Each glove owns one of these. The builders return bytes to send with [method HaptGloveHandler.bt_send];
## they also record the last command per channel, which the floating menu's readout and
## HexR Remote's haptics feed read back. That record is commanded intent: the glove does
## not acknowledge commands.
##
## Intensity is 0.1..1 and maps linearly to 15..50 kPa. Speed is 0.1..1, the ramp rate.
## Out-of-range values are clamped, not rejected.

## Haptic channels in wire order (the channel byte, 0..5).
enum Finger { THUMB, INDEX, MIDDLE, RING, PINKY, PALM }

## What a channel was last told to do.
enum HapticMode { OFF, PRESSURE, VIBRATION, PULSE }

## Outbound function indices (app to glove), as the Unity package names them.
enum FunIndex {
	FI_AIR_PRESSURE = 0x01,
	FI_STABLE_PRESSURE_CTRL = 0x02,
	FI_SET_PRESSURE_DEPRECATED = 0x03,
	FI_SET_PRESSURE = 0x04,
	FI_SET_PID = 0x05,
	FI_SET_BATTERY_LED = 0x06,
	FI_SET_VIBRATION = 0x07,
	FI_SET_PULSE = 0x08,
	FI_SET_VIB_SPEED = 0x09,
	FI_SET_PULSE_SPEED = 0x0A,
}


## The last command sent to one channel.
class ChannelState:
	var mode: int = Haptics.HapticMode.OFF
	var intensity: float = 0.0
	var frequency: float = 0.0

	func _init(p_mode: int = Haptics.HapticMode.OFF, p_intensity: float = 0.0, p_frequency: float = 0.0) -> void:
		mode = p_mode
		intensity = p_intensity
		frequency = p_frequency

	func is_on() -> bool:
		return mode != Haptics.HapticMode.OFF

	func equals(other: ChannelState) -> bool:
		return other != null and mode == other.mode and is_equal_approx(intensity, other.intensity) \
				and is_equal_approx(frequency, other.frequency)


var _current: Array[ChannelState] = []
var _last_active: Array[ChannelState] = []
var _activations: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])


func _init() -> void:
	for i in 6:
		_current.append(ChannelState.new())
		_last_active.append(ChannelState.new())


## The last command sent to [param finger].
func get_channel_state(finger: int) -> ChannelState:
	return _current[finger]


## The last command that turned [param finger] on, kept after it goes off again. A tap can be
## switched on and off within one frame, and polling [method get_channel_state] would miss it.
func get_last_active_state(finger: int) -> ChannelState:
	return _last_active[finger]


## How many commands have turned [param finger] on. Changes on every trigger, including a
## repeat of the same value.
func get_activation_count(finger: int) -> int:
	return _activations[finger]


func _record(finger: int, state: ChannelState) -> void:
	_current[finger] = state
	if state.is_on():
		_last_active[finger] = state
		_activations[finger] += 1


static func _state_byte(on: bool) -> int:
	return HexRTypes.STATE_ENTER if on else HexRTypes.STATE_EXIT


static func _speed_byte(speed: float) -> int:
	speed = HexRF32.clamp32(0.1, 1.0, speed)
	speed = HexRF32.lin_map(0.1, 1.0, speed, 0.1, 1.0)
	return HexRF32.to_byte(HexRF32.r(speed * 100.0))


static func _end_kpa(end_intensity: float) -> float:
	end_intensity = HexRF32.r(end_intensity)
	if end_intensity < HexRF32.r(0.1):
		return 0.0
	return HexRF32.lin_map(0.1, 1.0, HexRF32.clamp32(0.1, 1.0, end_intensity), 15.0, 50.0)


## Unity GetVibIntensity: the pressure and peak ratio a vibration of [param frequency] uses
## for a 0.1..1 intensity. At 5 Hz and above the pump runs flat out and intensity sets the
## peak ratio; below that intensity sets the pressure.
static func vibration_pressure_and_peak(frequency: float, intensity: float) -> Array:
	var kpa := 0.0
	var peak := 0
	intensity = HexRF32.clamp32(0.1, 1.0, intensity)
	frequency = HexRF32.r(frequency)
	if frequency >= 10.0:
		kpa = 50.0
		peak = HexRF32.to_byte(HexRF32.lin_map(0.1, 1.0, intensity, 20.0, 50.0))
	elif frequency >= 5.0:
		kpa = 50.0
		var bound1 := HexRF32.to_byte(HexRF32.lin_map(5.0, 10.0, frequency, 20.0, 20.0))
		peak = HexRF32.to_byte(HexRF32.lin_map(0.1, 1.0, intensity, bound1, 50.0))
	elif frequency >= HexRF32.r(0.1):
		peak = 50
		kpa = HexRF32.lin_map(0.1, 1.0, intensity, 15.0, 50.0)
	return [kpa, peak]


## Steady pressure on one channel (function 0x04).
## [param on]: true to press, false to release. [param intensity]: 0.1..1. [param speed]: 0.1..1.
func hexr_pressure(finger: int, on: bool, intensity: float, speed: float = 1.0) -> PackedByteArray:
	intensity = HexRF32.clamp32(0.1, 1.0, intensity)
	var kpa := HexRF32.lin_map(0.1, 1.0, intensity, 15.0, 50.0)
	var payload := HexRTlv.f32(0.0)
	payload.append_array(HexRTlv.u8(finger))
	payload.append_array(HexRTlv.u8(_state_byte(on)))
	payload.append_array(HexRTlv.f32(kpa))
	payload.append_array(HexRTlv.u8(_speed_byte(speed)))
	_record(finger, ChannelState.new(HapticMode.PRESSURE, intensity, 0.0) if on else ChannelState.new())
	return HexRTlv.frame(FunIndex.FI_SET_PRESSURE, payload)


## [method hexr_pressure] for several channels, concatenated into one write.
func hexr_pressure_multi(fingers: Array, states: Array, intensities: Array, speeds: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for i in fingers.size():
		out.append_array(hexr_pressure(fingers[i], states[i], intensities[i], speeds[i]))
	return out


## Vibration on one channel (function 0x07). [param frequency]: 0.1..40 Hz.
## [param intensity]: 0.1..1; at 5 Hz and above it sets the peak ratio, below that the pressure.
func hexr_vibration(finger: int, on: bool, frequency: float, intensity: float) -> PackedByteArray:
	frequency = HexRF32.clamp32(0.1, 40.0, frequency)
	var pk := vibration_pressure_and_peak(frequency, intensity)
	var payload := HexRTlv.f32(frequency)
	payload.append_array(HexRTlv.u8(finger))
	payload.append_array(HexRTlv.u8(_state_byte(on)))
	payload.append_array(HexRTlv.f32(pk[0]))
	payload.append_array(HexRTlv.u8(pk[1]))
	_record(finger, ChannelState.new(HapticMode.VIBRATION, HexRF32.r(intensity), frequency) if on else ChannelState.new())
	return HexRTlv.frame(FunIndex.FI_SET_VIBRATION, payload)


## [method hexr_vibration] for several channels, concatenated into one write.
func hexr_vibration_multi(fingers: Array, states: Array, frequencies: Array, intensities: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for i in fingers.size():
		out.append_array(hexr_vibration(fingers[i], states[i], frequencies[i], intensities[i]))
	return out


## Low-frequency vibration with a shaped pulse (function 0x09). [param frequency]: 0.1..2 Hz.
## [param peak_ratio]: 0.2..0.8, the share of each cycle spent at peak. [param end_intensity]:
## the pressure to hold after the vibration; below 0.1 holds none.
func hexr_vibration_ramped(finger: int, on: bool, frequency: float, intensity: float,
		peak_ratio: float, speed: float, end_intensity: float) -> PackedByteArray:
	frequency = HexRF32.clamp32(0.1, 2.0, frequency)
	intensity = HexRF32.clamp32(0.1, 1.0, intensity)
	var kpa := HexRF32.lin_map(0.1, 1.0, intensity, 15.0, 50.0)
	var peak := HexRF32.to_byte(HexRF32.r(HexRF32.clamp32(0.2, 0.8, peak_ratio) * 100.0))
	var payload := HexRTlv.f32(frequency)
	payload.append_array(HexRTlv.u8(finger))
	payload.append_array(HexRTlv.u8(_state_byte(on)))
	payload.append_array(HexRTlv.f32(kpa))
	payload.append_array(HexRTlv.u8(peak))
	payload.append_array(HexRTlv.u8(_speed_byte(speed)))
	payload.append_array(HexRTlv.f32(_end_kpa(end_intensity)))
	_record(finger, ChannelState.new(HapticMode.VIBRATION, intensity, frequency) if on else ChannelState.new())
	return HexRTlv.frame(FunIndex.FI_SET_VIB_SPEED, payload)


## A counted burst of pulses (function 0x08). [param frequency]: 0.1..40 Hz.
## [param pulse_count]: 1..1000.
func hexr_pulse(finger: int, on: bool, frequency: float, intensity: float, pulse_count: int) -> PackedByteArray:
	frequency = HexRF32.clamp32(0.1, 40.0, frequency)
	var pk := vibration_pressure_and_peak(frequency, intensity)
	var payload := HexRTlv.f32(frequency)
	payload.append_array(HexRTlv.u8(finger))
	payload.append_array(HexRTlv.u8(_state_byte(on)))
	payload.append_array(HexRTlv.f32(pk[0]))
	payload.append_array(HexRTlv.u8(pk[1]))
	payload.append_array(HexRTlv.u16(clampi(pulse_count, 1, 1000)))
	_record(finger, ChannelState.new(HapticMode.PULSE, HexRF32.r(intensity), frequency) if on else ChannelState.new())
	return HexRTlv.frame(FunIndex.FI_SET_PULSE, payload)


## A counted burst of shaped low-frequency pulses (function 0x0A). [param frequency]: 0.1..2 Hz.
func hexr_pulse_ramped(finger: int, on: bool, frequency: float, intensity: float, peak_ratio: float,
		speed: float, pulse_count: int, end_intensity: float) -> PackedByteArray:
	frequency = HexRF32.clamp32(0.1, 2.0, frequency)
	intensity = HexRF32.clamp32(0.1, 1.0, intensity)
	var kpa := HexRF32.lin_map(0.1, 1.0, intensity, 15.0, 50.0)
	var peak := HexRF32.to_byte(HexRF32.r(HexRF32.clamp32(0.2, 0.8, peak_ratio) * 100.0))
	var payload := HexRTlv.f32(frequency)
	payload.append_array(HexRTlv.u8(finger))
	payload.append_array(HexRTlv.u8(_state_byte(on)))
	payload.append_array(HexRTlv.f32(kpa))
	payload.append_array(HexRTlv.u8(peak))
	payload.append_array(HexRTlv.u16(clampi(pulse_count, 1, 1000)))
	payload.append_array(HexRTlv.u8(_speed_byte(speed)))
	payload.append_array(HexRTlv.f32(_end_kpa(end_intensity)))
	_record(finger, ChannelState.new(HapticMode.PULSE, intensity, frequency) if on else ChannelState.new())
	return HexRTlv.frame(FunIndex.FI_SET_PULSE_SPEED, payload)


## Releases [param fingers] on both paths: a vibration exit, then a pressure exit, per channel.
## A pressure exit alone does not stop a vibration of 5 Hz or more. Byte-identical to the
## Unity package's release (216 bytes for all six channels).
func build_release(fingers: Array = HexRTypes.ALL_FINGERS) -> PackedByteArray:
	var out := PackedByteArray()
	for f in fingers:
		out.append_array(hexr_vibration(f, false, 1.0, 0.1))
		out.append_array(hexr_pressure(f, false, 0.0, 1.0))
	return out


## Air-source pump control (function 0x02). Current firmware ignores it; it is sent for
## parity with the Unity package.
static func pump_control(start: bool, source_kpa: int = 80) -> PackedByteArray:
	var payload := HexRTlv.u8(1 if start else 0)
	payload.append_array(HexRTlv.u8(source_kpa if start else 0))
	return HexRTlv.frame(FunIndex.FI_STABLE_PRESSURE_CTRL, payload)


## PID gains for every channel's pressure loop (function 0x05). Changing them changes how
## every haptic feels; leave them alone unless Microtube asks.
static func set_pid(kp: float, ki: float, kd: float) -> PackedByteArray:
	var payload := HexRTlv.f32(kp)
	payload.append_array(HexRTlv.f32(ki))
	payload.append_array(HexRTlv.f32(kd))
	return HexRTlv.frame(FunIndex.FI_SET_PID, payload)
