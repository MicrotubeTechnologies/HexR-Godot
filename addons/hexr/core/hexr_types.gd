class_name HexRTypes
## Shared enums and constants for the HexR glove. Values match the glove's wire protocol,
## so a [enum Finger] can be sent as a channel byte as-is.

enum Hand { LEFT, RIGHT }

## Haptic channels in wire order (channel byte 0..5).
enum Finger { THUMB, INDEX, MIDDLE, RING, PINKY, PALM }

enum HapticMode { OFF, PRESSURE, VIBRATION, PULSE }

enum BatteryState { FULL, MEDIUM, LOW }

## Outbound function indices (app to glove).
enum Op {
	AIR_PRESSURE = 0x01,
	STABLE_PRESSURE_CTRL = 0x02,
	SET_PRESSURE_DEPRECATED = 0x03,
	SET_PRESSURE = 0x04,
	SET_PID = 0x05,
	SET_BATTERY_LED = 0x06,
	SET_VIBRATION = 0x07,
	SET_PULSE = 0x08,
	SET_VIB_SPEED = 0x09,
	SET_PULSE_SPEED = 0x0A,
}

## Inbound function indices (glove to app, notifications).
enum InOp { PRESSURE = 0x01, MICROTUBE = 0x04, CLUTCH_ACTIVATED = 0x05, BATTERY = 0x06 }

const SERVICE_UUID := "000000ff-0000-1000-8000-00805f9b34fb"
const CHARACTERISTIC_UUID := "0000ff01-0000-1000-8000-00805f9b34fb"

const NAME_PREFIX := "HaptGloveAR"
const NAME_LEFT := "HaptGloveAR Left"
const NAME_RIGHT := "HaptGloveAR Right"

## Channel state byte: 0 applies, 2 releases. 1 ("stay") does nothing on the glove.
const STATE_ENTER := 0
const STATE_EXIT := 2

const ALL_FINGERS: Array[int] = [0, 1, 2, 3, 4, 5]

const FINGER_NAMES: Array[String] = ["Thumb", "Index", "Middle", "Ring", "Pinky", "Palm"]


static func hand_name(hand: int) -> String:
	return "Left" if hand == Hand.LEFT else "Right"


static func finger_name(finger: int) -> String:
	return FINGER_NAMES[finger] if finger >= 0 and finger < FINGER_NAMES.size() else "?"


static func default_device_name(hand: int) -> String:
	return NAME_LEFT if hand == Hand.LEFT else NAME_RIGHT


## Which hand an advertised name belongs to, or -1. The hand is carried only by the name;
## the command bytes are identical for both gloves.
static func hand_from_device_name(device_name: String) -> int:
	var n := device_name.strip_edges()
	if not n.begins_with(NAME_PREFIX):
		return -1
	var tail := n.substr(NAME_PREFIX.length()).strip_edges().to_lower()
	if tail.begins_with("left"):
		return Hand.LEFT
	if tail.begins_with("right"):
		return Hand.RIGHT
	return -1
