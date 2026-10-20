class_name ProximityCheck
extends Area3D
## Marks a hand as "near" while any of its touch points is inside this area, which opens the
## hand-near check on that hand's [PressureTrackerMain]. Use it around objects whose haptics
## come from code or from an interaction toolkit that does not report grabs itself.
## Size the collision shape to the space a hand has to be in.

## How long a hand still counts as near after its last contact.
@export var clear_delay := 0.5

var _last_contact: PackedFloat64Array = PackedFloat64Array([-INF, -INF])
var _near: Array[bool] = [false, false]


func _init() -> void:
	collision_layer = 0
	collision_mask = 1 << 19
	monitorable = false


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var touching: Array[bool] = [false, false]
	for area in get_overlapping_areas():
		if area is HapticFingerTrigger:
			touching[area.hand_type] = true
			_last_contact[area.hand_type] = now
	for hand in 2:
		if touching[hand]:
			_set_near(hand, true)
		elif _near[hand] and now - _last_contact[hand] > clear_delay:
			_set_near(hand, false)


func _exit_tree() -> void:
	_set_near(HaptGloveHandler.HandType.LEFT, false)
	_set_near(HaptGloveHandler.HandType.RIGHT, false)


## True while [param hand] counts as near this zone.
func is_near(hand: int) -> bool:
	return _near[hand]


func _set_near(hand: int, near: bool) -> void:
	if _near[hand] == near:
		return
	_near[hand] = near
	var hub := HexRManager.get_instance()
	var c := hub.controller(hand) if hub else null
	if c:
		c.set_near_source(self, near)
