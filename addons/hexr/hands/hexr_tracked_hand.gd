class_name HexRTrackedHand
extends Node3D
## One tracked hand: reads the OpenXR hand tracker and moves six [HexRTouchPoint]s (five
## fingertips and the palm) with its joints, and tracks how curled each finger is.
##
## It reads [XRHandTracker] directly (the standard OpenXR joints), so it works on Meta Quest,
## PICO and any OpenXR runtime, with or without a hand mesh. Put it anywhere under the
## [XROrigin3D]; [HexRRig] creates two.

signal tracking_changed(tracking: bool)

const TIP_JOINTS: Array[int] = [
	XRHandTracker.HAND_JOINT_THUMB_TIP,
	XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
	XRHandTracker.HAND_JOINT_RING_FINGER_TIP,
	XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP,
]
## Where each finger's curl is measured from (the thumb from its metacarpal).
const KNUCKLE_JOINTS: Array[int] = [
	XRHandTracker.HAND_JOINT_THUMB_METACARPAL,
	XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL,
	XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL,
	XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL,
	XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL,
]
## Fingertip sphere centres in joint space (OpenXR: -Z toward the tip, -Y toward the palm): a few
## millimetres toward the pad and back from the tip. The Unity package's values for the same
## OpenXR joints, tuned on PICO, with Z flipped from Unity's left-handed axes.
const DEFAULT_TIP_OFFSETS_LEFT: Array[Vector3] = [
	Vector3(0.0010, -0.0009, 0.0079), Vector3(-0.0001, -0.0051, 0.0070), Vector3(-0.0005, -0.0059, 0.0077),
	Vector3(-0.0002, -0.0034, 0.0032), Vector3(-0.0009, -0.0051, 0.0071),
]
const DEFAULT_TIP_OFFSETS_RIGHT: Array[Vector3] = [
	Vector3(-0.0006, -0.0056, 0.0081), Vector3(0.0008, -0.0059, 0.0089), Vector3(0.0005, -0.0079, 0.0089),
	Vector3(0.0013, -0.0054, 0.0055), Vector3(0.0012, -0.0060, 0.0070),
]

@export var hand: HexRTypes.Hand = HexRTypes.Hand.LEFT
## Leave empty for the standard OpenXR tracker (/user/hand_tracker/left or /right).
@export var tracker_name: StringName = &""
@export var tip_radius := 0.008
## Per finger, Thumb..Pinky. Empty uses the defaults for this hand.
@export var tip_offsets: Array[Vector3] = []
@export var palm_size := Vector3(0.062, 0.0203, 0.0605)
@export var palm_offset := Vector3(0.001, -0.0193, 0.0038)
## Physics layer of the touch points. Zones and components must include it in their mask.
@export_flags_3d_physics var touch_layer: int = 1 << 19
## Draw the touch points (for checking placement).
@export var show_touch_points := false:
	set(v):
		show_touch_points = v
		_update_debug_meshes()

## The six touch points, indexed by [enum HexRTypes.Finger].
var touch_points: Array[HexRTouchPoint] = []
var finger_use := HexRFingerUseTracking.new()
## True while the tracker reports this hand.
var tracking := false

var _joint_globals: Dictionary = {}


func _ready() -> void:
	_build_touch_points()
	var hub := HexRManager.get_instance()
	if hub:
		hub._register_hand(self)


func _exit_tree() -> void:
	var hub := HexRManager.get_instance()
	if hub:
		hub._unregister_hand(self)


func get_tracker_name() -> StringName:
	if tracker_name != &"":
		return tracker_name
	return &"/user/hand_tracker/left" if hand == HexRTypes.Hand.LEFT else &"/user/hand_tracker/right"


func get_tracker() -> XRHandTracker:
	return XRServer.get_tracker(get_tracker_name()) as XRHandTracker


func touch_point(finger: int) -> HexRTouchPoint:
	return touch_points[finger] if finger >= 0 and finger < touch_points.size() else null


## A joint's global transform this frame, or null-equivalent identity when it is not tracked.
## [param joint] is an [enum XRHandTracker.HandJoint].
func get_joint_global_transform(joint: int) -> Transform3D:
	return _joint_globals.get(joint, Transform3D())


