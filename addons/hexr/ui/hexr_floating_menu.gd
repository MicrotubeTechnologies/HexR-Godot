@tool
class_name HexRFloatingMenu
extends Node3D
## The HexR menu as a panel in the room (port of the Unity package's HexRFloatingMenu): press its
## buttons with a fingertip, move it by pinching its header. It stays where it is put and does not
## follow the head; [method recenter] brings it in front of the wearer.
##
## Every button has a press volume of its own, as in Unity: the index finger presses on entry,
## feels a held press while it stays in, and can press again 0.2 s after it leaves. The volume
## reaches through the panel, so a finger from either side works.
##
## One panel serves the whole session: the first one moves to the scene tree's root and outlives
## scene changes, rebuilding its SCENES and DEMOS for each new scene; a later scene's copy stands
## down. Its origin is the top edge of the header, which is what you grab.

## The live panel, so anything can call [method recenter]. Null when there is none.
static var instance: HexRFloatingMenu

@export_group("Placement")
## How far in front of the head [method recenter] puts the panel, in metres.
@export var spawn_distance := 0.65
## How far to the side, in metres; negative is to the left.
@export var spawn_side_offset := -0.35
## How far above (or below, negative) the eyes.
@export var spawn_height_offset := -0.2
## Bring the panel in front of the wearer when the app starts.
@export var recenter_on_start := false
@export_group("Panel")
## Panel width in metres. Height follows from the contents.
@export var panel_width := 0.26:
	set(v):
		panel_width = v
		_queue_preview()
@export_group("Behaviour")
## One button per scene in the project setting [code]hexr/scenes[/code] (Godot's stand-in for
## Unity's Build Settings), when it lists two or more.
@export var show_scene_switcher := true:
	set(v):
		show_scene_switcher = v
		_queue_preview()
## One button per "... Demo Components" node in the scene, one of them shown at a time.
@export var show_demo_groups := true:
	set(v):
		show_demo_groups = v
		_queue_preview()
## What each channel of each glove was last told to do.
@export var show_haptics_readout := true:
	set(v):
		show_haptics_readout = v
		_queue_preview()
## Draw the panel in the editor's 3D view. The preview is never saved into the scene.
@export var preview_in_editor := true:
	set(v):
		preview_in_editor = v
		_queue_preview()

const VIEWPORT_WIDTH := 640
## Unity's press depth: 30 of its panel's 360 pixels, centred on the panel.
const PRESS_DEPTH_PX := 30.0

## The 2D content.
var panel: HexRMenuPanel
var _viewport: SubViewport
var _quad: MeshInstance3D
var _grip: Area3D
var _volumes: Array[Node] = []
var _size := Vector2.ZERO
var _drag_hand := -1
var _drag_offset := Transform3D()
var _moving := false
var _preview_queued := false


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild()
		return
	if instance != null and is_instance_valid(instance) and instance != self:
		queue_free()
		return
	instance = self
	_rebuild()
	get_tree().scene_changed.connect(_on_scene_changed)
	# Outlive scene changes, as the Unity panel does with DontDestroyOnLoad.
	if get_parent() != get_tree().root:
		_moving = true
		reparent.call_deferred(get_tree().root)
		_finish_move.call_deferred()
	if recenter_on_start:
		recenter.call_deferred()


# A HexR 0.1 menu carried its own scene list; the list is now the project setting hexr/scenes.
func _set(property: StringName, value: Variant) -> bool:
	if property != &"scenes":
		return false
	if not Engine.is_editor_hint():
		show_scene_switcher = not (value as PackedStringArray).is_empty()
	HexRTypes.warn_renamed(self, "scenes", "show_scene_switcher (list the scenes in the hexr/scenes project setting)")
	return true


func _finish_move() -> void:
	_moving = false


func _exit_tree() -> void:
	if _moving or Engine.is_editor_hint():
		return
	if instance == self:
		instance = null


func _on_scene_changed() -> void:
	# The scene list's current scene and the demos belong to the scene, so they are rebuilt;
	# the panel keeps wherever the wearer put it.
	_rebuild()


