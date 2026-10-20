extends HexRTest
## Touch points on an injected OpenXR hand tracker, and the components they drive, through real
## physics overlaps and the simulated glove.

const F := Haptics.Finger
const H := HaptGloveHandler.HandType

var hub: HexRManager
var sim: HexRSimulatedTransport
var lg: HexRSimulatedGlove
var tracker: XRHandTracker
var origin: XROrigin3D
var rig: HexRRig
var now := 1000
# Where each joint is, relative to the wrist; the hand points along -Z with the palm down (-Y).
var pose: Dictionary = {}
var wrist := Vector3(0, 1, 0)


func before_each() -> void:
	sim = HexRSimulatedTransport.new()
	lg = sim.add_glove(HexRSimulatedGlove.new("AA:LEFT", HexRTypes.NAME_LEFT))
	lg.mtu = 247
	hub = HexRManager.new()
	hub.drive_from_process = false
	hub.setup(sim, HexRDeviceStore.new(""))
	add_child(hub)
	hub.make_current()
	for g in [hub.left, hub.right]:
		g.coalescer.min_interval_ms = 0
	hub.connect_hand(H.LEFT)
	for i in 50:
		now += 20
		hub.tick(now)
	assert_true(hub.is_hand_connected(H.LEFT), "glove connected")

	tracker = XRHandTracker.new()
	tracker.name = &"/user/hand_tracker/left"
	tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT
	XRServer.add_tracker(tracker)
	_open_pose()
	_apply_pose()

	origin = XROrigin3D.new()
	add_child(origin)
	rig = HexRRig.new()
	origin.add_child(rig)
	await wait_physics(2)


func after_each() -> void:
	XRServer.remove_tracker(tracker)
	if is_instance_valid(origin):
		origin.queue_free()


func wait_physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		now += 16
		hub.tick(now)


func _open_pose() -> void:
	pose.clear()
	pose[XRHandTracker.HAND_JOINT_WRIST] = Vector3.ZERO
	pose[XRHandTracker.HAND_JOINT_PALM] = Vector3(0, 0, -0.05)
	var xs := [0.04, 0.02, 0.0, -0.02, -0.04]
	var metacarpal := [XRHandTracker.HAND_JOINT_THUMB_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL,
			XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL]
	for f in 5:
		pose[metacarpal[f]] = Vector3(xs[f], 0, -0.03)
		pose[HexRTrackedHand.KNUCKLE_JOINTS[f]] = Vector3(xs[f], 0, -0.08)
		pose[HexRTrackedHand.TIP_JOINTS[f]] = Vector3(xs[f], 0, -0.16)


func _apply_pose() -> void:
	tracker.has_tracking_data = true
	var flags := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED \
			| XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED
	for joint in pose.keys():
		tracker.set_hand_joint_flags(joint, flags)
		tracker.set_hand_joint_transform(joint, Transform3D(Basis(), wrist + pose[joint]))


func _tip(f: int) -> Vector3:
	return wrist + pose[HexRTrackedHand.TIP_JOINTS[f]]


func _zone_at(node: Area3D, at: Vector3, radius: float) -> Area3D:
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	shape.shape = s
	node.add_child(shape)
	node.position = at
	origin.add_child(node)
	return node


func test_touch_points_follow_joints() -> void:
	var hand := hub.tracked_hand(H.LEFT)
	assert_true(hand != null, "rig registered a left hand")
	assert_true(hub.controller(H.LEFT) != null, "rig registered a left Pressure Controller")
	assert_true(hand.tracking, "tracking")
	var index := hand.touch_point(F.INDEX)
	assert_true(index.global_position.distance_to(_tip(F.INDEX)) < 0.001, "index touch point at the tip joint")
	assert_true(index.monitorable, "valid joint is monitorable")
	wrist = Vector3(0.3, 1.2, -0.4)
	_apply_pose()
	await wait_physics(2)
	assert_true(index.global_position.distance_to(_tip(F.INDEX)) < 0.001, "moved with the hand")
	tracker.has_tracking_data = false
	await wait_physics(2)
	assert_false(hand.tracking, "lost tracking")
	assert_false(index.monitorable, "untracked touch point stops touching")


