class_name HexRFloatingMenu
extends Node3D
## The HexR menu as a panel in the room (port of the Unity package's HexRFloatingMenu): press
## its buttons with a fingertip, move it by pinching its header. It stays where it is put, and
## does not follow the head; call [method recenter] to bring it in front of the wearer.
##
## Each press gives the pressing finger a short tap.

## Panel width in metres.
@export var panel_width := 0.26
@export var show_haptics_readout := true
## Scene paths offered on the panel. Empty hides the section.
@export var scenes: PackedStringArray = []
## Where [method recenter] puts the panel, relative to the head.
@export var spawn_distance := 0.65
@export var spawn_height_offset := -0.2
@export var spawn_side_offset := -0.35
## Bring the panel in front of the wearer when the scene starts.
@export var recenter_on_start := false

const VIEWPORT_WIDTH := 640
const POKE_DEPTH := 0.03
const TAP_INTENSITY := 0.35

var panel: HexRMenuPanel
var _viewport: SubViewport
var _quad: MeshInstance3D
var _poke: Area3D
var _grip: Area3D
var _poker: HexRTouchPoint
var _last_poke := Vector2.ZERO
var _drag_offset := Transform3D()
var _dragging_with: HexRTouchPoint
var _size := Vector2.ZERO


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.gui_embed_subwindows = true
	panel = HexRMenuPanel.new()
	panel.show_haptics_readout = show_haptics_readout
	panel.scenes = scenes
	panel.recenter_requested.connect(recenter)
	panel.touch_points_toggled.connect(_set_touch_points_visible)
	panel.scene_requested.connect(func(path: String) -> void: get_tree().change_scene_to_file(path))
	_viewport.add_child(panel)
	add_child(_viewport)
	# Let the panel lay itself out, then size the viewport and the quad to it.
	await get_tree().process_frame
	var px := Vector2i(VIEWPORT_WIDTH, maxi(int(panel.get_combined_minimum_size().y), 200))
	_viewport.size = px
	panel.size = Vector2(px)
	_size = Vector2(panel_width, panel_width * px.y / px.x)
	_build_surface()
	if recenter_on_start:
		recenter()


func _build_surface() -> void:
	_quad = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = _size
	_quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_quad.material_override = mat
	add_child(_quad)

	# A thin volume in front of the panel: a fingertip entering it presses.
	_poke = _box_area(Vector3(_size.x, _size.y, POKE_DEPTH), Vector3(0, 0, POKE_DEPTH * 0.5 - 0.004))
	_poke.area_entered.connect(_on_poke_entered)
	_poke.area_exited.connect(_on_poke_exited)
	# The header strip: a pinch there picks the panel up.
	var header_h := 0.035
	_grip = _box_area(Vector3(_size.x, header_h, 0.06), Vector3(0, _size.y * 0.5 - header_h * 0.5, 0.01))


func _box_area(size: Vector3, offset: Vector3) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 << 19
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset
	area.add_child(shape)
	add_child(area)
	return area


## Puts the panel in front of the wearer's head, facing them.
func recenter() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var head := cam.global_transform
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var pos := head.origin + forward * spawn_distance + Vector3.UP * spawn_height_offset + right * -spawn_side_offset
	global_position = pos
	# The quad's front is +Z: turn it to face the head, upright.
	look_at(Vector3(head.origin.x, pos.y, head.origin.z), Vector3.UP, true)


func _physics_process(_delta: float) -> void:
	if _quad == null:
		return
	_update_drag()
	# Follow the finger only while it is in front of the panel. This runs before the physics
	# step reports an exit, so a finger already pulled away must not move the pointer.
	if _poker != null and is_instance_valid(_poker) and _in_poke_volume(_poker):
		_last_poke = _panel_position(_poker)
		_send_at(_last_poke, InputEventMouseMotion.new())


func _update_drag() -> void:
	var by_hand := [[null, null], [null, null]]  # [hand] -> [thumb, index]
	for a in _grip.get_overlapping_areas():
		if a is HexRTouchPoint and (a.finger == HexRTypes.Finger.THUMB or a.finger == HexRTypes.Finger.INDEX):
			by_hand[a.hand][0 if a.finger == HexRTypes.Finger.THUMB else 1] = a
	if _dragging_with == null:
		for hand in 2:
			if by_hand[hand][0] != null and by_hand[hand][1] != null:
				_dragging_with = by_hand[hand][1]
				_drag_offset = _dragging_with.global_transform.affine_inverse() * global_transform
				break
	elif by_hand[_dragging_with.hand][0] == null or by_hand[_dragging_with.hand][1] == null:
		_dragging_with = null
	if _dragging_with != null:
		var t := _dragging_with.global_transform * _drag_offset
		# Keep the panel upright while carried.
		global_position = t.origin
		var fwd := t.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.01:
			global_basis = Basis.looking_at(-fwd.normalized(), Vector3.UP)


func _on_poke_entered(area: Area3D) -> void:
	if _poker != null or _dragging_with != null or not (area is HexRTouchPoint):
		return
	var tp := area as HexRTouchPoint
	if tp.finger != HexRTypes.Finger.INDEX:
		return
	_poker = tp
	_last_poke = _panel_position(tp)
	_send_at(_last_poke, InputEventMouseMotion.new())
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_send_at(_last_poke, press)
	_tap(tp)


func _on_poke_exited(area: Area3D) -> void:
	if area != _poker:
		return
	# Released where the finger last was on the panel: a finger pulling back has already left
	# by the time this runs, and a release outside the button would cancel the click.
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	_send_at(_last_poke, release)
	_poker = null


func _in_poke_volume(tp: HexRTouchPoint) -> bool:
	var local := to_local(tp.global_position)
	return absf(local.x) <= _size.x * 0.5 and absf(local.y) <= _size.y * 0.5 			and local.z >= -0.01 and local.z <= POKE_DEPTH


## The fingertip mapped onto the panel, in viewport pixels.
func _panel_position(tp: HexRTouchPoint) -> Vector2:
	var local := to_local(tp.global_position)
	var uv := Vector2(local.x / _size.x + 0.5, 0.5 - local.y / _size.y)
	return uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(_viewport.size)


func _send_at(pos: Vector2, event: InputEventMouse) -> void:
	event.position = pos
	event.global_position = pos
	_viewport.push_input(event)


func _tap(tp: HexRTouchPoint) -> void:
	tp.trigger_fix_pressure(TAP_INTENSITY)
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(tp):
		tp.remove_haptics()


func _set_touch_points_visible(v: bool) -> void:
	var hub := HexRManager.get_instance()
	if hub == null:
		return
	for hand in 2:
		var h := hub.tracked_hand(hand)
		if h:
			h.show_touch_points = v