## Rebuilds the panel, its quad and its press volumes.
func _rebuild() -> void:
	_preview_queued = false
	for n in [_viewport, _quad, _grip] + _volumes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_volumes.clear()
	_viewport = null
	_quad = null
	_grip = null
	if Engine.is_editor_hint() and not preview_in_editor:
		return

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if Engine.is_editor_hint() else SubViewport.UPDATE_ALWAYS
	if panel == null or not is_instance_valid(panel):
		panel = HexRMenuPanel.new()
	elif panel.get_parent():
		panel.get_parent().remove_child(panel)
	panel.show_haptics_readout = show_haptics_readout
	panel.show_scene_switcher = show_scene_switcher
	panel.show_demo_groups = show_demo_groups
	_viewport.add_child(panel)
	_add(_viewport)
	panel.build(VIEWPORT_WIDTH)
	_viewport.size = Vector2i(panel.size)
	_size = Vector2(panel_width, panel_width * panel.size.y / VIEWPORT_WIDTH)

	_quad = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = _size
	_quad.mesh = mesh
	_quad.position = Vector3(0, -_size.y * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad.material_override = mat
	_add(_quad)
	if Engine.is_editor_hint():
		return

	var px := panel_width / VIEWPORT_WIDTH
	for b: Dictionary in panel.buttons:
		_volumes.append(_press_volume(b["pill"], b["rect"], px))
	# The header strip: a pinch there picks the panel up.
	var header_h := HexRMenuPanel.HEADER_HEIGHT * panel_width / HexRMenuPanel.UNITY_WIDTH
	_grip = _box_area(Area3D.new(), Vector3(_size.x, header_h, 0.02), Vector3(0, -header_h * 0.5, 0))


func _press_volume(pill: HexRMenuPanel.Pill, rect: Rect2, px: float) -> HexRPhysicalButton:
	var press := HexRPhysicalButton.new()
	press.name = "Press " + pill.label.text
	# No travel: the feedback is the button darkening. Pressure 35 is 0.55, held while the
	# finger is in, as the Unity menu does.
	press.travel = 0.0
	press.press_pressure = 35.0
	press.rearm_seconds = 0.2
	press.pressed.connect(func() -> void: panel.press(pill))
	press.released.connect(func() -> void: panel.release(pill))
	var c := rect.get_center()
	var depth := PRESS_DEPTH_PX / HexRMenuPanel.UNITY_WIDTH * panel_width
	return _box_area(press, Vector3(rect.size.x * px, rect.size.y * px, depth),
			Vector3((c.x - VIEWPORT_WIDTH * 0.5) * px, -c.y * px, 0))


func _box_area(area: Area3D, size: Vector3, at: Vector3) -> Area3D:
	area.collision_layer = 0
	area.collision_mask = 1 << 19
	area.monitorable = false
	area.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	_add(area)
	return area


# Internal children: never saved with the scene, never shown in the Scene dock.
func _add(n: Node) -> void:
	add_child(n, false, Node.INTERNAL_MODE_BACK)


func _queue_preview() -> void:
	if Engine.is_editor_hint() and is_inside_tree() and not _preview_queued:
		_preview_queued = true
		_rebuild.call_deferred()


## Puts the panel in front of the wearer's head, facing them. Safe to call any time.
func recenter() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var head := cam.global_transform
	# Flattened forward and right, so the panel hangs level however the head is tilted.
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var pos := head.origin + forward * spawn_distance + right * spawn_side_offset + Vector3.UP * spawn_height_offset
	global_position = pos
	# The quad's front is +Z: turn it to face the head, upright.
	look_at(Vector3(head.origin.x, pos.y, head.origin.z), Vector3.UP, true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or panel == null:
		return
	panel.refresh()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _grip == null:
		return
	_update_drag()


func _update_drag() -> void:
	var by_hand := [[null, null], [null, null]]  # [hand] -> [thumb, index]
	for a in _grip.get_overlapping_areas():
		if a is HapticFingerTrigger and (a.finger_type == Haptics.Finger.THUMB or a.finger_type == Haptics.Finger.INDEX):
			by_hand[a.hand_type][0 if a.finger_type == Haptics.Finger.THUMB else 1] = a
	if _drag_hand < 0:
		for hand in 2:
			if by_hand[hand][0] != null and by_hand[hand][1] != null:
				_drag_hand = hand
				_drag_offset = _hand_frame(hand, by_hand[hand][1]).affine_inverse() * global_transform
				break
	elif by_hand[_drag_hand][0] == null or by_hand[_drag_hand][1] == null:
		_drag_hand = -1
	if _drag_hand >= 0:
		# Position and rotation follow the hand freely, as in Unity.
		global_transform = _hand_frame(_drag_hand, by_hand[_drag_hand][1]) * _drag_offset


# The palm's frame when the hand is tracked; a fingertip's turns as the pinch curls the finger.
func _hand_frame(hand: int, index_tip: HapticFingerTrigger) -> Transform3D:
	var hub := HexRManager.get_instance()
	var tracked := hub.tracked_hand(hand) if hub else null
	if tracked and tracked.is_joint_valid(XRHandTracker.HAND_JOINT_PALM):
		return tracked.get_joint_global_transform(XRHandTracker.HAND_JOINT_PALM)
	return index_tip.global_transform
