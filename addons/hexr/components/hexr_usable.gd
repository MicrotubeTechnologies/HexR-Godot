class_name HexRUsable
extends Area3D
## Fires when a hand touching this area curls the chosen fingers, and again when it lets them
## out (port of the Unity package's HexRUsable): squeeze a spray can, pull a trigger.
##
## The Unity component only looked at the last finger it checked; this one needs every chosen
## finger past the threshold.

signal used(hand: int)
signal stopped_using(hand: int)

@export_group("Fingers that have to curl")
## The fingers that have to curl, all five by default as in the Unity package.
@export var thumb := true
@export var index_finger := true
@export var middle_finger := true
@export var ring_finger := true
@export var little_finger := true
@export_group("")
## 0 is fully curled, 1 fully extended. A finger counts as curled below this.
@export_range(0.0, 1.0, 0.05) var use_threshold := 0.3

var _hand := -1
var _in_use := false


func _init() -> void:
	collision_layer = 0
	collision_mask = 1 << 19
	monitorable = false


# Scenes saved with HexR 0.1 store the fingers as one bitmask.
func _set(property: StringName, value: Variant) -> bool:
	if property != &"fingers":
		return false
	var mask := int(value)
	thumb = mask & 1 != 0
	index_finger = mask & 2 != 0
	middle_finger = mask & 4 != 0
	ring_finger = mask & 8 != 0
	little_finger = mask & 16 != 0
	HexRTypes.warn_renamed(self, "fingers", "thumb/index_finger/middle_finger/ring_finger/little_finger")
	return true


func is_in_use() -> bool:
	return _in_use


func _physics_process(_delta: float) -> void:
	if not _in_use:
		for area in get_overlapping_areas():
			if area is HapticFingerTrigger:
				_hand = area.hand_type
				break
	if _hand < 0:
		return
	var hub := HexRManager.get_instance()
	var use := hub.finger_use(_hand) if hub else null
	if use == null:
		return
	if not _in_use and _all_needed(use, func(v: float) -> bool: return v < use_threshold):
		_in_use = true
		used.emit(_hand)
	elif _in_use and _all_needed(use, func(v: float) -> bool: return v > use_threshold):
		_in_use = false
		stopped_using.emit(_hand)
		_hand = -1


func _all_needed(use: FingerUseTracking, test: Callable) -> bool:
	var any := false
	var needed := [thumb, index_finger, middle_finger, ring_finger, little_finger]
	for f in 5:
		if needed[f]:
			any = true
			if not test.call(use.get_use(f)):
				return false
	return any
