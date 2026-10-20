class_name HexRPhysicalButton
extends Area3D
## A button pressed by a fingertip, with no interaction toolkit needed. The pressing finger
## feels it for as long as it stays in. Size the collision shape to the button's face.

signal pressed
signal released

@export_group("Fingers that press it")
## Which fingers can press it. Index only is the predictable choice: a palm or a curled ring
## finger brushing past should not fire it.
@export var thumb := false
@export var index := true
@export var middle := false
@export var ring := false
@export var pinky := false
@export var palm := false
@export_group("")
## The part that visibly moves. Empty moves this node itself.
@export var cap: Node3D
## How far the cap sinks, in metres, along [member press_direction].
@export var travel := 0.006
## Local direction the cap moves when pressed.
@export var press_direction := Vector3.DOWN
## Pressure on the pressing finger while held: 10 barely there, 60 firm, 0 off.
@export_range(0.0, 60.0, 1.0) var press_pressure := 40.0
## Ignore a new press for this long after one ends, so a finger resting on the edge cannot
## chatter the button.
@export var rearm_seconds := 0.2

var _presser: HapticFingerTrigger
var _cap_rest := Vector3.ZERO
var _cap_moved := false
var _rearm_at := 0.0


func _init() -> void:
	collision_layer = 0
	collision_mask = 1 << 19
	monitorable = false


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func is_pressed() -> bool:
	return _presser != null


## Whether [param finger] (a [enum Haptics.Finger]) can press this button.
func accepts(finger: int) -> bool:
	return [thumb, index, middle, ring, pinky, palm][finger]


# Scenes saved with HexR 0.1 store the fingers as one bitmask.
func _set(property: StringName, value: Variant) -> bool:
	if property != &"fingers":
		return false
	var mask := int(value)
	thumb = mask & 1 != 0
	index = mask & 2 != 0
	middle = mask & 4 != 0
	ring = mask & 8 != 0
	pinky = mask & 16 != 0
	palm = mask & 32 != 0
	HexRTypes.warn_renamed(self, "fingers", "thumb/index/middle/ring/pinky/palm")
	return true


func _on_area_entered(area: Area3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _presser != null or now < _rearm_at or not (area is HapticFingerTrigger):
		return
	var tp := area as HapticFingerTrigger
	if not accepts(tp.finger_type):
		return
	_presser = tp
	var c := cap if cap else self
	if travel > 0.0:
		_cap_rest = c.position
		c.position = _cap_rest + press_direction.normalized() * travel
		_cap_moved = true
	pressed.emit()
	if press_pressure > 0.0:
		tp.trigger_fix_pressure(PressureTrackerMain.strength_to_intensity(press_pressure))


func _on_area_exited(area: Area3D) -> void:
	if area != _presser:
		return
	released.emit()
	_release()


func _exit_tree() -> void:
	_release()


func _release() -> void:
	if _presser != null:
		if is_instance_valid(_presser):
			_presser.remove_haptics()
		_presser = null
		_rearm_at = Time.get_ticks_msec() / 1000.0 + rearm_seconds
	if _cap_moved:
		(cap if cap else self).position = _cap_rest
		_cap_moved = false
