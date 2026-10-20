extends HexRTest
## The floating menu, laid out and behaving as the Unity package's: a fingertip entering a button's
## press volume presses it and feels a held press, only the index finger presses, a pinch on the
## header carries the panel, and the panel spawns to the left and outlives its scene.

const F := Haptics.Finger
const H := HaptGloveHandler.HandType

var hub: HexRManager
var sim: HexRSimulatedTransport
var lg: HexRSimulatedGlove
var menu: HexRFloatingMenu
var now := 1000


func before_each() -> void:
	sim = HexRSimulatedTransport.new()
	lg = sim.add_glove(HexRSimulatedGlove.new("AA:LEFT", HexRTypes.NAME_LEFT))
	hub = HexRManager.new()
	hub.drive_from_process = false
	hub.setup(sim, HexRDeviceStore.new(""))
	add_child(hub)
	hub.make_current()
	menu = HexRFloatingMenu.new()
	menu.show_scene_switcher = false
	menu.show_demo_groups = false
	add_child(menu)
	await wait_frames(3)


func after_each() -> void:
	# The menu moves itself to the tree's root to outlive scene changes, so free it here.
	if is_instance_valid(menu):
		menu.free()
	HexRFloatingMenu.instance = null


func tick_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		now += 16
		hub.tick(now)


func connect_left() -> void:
	hub.connect_hand(H.LEFT)
	for i in 40:
		now += 20
		hub.tick(now)


func _finger(f: int, hand: int = H.LEFT) -> HapticFingerTrigger:
	var tp := HapticFingerTrigger.new()
	tp.hand_type = hand
	tp.finger_type = f
	tp.collision_layer = 1 << 19
	tp.collision_mask = 0
	tp.monitoring = false
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.006
	shape.shape = s
	tp.add_child(shape)
	tp.position = Vector3(0, 5, 0)
	add_child(tp)
	return tp


func _pill(text: String) -> HexRMenuPanel.Pill:
	for b: Dictionary in menu.panel.buttons:
		if b["pill"].label.text == text:
			return b["pill"]
	return null


## Where a pill's centre is, in menu-local metres (the origin is the top of the header).
func _point(pill: HexRMenuPanel.Pill) -> Vector3:
	var c := pill.get_rect().get_center()
	var px := menu.panel_width / HexRFloatingMenu.VIEWPORT_WIDTH
	return Vector3((c.x - HexRFloatingMenu.VIEWPORT_WIDTH * 0.5) * px, -c.y * px, 0.0)


func test_builds_to_unitys_layout() -> void:
	# Unity's default panel (GLOVES, VIEW, HAPTICS) is 546 of its 360-pixel-wide units tall.
	assert_eq(menu.panel.size.x, 640.0, "panel width")
	assert_almost(menu.panel.size.y, ceilf(546.0 * 640.0 / 360.0), 0.5, "Unity's height, scaled")
	assert_almost(menu._size.x, 0.26, 1e-6, "panel width in metres")
	for text in ["Connect Left Glove", "Connect Right Glove", "Colliders  -  no rig"]:
		assert_true(_pill(text) != null, "button '%s'" % text)
	assert_eq(menu.panel.buttons.size(), 3, "three buttons")


func test_poke_presses_on_entry_and_holds_the_press() -> void:
	connect_left()
	assert_true(hub.is_hand_connected(H.LEFT), "connected")
	var index := _finger(F.INDEX)
	await tick_physics(2)
	var before := lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size()
	var view: HexRMenuPanel.Pill = menu.panel.buttons[2]["pill"]
	index.global_position = menu.to_global(_point(view))
	await tick_physics(3)
	assert_true(view.finger_down, "drawn pressed while the finger is in")
	var during := lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size()
	assert_true(during > before, "the index feels the press")
	index.global_position = Vector3(0, 5, 0)
	await tick_physics(10)  # the simulated link writes at most every 100 ms
	assert_false(view.finger_down, "released")
	assert_true(lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size() > during, "and let go when it left")


func test_connect_fires_on_entry() -> void:
	var index := _finger(F.INDEX)
	index.global_position = menu.to_global(_point(_pill("Connect Left Glove")))
	await tick_physics(3)
	assert_true(hub.is_hand_connecting(H.LEFT), "the press reached Connect while the finger is still in")
	index.global_position = Vector3(0, 5, 0)
	await tick_physics(2)


