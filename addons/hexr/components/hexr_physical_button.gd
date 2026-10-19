class_name HexRPhysicalButton
extends Area3D
## A button pressed by a fingertip, with no interaction toolkit needed. The pressing finger
## feels it for as long as it stays in. Size the collision shape to the button's face.

signal pressed
signal released

## Which fingers can press it. Index only is the predictable choice: a palm or a curled ring
## finger brushing past should not fire it.
@export_flags("Thumb", "Index", "Middle", "Ring", "Pinky", "Palm") var fingers: int = 2
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

var _presser: HexRTouchPoint
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


func accepts(finger: int) -> bool:
	return (fingers & (1 << finger)) != 0


func _on_area_entered(area: Area3D) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _presser != null or now < _rearm_at or not (area is HexRTouchPoint):
		return
	var tp := area as HexRTouchPoint
	if not accepts(tp.finger):
		return
	_presser = tp
	var c := cap if cap else self
	if travel > 0.0:
		_cap_rest = c.position
		c.position = _cap_rest + press_direction.normalized() * travel
		_cap_moved = true
	pressed.emit()
	if press_pressure > 0.0:
		tp.trigger_fix_pressure(HexRPressureController.strength_to_intensity(press_pressure))


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
