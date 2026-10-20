class_name HexRGrabbable
extends Area3D
## Grab with a glove hand, no interaction toolkit needed (port of the Unity package's
## HexRGrabbable). Make it a child of the object to grab (usually a [RigidBody3D]) and give it a
## collision shape a little larger than the object.
##
## A pinch grab holds while the thumb and any other finger touch; a palm grab while the palm and
## any finger touch. Each touching finger is pressed at [member haptic_strength]. The object is
## let go when the hand opens (after a short grace), when only the anchor (thumb or palm) still
## touches, or when the anchor has lost contact.

signal grabbed(hand: int)
signal released(hand: int)

## Unity's grab types.
enum Options { PINCH_GRAB, PALM_GRAB }

@export var type_of_grab: Options = Options.PINCH_GRAB
## The object that moves. Empty uses the parent.
@export var the_object: Node3D
## Gravity on the object after it is let go (for a RigidBody3D).
@export var gravity_on_release := true
## How firmly each touching finger is pressed: 10 barely there, 60 firm, 0 no haptics.
@export_range(0.0, 60.0, 10.0) var haptic_strength := 10.0
## Seconds after grabbing before an open hand lets go.
@export var open_hand_grace := 0.5
## Seconds the anchor may lose contact before the object is let go.
@export var lost_contact_grace := 0.2

var _grab_hand := -1
var _anchor: HapticFingerTrigger
var _offset := Transform3D()
var _grabbed_at := 0.0
var _anchor_lost_at := -1.0
var _pressed: Array[bool] = [false, false, false, false, false, false]
var _velocity := Vector3.ZERO
var _last_position := Vector3.ZERO
var _clock := 0.0


func _init() -> void:
	collision_layer = 0
	collision_mask = 1 << 19
	monitorable = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if the_object == null:
		the_object = get_parent() as Node3D


# Scenes saved with HexR 0.1 use the old property names.
func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"grab_type":
			type_of_grab = value
		&"target":
			the_object = value
		_:
			return false
	HexRTypes.warn_renamed(self, property, {&"grab_type": "type_of_grab", &"target": "the_object"}[property])
	return true


func is_grabbed() -> bool:
	return _grab_hand >= 0


## The hand holding the object, or -1.
func grabbing_hand() -> int:
	return _grab_hand


func _anchor_finger() -> int:
	return Haptics.Finger.THUMB if type_of_grab == Options.PINCH_GRAB else Haptics.Finger.PALM


func _physics_process(delta: float) -> void:
	_clock += delta
	var touching := [[null, null, null, null, null, null], [null, null, null, null, null, null]]
	for area in get_overlapping_areas():
		if area is HapticFingerTrigger:
			touching[area.hand_type][area.finger_type] = area
	var anchor_finger := _anchor_finger()

	if _grab_hand < 0:
		# Right hand first, as in the Unity package.
		for hand in [HaptGloveHandler.HandType.RIGHT, HaptGloveHandler.HandType.LEFT]:
			if touching[hand][anchor_finger] != null and _another_finger(touching[hand]):
				_grab(hand, touching[hand][anchor_finger])
				break
	else:
		var row: Array = touching[_grab_hand]
		var anchor_touching: bool = row[anchor_finger] != null
		if anchor_touching:
			_anchor_lost_at = -1.0
		elif _anchor_lost_at < 0.0:
			_anchor_lost_at = _clock
		var use := _finger_use(_grab_hand)
		if anchor_touching and not _another_finger(row):
			_let_go()
		elif _anchor_lost_at >= 0.0 and _clock - _anchor_lost_at > lost_contact_grace:
			_let_go()
		elif use != null and _clock - _grabbed_at > open_hand_grace and use.is_hand_open():
			_let_go()
		else:
			_follow(delta)
			_update_finger_haptics(row)


func _another_finger(row: Array) -> bool:
	return row[Haptics.Finger.INDEX] != null or row[Haptics.Finger.MIDDLE] != null \
			or row[Haptics.Finger.RING] != null or row[Haptics.Finger.PINKY] != null


func _grab(hand: int, anchor: HapticFingerTrigger) -> void:
	if the_object == null:
		return
	_grab_hand = hand
	_anchor = anchor
	_offset = anchor.global_transform.affine_inverse() * the_object.global_transform
	_grabbed_at = _clock
	_anchor_lost_at = -1.0
	_last_position = the_object.global_position
	_velocity = Vector3.ZERO
	if the_object is RigidBody3D:
		var body := the_object as RigidBody3D
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
	var c := _controller(hand)
	if c:
		c.hand_grabbing_check(true)
	grabbed.emit(hand)


func _follow(delta: float) -> void:
	if not is_instance_valid(_anchor) or the_object == null:
		return
	the_object.global_transform = _anchor.global_transform * _offset
	if delta > 0.0:
		_velocity = _velocity.lerp((the_object.global_position - _last_position) / delta, 0.5)
	_last_position = the_object.global_position


func _update_finger_haptics(row: Array) -> void:
	if haptic_strength <= 0.0:
		return
	var g := _glove(_grab_hand)
	if g == null:
		return
	var intensity := PressureTrackerMain.strength_to_intensity(haptic_strength)
	var out := PackedByteArray()
	for f in 6:
		var touching: bool = row[f] != null
		if touching != _pressed[f]:
			_pressed[f] = touching
			out.append_array(g.haptics.hexr_pressure(f, touching, intensity, 1.0))
	if not out.is_empty():
		g.bt_send(out)


func _let_go() -> void:
	var hand := _grab_hand
	_grab_hand = -1
	_anchor = null
	if the_object is RigidBody3D:
		var body := the_object as RigidBody3D
		body.freeze = false
		body.gravity_scale = 1.0 if gravity_on_release else 0.0
		body.linear_velocity = _velocity
	var c := _controller(hand)
	if c:
		c.hand_grabbing_check(false)
	_release_haptics(hand)
	released.emit(hand)


func _release_haptics(hand: int) -> void:
	_pressed = [false, false, false, false, false, false]
	if haptic_strength <= 0.0:
		return
	var g := _glove(hand)
	if g:
		var out := PackedByteArray()
		for f in 6:
			out.append_array(g.haptics.hexr_pressure(f, false, 0.0, 1.0))
		g.bt_send(out)


func _exit_tree() -> void:
	if _grab_hand >= 0:
		_let_go()


func _finger_use(hand: int) -> FingerUseTracking:
	var hub := HexRManager.get_instance()
	return hub.finger_use(hand) if hub else null


func _glove(hand: int) -> HaptGloveHandler:
	var hub := HexRManager.get_instance()
	return hub.glove(hand) if hub else null


func _controller(hand: int) -> PressureTrackerMain:
	var hub := HexRManager.get_instance()
	return hub.controller(hand) if hub else null