func test_physical_button_presses_the_finger() -> void:
	var button := HexRPhysicalButton.new()
	var presses: Array[int] = []
	button.pressed.connect(func() -> void: presses.append(1))
	_zone_at(button, _tip(F.INDEX) + Vector3(0, 0, -0.3), 0.02)  # out of reach to start
	await wait_physics(2)
	var before := lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size()
	button.position = _tip(F.INDEX)
	await wait_physics(3)
	assert_eq(presses.size(), 1, "pressed once")
	var frames := lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE)
	assert_true(frames.size() > before, "a pressure frame reached the glove")
	assert_eq(frames.back()[8], F.INDEX, "on the index channel")
	assert_eq(frames.back()[10], HexRTypes.STATE_ENTER, "pressing")
	button.position += Vector3(0, 0, -0.3)
	await wait_physics(3)
	assert_eq(lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).back()[10], HexRTypes.STATE_EXIT, "released on exit")


func test_physical_button_ignores_other_fingers() -> void:
	var button := HexRPhysicalButton.new()
	var presses: Array[int] = []
	button.pressed.connect(func() -> void: presses.append(1))
	_zone_at(button, _tip(F.PINKY), 0.01)
	await wait_physics(3)
	assert_eq(presses.size(), 0, "pinky does not press an index-only button")


func test_proximity_opens_hand_near_check() -> void:
	var c := hub.controller(H.LEFT)
	var zone := ProximityCheck.new()
	zone.clear_delay = 0.05
	_zone_at(zone, _tip(F.MIDDLE), 0.05)
	await wait_physics(3)
	assert_true(c.is_hand_near(), "near while touching")
	var before := lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size()
	c.single_index_haptic(0.7)
	assert_eq(lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size(), before + 1, "gated call goes through when near")
	zone.position += Vector3(0, 2, 0)
	await wait_physics(8)
	assert_false(c.is_hand_near(), "not near once gone")
	c.single_index_haptic(0.7)
	assert_eq(lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size(), before + 1, "gated call is dropped when not near")


func test_special_haptics_fountain_vibrates_and_stops() -> void:
	var zone := SpecialHaptics.new()
	zone.effect = SpecialHaptics.Effect.FOUNTAIN
	_zone_at(zone, _tip(F.INDEX), 0.015)
	await wait_physics(30)
	assert_true(lg.vibrating[F.INDEX], "index vibrating in the fountain")
	var vib := lg.frames_with_op(Haptics.FunIndex.FI_SET_VIBRATION)
	assert_almost(vib.back().decode_float(3), 18.0, 1e-4, "at 18 Hz")
	zone.position += Vector3(0, 2, 0)
	await wait_physics(30)
	assert_false(lg.vibrating[F.INDEX], "stopped after the hand left")


func test_special_haptics_custom_presses_and_releases() -> void:
	var zone := SpecialHaptics.new()
	zone.effect = SpecialHaptics.Effect.CUSTOM_HAPTICS
	zone.haptic_pressure = 40.0
	_zone_at(zone, _tip(F.RING), 0.012)
	await wait_physics(4)
	assert_true(lg.target_kpa[F.RING] > 0.0, "ring pressed")
	zone.position += Vector3(0, 2, 0)
	await wait_physics(12)
	assert_eq(lg.target_kpa[F.RING], 0.0, "released after the grace")


func test_zone_releases_on_removal() -> void:
	var zone := SpecialHaptics.new()
	zone.effect = SpecialHaptics.Effect.CUSTOM_VIBRATIONS
	zone.vibration_frequency = 25.0
	_zone_at(zone, _tip(F.INDEX), 0.015)
	await wait_physics(20)
	assert_true(lg.vibrating[F.INDEX], "vibrating")
	zone.queue_free()
	await wait_physics(2)
	assert_false(lg.any_channel_on(), "removing the zone released its channels")