func test_other_fingers_do_not_press() -> void:
	var ring := _finger(F.RING)
	ring.global_position = menu.to_global(_point(_pill("Connect Left Glove")))
	await tick_physics(3)
	assert_false(hub.is_hand_connecting(H.LEFT), "a ring finger did not press Connect")


func test_pinch_on_header_carries_the_panel() -> void:
	var thumb := _finger(F.THUMB)
	var index := _finger(F.INDEX)
	var header := Vector3(0, -0.015, 0)
	thumb.global_position = menu.to_global(header + Vector3(-0.01, 0, 0))
	index.global_position = menu.to_global(header + Vector3(0.01, 0, 0))
	await tick_physics(3)
	var start := menu.global_position
	for tp in [thumb, index]:
		tp.global_position += Vector3(0.2, 0.1, 0)
	await tick_physics(3)
	assert_true(menu.global_position.distance_to(start + Vector3(0.2, 0.1, 0)) < 0.01, "panel moved with the pinch")
	index.global_position = Vector3(0, 5, 0)
	await tick_physics(2)
	var dropped_at := menu.global_position
	thumb.global_position += Vector3(0.3, 0, 0)
	await tick_physics(2)
	assert_true(menu.global_position.distance_to(dropped_at) < 0.001, "stays put once let go")


func test_recenter_faces_the_head_to_the_left() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(1, 1.6, 2)
	cam.make_current()
	menu.recenter()
	var to_cam := (cam.global_position - menu.global_position)
	to_cam.y = 0
	var front := menu.global_basis.z
	front.y = 0
	assert_true(front.normalized().dot(to_cam.normalized()) > 0.99, "panel front faces the head")
	assert_almost(menu.global_position.y, 1.4, 1e-3, "below eye level")
	assert_almost(menu.global_position.x, 1 - 0.35, 1e-3, "to the wearer's left, as in Unity")
	cam.queue_free()


func test_one_menu_for_the_session() -> void:
	await wait_frames(2)
	assert_eq(menu.get_parent(), get_tree().root, "moved to the root to outlive scene changes")
	assert_eq(HexRFloatingMenu.instance, menu, "the live panel")
	var second := HexRFloatingMenu.new()
	add_child(second)
	await wait_frames(2)
	assert_false(is_instance_valid(second), "a later scene's copy stands down")


func test_glove_button_says_what_the_glove_is_doing() -> void:
	connect_left()
	await wait_frames(2)
	var label := menu.panel._glove_labels[H.LEFT]
	assert_true(label.text.begins_with("Left"), "status on the button: " + label.text)
	assert_eq(label.get_theme_color("font_color"), HexRMenuPanel.OK, "mint when connected")


func test_readout_reads_like_unitys() -> void:
	var s := Haptics.ChannelState.new(Haptics.HapticMode.PRESSURE, 0.5, 0.0)
	assert_eq(HexRMenuPanel.format_channel(s), "0.5", "pressure")
	s = Haptics.ChannelState.new(Haptics.HapticMode.VIBRATION, 0.55, 30.0)
	assert_eq(HexRMenuPanel.format_channel(s), "0.55  30Hz", "vibration")
	s = Haptics.ChannelState.new(Haptics.HapticMode.VIBRATION, 1.0, 255.0)
	assert_eq(HexRMenuPanel.format_channel(s), "1  vib", "flagged vibration")
	s = Haptics.ChannelState.new(Haptics.HapticMode.PULSE, 0.3, 10.0)
	assert_eq(HexRMenuPanel.format_channel(s), "0.3  pulse", "pulse")


func test_scene_switcher_lists_the_project_scenes() -> void:
	var before: Variant = ProjectSettings.get_setting(SceneLoader.SETTING, PackedStringArray())
	ProjectSettings.set_setting(SceneLoader.SETTING, PackedStringArray(["res://x/1_basic_tutorial.tscn", "res://x/2_water.tscn"]))
	menu.show_scene_switcher = true
	menu._rebuild()
	await wait_frames(1)
	assert_true(_pill("1 Basic Tutorial") != null and _pill("2 Water") != null, "one button per scene")
	ProjectSettings.set_setting(SceneLoader.SETTING, before)
