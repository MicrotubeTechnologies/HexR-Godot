extends HexRTest
## The floating menu: a fingertip poke lands on the right button, taps the finger, and a pinch
## on the header carries the panel.

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
	add_child(menu)
	await wait_frames(3)


func tick_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		now += 16
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


## Where on the panel (menu-local metres) a Control's centre is.
func _panel_point(c: Control) -> Vector3:
	var rect := c.get_global_rect()
	var uv := rect.get_center() / Vector2(menu._viewport.size)
	return Vector3((uv.x - 0.5) * menu._size.x, (0.5 - uv.y) * menu._size.y, 0.005)


func test_builds_to_content_size() -> void:
	assert_true(menu._viewport.size.y > 300, "viewport sized to the panel: %s" % str(menu._viewport.size))
	assert_almost(menu._size.x, 0.26, 1e-6, "panel width in metres")
	assert_true(menu._size.y > 0.1, "aspect kept")


func test_poke_presses_connect_and_taps() -> void:
	# Connected glove to feel the tap; then the press toggles it off (Disconnect).
	hub.connect_hand(H.LEFT)
	for i in 40:
		now += 20
		hub.tick(now)
	assert_true(hub.is_hand_connected(H.LEFT), "connected")
	await wait_ms(300)  # the panel refreshes five times a second
	var button: Button = menu.panel._connect[H.LEFT]
	assert_eq(button.text, "Disconnect", "button reflects the connection")
	var index := _finger(F.INDEX)
	await tick_physics(2)
	var before := lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size()
	index.global_position = menu.to_global(_panel_point(button))
	await tick_physics(3)
	assert_true(lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size() > before, "the poke tapped the index")
	index.global_position = Vector3(0, 5, 0)
	await tick_physics(3)
	await wait_frames(2)
	assert_false(hub.is_hand_connected(H.LEFT), "the press reached the Disconnect button")


func test_other_fingers_do_not_press() -> void:
	var button: Button = menu.panel._connect[H.LEFT]
	var ring := _finger(F.RING)
	ring.global_position = menu.to_global(_panel_point(button))
	await tick_physics(3)
	ring.global_position = Vector3(0, 5, 0)
	await tick_physics(3)
	assert_false(hub.is_hand_connecting(H.LEFT), "a ring finger did not press Connect")


func test_pinch_on_header_carries_the_panel() -> void:
	var thumb := _finger(F.THUMB)
	var index := _finger(F.INDEX)
	var header := Vector3(0, menu._size.y * 0.5 - 0.015, 0.01)
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


func test_recenter_faces_the_camera() -> void:
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
	cam.queue_free()
