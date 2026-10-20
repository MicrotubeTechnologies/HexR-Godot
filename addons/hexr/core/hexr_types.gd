class_name HexRTypes
## Wire-protocol constants and small helpers shared by the addon. The enums a game uses live
## where the Unity package has them: [enum HaptGloveHandler.HandType],
## [enum HaptGloveHandler.BatteryState], [enum Haptics.Finger], [enum Haptics.HapticMode] and
## [enum Haptics.FunIndex].

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
	return "Left" if hand == HaptGloveHandler.HandType.LEFT else "Right"


static func finger_name(finger: int) -> String:
	return FINGER_NAMES[finger] if finger >= 0 and finger < FINGER_NAMES.size() else "?"


static func default_device_name(hand: int) -> String:
	return NAME_LEFT if hand == HaptGloveHandler.HandType.LEFT else NAME_RIGHT


## Which hand an advertised name belongs to, or -1. The hand is carried only by the name;
## the command bytes are identical for both gloves.
static func hand_from_device_name(device_name: String) -> int:
	var n := device_name.strip_edges()
	if not n.begins_with(NAME_PREFIX):
		return -1
	var tail := n.substr(NAME_PREFIX.length()).strip_edges().to_lower()
	if tail.begins_with("left"):
		return HaptGloveHandler.HandType.LEFT
	if tail.begins_with("right"):
		return HaptGloveHandler.HandType.RIGHT
	return -1


static var _renamed_warned := {}


## Warns once that a scene still uses a 0.1 property name. The components' _set() shims call it
## while they map the old name onto the new one; HexR > Migration > Upgrade 0.1 scenes rewrites
## the scene files for good.
static func warn_renamed(owner: Object, old_name: String, new_name: String) -> void:
	var cls: String = owner.get_script().get_global_name() if owner.get_script() else owner.get_class()
	var key := "%s.%s" % [cls, old_name]
	if _renamed_warned.has(key):
		return
	_renamed_warned[key] = true
	push_warning("[HexR] %s.%s is now %s (HexR 0.2). Run HexR > Migration > Upgrade 0.1 scenes to update your scenes."
			% [cls, old_name, new_name])

