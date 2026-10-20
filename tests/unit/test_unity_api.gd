extends HexRTest
## The Godot addon uses the Unity package's names: these tests fail if a Unity-named member
## goes missing, if a glove signal stops reaching HexRManager, or if a HexR 0.1 scene's
## property names stop being understood.

const H := HaptGloveHandler.HandType

## Unity name (snake_case) of every member a game script is likely to use, per class.
const PARITY := {
	"HexRManager": ["connect_hand", "disconnect_hand", "is_hand_connected", "is_hand_connecting",
			"begin_connect", "connect_left_bt", "connect_right_bt", "left_hand", "right_hand",
			"connect_attempt_ended"],
	"HaptGloveHandler": ["bt_connection", "bt_disconnection", "get_remembered_device_id", "remember_device",
			"forget_device", "connect_to_device", "air_pressure_source_control", "release_all_channels",
			"release_channels", "get_air_pressure", "get_finger_position", "get_battery_level",
			"set_battery_level_update_interval", "bt_send", "which_hand", "haptics", "ble_connected",
			"release_when_paused", "use_custom_device_name", "optional_custom_device_name", "battery_state",
			"bluetooth_connected", "bluetooth_disconnected", "bluetooth_connection_failed", "pump_changed",
			"battery_state_changed", "device_found"],
	"Haptics": ["get_channel_state", "get_last_active_state", "get_activation_count", "hexr_pressure",
			"hexr_vibration", "hexr_pulse"],
	"PressureTrackerMain": ["hand_grabbing_check", "poke_hovering_check", "is_physics_collision_near",
			"strength_to_intensity", "single_thumb_haptic", "single_index_haptic", "single_middle_haptic",
			"single_ring_haptic", "single_pinky_haptic", "single_palm_haptic", "remove_thumb_haptics",
			"remove_index_haptics", "remove_middle_haptics", "remove_ring_haptics", "remove_pinky_haptics",
			"remove_palm_haptics", "custom_single_haptics", "custom_single_vibrations",
			"trigger_all_haptics_increase", "trigger_custom_haptics_increase", "trigger_pinch_pressure",
			"remove_pinch_pressure", "trigger_all_vibrations", "trigger_custom_vibrations",
			"remove_all_haptics", "remove_all_vibrations", "trigger_pulse_it", "hand_type", "hand_grabbing",
			"poke_hovering", "thumb_pressure", "index_pressure", "middle_pressure", "ring_pressure",
			"little_pressure", "palm_pressure", "tank_pressure", "glove_handler", "collision_near_hand"],
	"HapticFingerTrigger": ["trigger_fix_pressure", "trigger_vibration_pressure", "remove_vibration",
			"remove_haptics", "hand_type", "finger_type"],
	"FingerUseTracking": ["is_hand_open", "thumb_use", "index_use", "middle_use", "ring_use", "little_use"],
	"HexRTrackedHand": ["hand_type"],
	"HexRGrabbable": ["type_of_grab", "the_object", "haptic_strength", "gravity_on_release"],
	"HexRPhysicalButton": ["thumb", "index", "middle", "ring", "pinky", "palm", "cap", "travel",
			"press_direction", "press_pressure", "rearm_seconds"],
	"HexRUsable": ["thumb", "index_finger", "middle_finger", "ring_finger", "little_finger", "use_threshold"],
	"ProximityCheck": ["clear_delay"],
	"SpecialHaptics": ["type_of_haptics", "haptic_strength_value", "vibrations_frequency_value",
			"haptic_pressure", "heart_beat_pressure", "heartbeat", "in_timer", "out_timer", "include_palm",
			"squeeze_tightness", "toggle_heart_regularity"],
	"HexRInteractableHaptics": ["fire_on", "thumb", "index", "middle", "ring", "pinky", "palm", "strength",
			"follow_grip", "min_strength"],
	"HexRFloatingMenu": ["recenter", "spawn_distance", "spawn_side_offset", "spawn_height_offset",
			"panel_width", "show_haptics_readout"],
	"HexRRemote": ["register_command", "unregister_command", "phones_connected", "allow_glove_control",
			"allow_video", "expose_scenes"],
}


func _make(class_name_: String) -> Object:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == class_name_:
			return load(c["path"]).new()
	return null


func _has_member(o: Object, member: String) -> bool:
	if o.has_method(member) or o.has_signal(member):
		return true
	for p in o.get_property_list():
		if p["name"] == member:
			return true
	return false