func is_joint_valid(joint: int) -> bool:
	return _joint_globals.has(joint)


func _build_touch_points() -> void:
	if not touch_points.is_empty():
		return
	var offsets := tip_offsets if tip_offsets.size() == 5 else (DEFAULT_TIP_OFFSETS_LEFT if hand == HexRTypes.Hand.LEFT else DEFAULT_TIP_OFFSETS_RIGHT)
	for f in 6:
		var tp := HexRTouchPoint.new()
		tp.hand = hand
		tp.finger = f
		tp.name = "%s%s" % [HexRTypes.hand_name(hand), HexRTypes.finger_name(f)]
		tp.collision_layer = touch_layer
		tp.collision_mask = 0
		tp.monitoring = false
		tp.monitorable = false
		var shape := CollisionShape3D.new()
		if f == HexRTypes.Finger.PALM:
			var box := BoxShape3D.new()
			box.size = palm_size
			shape.shape = box
			shape.position = palm_offset
		else:
			var sphere := SphereShape3D.new()
			sphere.radius = tip_radius
			shape.shape = sphere
			shape.position = offsets[f]
		tp.add_child(shape)
		tp.top_level = true
		add_child(tp)
		touch_points.append(tp)
	_update_debug_meshes()


func _physics_process(_delta: float) -> void:
	update_from_tracker()


## Moves the touch points to the tracker's current joints. Called every physics frame.
func update_from_tracker() -> void:
	var tracker := get_tracker()
	var has_data := tracker != null and tracker.has_tracking_data
	_joint_globals.clear()
	if has_data:
		var origin := _origin_transform()
		var scale := XRServer.world_scale
		for joint in TIP_JOINTS + KNUCKLE_JOINTS + [XRHandTracker.HAND_JOINT_PALM, XRHandTracker.HAND_JOINT_WRIST]:
			if tracker.get_hand_joint_flags(joint) & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID:
				var t := tracker.get_hand_joint_transform(joint)
				t.origin *= scale
				_joint_globals[joint] = origin * t
	for f in 6:
		var joint: int = TIP_JOINTS[f] if f < 5 else XRHandTracker.HAND_JOINT_PALM
		var tp := touch_points[f]
		var valid := _joint_globals.has(joint)
		if valid:
			tp.global_transform = _joint_globals[joint]
		if tp.monitorable != valid:
			tp.set_deferred("monitorable", valid)
		if tp.visible != valid:
			tp.visible = valid
	if _all_finger_joints_valid():
		var distances := PackedFloat32Array()
		for i in 5:
			distances.append(_joint_globals[TIP_JOINTS[i]].origin.distance_to(_joint_globals[KNUCKLE_JOINTS[i]].origin))
		finger_use.update(distances)
	if has_data != tracking:
		tracking = has_data
		tracking_changed.emit(tracking)


func _all_finger_joints_valid() -> bool:
	for i in 5:
		if not _joint_globals.has(TIP_JOINTS[i]) or not _joint_globals.has(KNUCKLE_JOINTS[i]):
			return false
	return true


func _origin_transform() -> Transform3D:
	var n := get_parent()
	while n != null:
		if n is XROrigin3D:
			return (n as XROrigin3D).global_transform
		n = n.get_parent()
	return Transform3D()


func _update_debug_meshes() -> void:
	for tp in touch_points:
		var existing := tp.get_node_or_null("DebugMesh")
		if show_touch_points and existing == null:
			var shape := tp.get_child(0) as CollisionShape3D
			var mi := MeshInstance3D.new()
			mi.name = "DebugMesh"
			if shape.shape is SphereShape3D:
				var m := SphereMesh.new()
				m.radius = (shape.shape as SphereShape3D).radius
				m.height = m.radius * 2.0
				mi.mesh = m
			else:
				var b := BoxMesh.new()
				b.size = (shape.shape as BoxShape3D).size
				mi.mesh = b
			mi.position = shape.position
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.95, 0.4, 0.1, 0.5)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tp.add_child(mi)
		elif not show_touch_points and existing != null:
			existing.queue_free()