func test_pinch_grab_follows_and_lets_go() -> void:
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	var grab := HexRGrabbable.new()
	grab.haptic_strength = 30.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.036, 0.03, 0.03)  # covers the thumb and index tips only
	shape.shape = box
	grab.add_child(shape)
	body.add_child(grab)
	var mid := (_tip(F.THUMB) + _tip(F.INDEX)) / 2.0
	body.position = mid
	origin.add_child(body)
	var events: Array[String] = []
	grab.grabbed.connect(func(h: int) -> void: events.append("grabbed %d" % h))
	grab.released.connect(func(h: int) -> void: events.append("released %d" % h))
	await wait_physics(3)
	assert_eq(events, ["grabbed %d" % H.LEFT] as Array[String], "pinch grabbed by the left hand")
	assert_true(body.freeze, "frozen while held")
	assert_true(hub.controller(H.LEFT).hand_grabbing, "hand marked as grabbing")
	assert_true(lg.target_kpa[F.THUMB] > 0.0 and lg.target_kpa[F.INDEX] > 0.0, "thumb and index pressed")
	var offset := body.global_position - _tip(F.THUMB)
	wrist += Vector3(0.2, 0.1, 0.0)
	_apply_pose()
	await wait_physics(3)
	assert_true(body.global_position.distance_to(_tip(F.THUMB) + offset) < 0.002, "object follows the hand")
	# Only the thumb still touching: let go.
	pose[HexRTrackedHand.TIP_JOINTS[F.INDEX]] += Vector3(0, 0.3, 0)
	_apply_pose()
	await wait_physics(3)
	assert_eq(events.back(), "released %d" % H.LEFT, "released")
	assert_false(body.freeze, "unfrozen")
	assert_false(hub.controller(H.LEFT).hand_grabbing, "no longer grabbing")
	assert_eq(lg.target_kpa[F.THUMB], 0.0, "thumb released")


func test_finger_use_calibrates() -> void:
	var hand := hub.tracked_hand(H.LEFT)
	# Curl the index (tip toward the knuckle), then open it.
	pose[HexRTrackedHand.TIP_JOINTS[F.INDEX]] = Vector3(0.02, -0.02, -0.09)
	_apply_pose()
	await wait_physics(2)
	_open_pose()
	_apply_pose()
	await wait_physics(2)
	assert_almost(hand.finger_use.index_use, 1.0, 1e-3, "open index is 1")
	pose[HexRTrackedHand.TIP_JOINTS[F.INDEX]] = Vector3(0.02, -0.02, -0.09)
	_apply_pose()
	await wait_physics(2)
	assert_almost(hand.finger_use.index_use, 0.0, 1e-3, "curled index is 0")


func test_interactable_haptics_follows_state() -> void:
	var ih := HexRInteractableHaptics.new()
	ih.auto_bind_xr_tools = false
	ih.follow_grip = false
	ih.strength = 40.0
	ih.palm = false
	add_child(ih)
	var c := hub.controller(H.LEFT)
	c.hand_grabbing_check(true)
	ih.set_interactor_state("hand", H.LEFT, false, true)
	await wait_physics(1)
	assert_true(lg.target_kpa[F.THUMB] > 0.0 and lg.target_kpa[F.INDEX] > 0.0 and lg.target_kpa[F.MIDDLE] > 0.0,
			"chosen fingers pressed while selected")
	assert_eq(lg.target_kpa[F.PALM], 0.0, "palm left out")
	ih.set_interactor_state("hand", H.LEFT, false, false)
	await wait_physics(1)
	assert_false(lg.any_channel_on(), "released when let go")
	c.hand_grabbing_check(false)
	ih.queue_free()


func test_strength_scale() -> void:
	assert_almost(PressureTrackerMain.strength_to_intensity(10), 0.1, 1e-6, "10 is lightest")
	assert_almost(PressureTrackerMain.strength_to_intensity(60), 1.0, 1e-6, "60 is firmest")
	assert_almost(PressureTrackerMain.strength_to_intensity(35), 0.55, 1e-6, "midpoint")
	assert_almost(PressureTrackerMain.strength_to_intensity(0), 0.1, 1e-6, "clamped low")
	assert_almost(PressureTrackerMain.strength_to_intensity(90), 1.0, 1e-6, "clamped high")