func test_unity_named_members_exist() -> void:
	for class_name_: String in PARITY:
		var o := _make(class_name_)
		assert_true(o != null, "class %s exists" % class_name_)
		if o == null:
			continue
		for member: String in PARITY[class_name_]:
			assert_true(_has_member(o, member), "%s.%s" % [class_name_, member])
		if o is Node:
			o.free()


func test_unity_enums_have_unity_homes() -> void:
	assert_eq(HaptGloveHandler.HandType.RIGHT, 1, "HaptGloveHandler.HandType")
	assert_eq(HaptGloveHandler.BatteryState.LOW, 2, "HaptGloveHandler.BatteryState")
	assert_eq(Haptics.Finger.PALM, 5, "Haptics.Finger is the wire order")
	assert_eq(Haptics.HapticMode.PULSE, 3, "Haptics.HapticMode")
	assert_eq(Haptics.FunIndex.FI_SET_PRESSURE, 0x04, "Haptics.FunIndex")
	assert_eq(HexRGrabbable.Options.PALM_GRAB, 1, "HexRGrabbable.Options")
	assert_eq(SpecialHaptics.Options.HAND_SQUEEZE_EFFECT, 5, "SpecialHaptics.Options, Unity's order")
	assert_true(HexRManager.instance == null or HexRManager.instance is HexRManager, "HexRManager.instance")


func test_every_glove_signal_reaches_the_manager_with_its_hand() -> void:
	var hub := HexRManager.new()
	hub.drive_from_process = false
	hub.setup(HexRSimulatedTransport.new(), HexRDeviceStore.new(""))
	add_child(hub)
	var got: Array[String] = []
	for sig in ["glove_connected", "glove_disconnected", "glove_connect_failed", "connect_attempt_ended"]:
		hub.connect(sig, func(hand: int) -> void: got.append("%s %d" % [sig, hand]))
	hub.battery_state_changed.connect(func(hand: int, s: int) -> void: got.append("battery %d %d" % [hand, s]))
	hub.pump_changed.connect(func(hand: int, on: bool) -> void: got.append("pump %d %s" % [hand, on]))
	hub.status_changed.connect(func(hand: int, t: String) -> void: got.append("status %d %s" % [hand, t]))
	var g := hub.right_hand
	g.bluetooth_connected.emit(H.RIGHT)
	g.bluetooth_disconnected.emit(H.RIGHT)
	g.bluetooth_connection_failed.emit(H.RIGHT)
	g.connect_campaign_ended.emit(H.RIGHT)
	g.battery_state_changed.emit(H.RIGHT, HaptGloveHandler.BatteryState.LOW)
	g.pump_changed.emit(H.RIGHT, true)
	g._set_status("hello")
	assert_eq(got, ["glove_connected 1", "glove_disconnected 1", "glove_connect_failed 1",
			"connect_attempt_ended 1", "battery 1 2", "pump 1 true", "status 1 hello"], "forwarded")
	hub.queue_free()


func test_0_1_property_names_still_load() -> void:
	var zone := SpecialHaptics.new()
	zone.set("effect", 4)
	zone.set("haptic_strength", 0.7)
	zone.set("vibration_frequency", 25.0)
	zone.set("heart_beat", SpecialHaptics.HeartBeat.IRREGULAR)
	assert_eq(zone.type_of_haptics, SpecialHaptics.Options.HEART_BEAT_EFFECT, "effect")
	assert_almost(zone.haptic_strength_value, 0.7, 1e-6, "haptic_strength")
	assert_almost(zone.vibrations_frequency_value, 25.0, 1e-6, "vibration_frequency")
	assert_eq(zone.heartbeat, SpecialHaptics.HeartBeat.IRREGULAR, "heart_beat")
	zone.free()

	var grab := HexRGrabbable.new()
	var body := Node3D.new()
	grab.set("grab_type", 1)
	grab.set("target", body)
	assert_eq(grab.type_of_grab, HexRGrabbable.Options.PALM_GRAB, "grab_type")
	assert_eq(grab.the_object, body, "target")
	grab.free()
	body.free()

	var button := HexRPhysicalButton.new()
	button.set("fingers", 1 | 32)
	assert_true(button.thumb and button.palm and not button.index, "fingers bitmask")
	button.free()

	var usable := HexRUsable.new()
	usable.set("fingers", 2)
	assert_true(usable.index_finger and not usable.thumb and not usable.little_finger, "fingers bitmask")
	usable.free()
