class_name HexRFrameDecoder
extends RefCounted
## Resynchronising parser for the glove's notifications (port of the HexR Companion's
## FrameDecoder).
##
## Inbound frames are [code][len][func][field...][xor][/code], where xor is the XOR of every byte
## before it. Notifications need not line up with frames, so this buffers, checks the length
## and checksum, and only then consumes. A frame that fails costs one byte, not the buffer.
##
## The glove sends three frames 50 times a second once notifications are on: finger positions
## (0x04), pressures (0x01) and battery (0x06).

const MAX_BUFFER := 74 * 16
const ABSOLUTE_PA_THRESHOLD := 10000.0

## Raw pressure readings: Thumb, Index, Middle, Ring, Pinky, Palm, then the air source.
## Firmware reports gauge kPa; some gloves report absolute pascals. See [method raw_to_kpa].
var pressure_raw: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
## Finger position sensor readings, Thumb..Pinky.
var finger_position: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
## Battery as a 0..1 fraction, or -1 until the glove reports it.
var battery: float = -1.0
## True once any valid frame has arrived.
var seen: bool = false
## Frames that failed their checksum or were shorter than their function implies.
var bad_frames: int = 0
## How many valid frames of each kind have arrived.
var pressure_frames: int = 0
var position_frames: int = 0
var battery_frames: int = 0

var _buf := PackedByteArray()


func reset() -> void:
	_buf.clear()
	pressure_raw = PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	finger_position = PackedInt32Array([0, 0, 0, 0, 0])
	battery = -1.0
	seen = false
	bad_frames = 0
	pressure_frames = 0
	position_frames = 0
	battery_frames = 0


## Feeds one notification. Returns how many frames it completed.
func feed(data: PackedByteArray) -> int:
	_buf.append_array(data)
	if _buf.size() > MAX_BUFFER:
		_buf = _buf.slice(_buf.size() - MAX_BUFFER)
	var frames := 0
	while _buf.size() >= 3:
		var length := _buf[0]
		var op := _buf[1]
		if length < 3 or not _is_inbound_op(op):
			_buf.remove_at(0)
			continue
		if _buf.size() < length:
			break
		var checksum := 0
		for i in length - 1:
			checksum ^= _buf[i]
		if checksum != _buf[length - 1]:
			bad_frames += 1
			_buf.remove_at(0)
			continue
		var frame := _buf.slice(0, length)
		_buf = _buf.slice(length)
		if _apply(frame):
			frames += 1
	return frames


static func _is_inbound_op(op: int) -> bool:
	return op == HexRTypes.InOp.PRESSURE or op == HexRTypes.InOp.MICROTUBE \
			or op == HexRTypes.InOp.CLUTCH_ACTIVATED or op == HexRTypes.InOp.BATTERY


func _apply(frame: PackedByteArray) -> bool:
	var op := frame[1]
	if op == HexRTypes.InOp.PRESSURE:
		if frame.size() < 3 + 6 * 5 + 4:
			bad_frames += 1
			return false
		for i in 7:
			pressure_raw[i] = frame.decode_float(3 + i * 5)
		pressure_frames += 1
	elif op == HexRTypes.InOp.MICROTUBE or op == HexRTypes.InOp.CLUTCH_ACTIVATED:
		if frame.size() < 3 + 4 * 5 + 4:
			bad_frames += 1
			return false
		for i in 5:
			finger_position[i] = frame.decode_s32(3 + i * 5)
		position_frames += 1
	elif op == HexRTypes.InOp.BATTERY:
		if frame.size() < 7:
			bad_frames += 1
			return false
		battery = frame.decode_float(3)
		battery_frames += 1
	seen = true
	return true


## Gauge kPa from a raw pressure reading, whichever unit the glove reports. A glove at rest
## reads near 0 in gauge kPa and near 100000 in absolute pascals.
static func raw_to_kpa(raw: float) -> float:
	if raw > ABSOLUTE_PA_THRESHOLD:
		return (raw - 100000.0) / 1000.0
	return raw


## True if any reading looks like absolute pascals.
static func looks_like_absolute_pa(raw_values: PackedFloat32Array) -> bool:
	for v in raw_values:
		if v > ABSOLUTE_PA_THRESHOLD:
			return true
	return false


## Builds an inbound frame with its XOR checksum. For the simulated glove and tests.
static func build_inbound(op: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([(payload.size() + 3) & 0xFF, op])
	out.append_array(payload)
	var checksum := 0
	for b in out:
		checksum ^= b
	out.append(checksum)
	return out
