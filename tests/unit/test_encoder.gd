extends HexRTest
## The bytes the glove receives. Reference frames come from the HexR Companion's tests and from
## the Unity package; golden_frames.json is a float32 sweep from tools/gen_golden_frames.py.

const F := HexRTypes.Finger


func test_reference_frames() -> void:
	var h := HexRHaptics.new()
	assert_bytes(h.hexr_pressure(F.INDEX, true, 1.0, 1.0),
			"12 04 09 00000000 01 01 01 00 09 00004842 01 64", "Companion reference: Index full")
	assert_bytes(h.hexr_pressure(F.INDEX, true, 0.8, 1.0),
			"12 04 09 00 00 00 00 01 01 01 00 09 8e e3 28 42 01 64", "Index 0.8")
	assert_bytes(h.hexr_pressure(F.INDEX, false, 0.0, 1.0),
			"12 04 09 00 00 00 00 01 01 01 02 09 00 00 70 41 01 64", "Index pressure release")
	assert_bytes(h.hexr_vibration(F.PALM, false, 1.0, 0.1),
			"12 07 09 00 00 80 3f 01 05 01 02 09 00 00 70 41 01 32", "Palm vibration release")
	assert_bytes(h.hexr_vibration(F.INDEX, true, 18.0, 0.8),
			"12 07 09 00 00 90 41 01 01 01 00 09 00 00 48 42 01 2b", "Index vibration 18 Hz 0.8")
	assert_bytes(HexRHaptics.pump_control(true), "06 02 01 01 01 50", "pump start")
	assert_bytes(HexRHaptics.pump_control(false), "06 02 01 00 01 00", "pump stop")


func test_golden_sweep() -> void:
	var data: Dictionary = load_json("res://tests/fixtures/golden_frames.json")
	var cases: Array = data["cases"]
	assert_true(cases.size() > 500, "golden file has its cases")
	var mismatches := 0
	for c in cases:
		var a: Array = c["args"]
		var h := HexRHaptics.new()
		var got := PackedByteArray()
		match c["kind"]:
			"pressure":
				got = h.hexr_pressure(int(a[0]), a[1], a[2], a[3])
			"vibration":
				got = h.hexr_vibration(int(a[0]), a[1], a[2], a[3])
			"pulse":
				got = h.hexr_pulse(int(a[0]), a[1], a[2], a[3], int(a[4]))
			"vibration_ramped":
				got = h.hexr_vibration_ramped(int(a[0]), a[1], a[2], a[3], a[4], a[5], a[6])
			"pulse_ramped":
				got = h.hexr_pulse_ramped(int(a[0]), a[1], a[2], a[3], a[4], a[5], int(a[6]), a[7])
			"pump":
				got = HexRHaptics.pump_control(a[0], int(a[1]))
			"release":
				var fingers: Array = []
				for x in a[0]:
					fingers.append(int(x))
				got = h.build_release(fingers)
			_:
				fail("unknown kind " + str(c["kind"]))
				continue
		if got.hex_encode() != c["hex"]:
			mismatches += 1
			if mismatches <= 5:
				fail("%s %s:\n    got  %s\n    want %s" % [c["kind"], str(a), got.hex_encode(), c["hex"]])
	assert_eq(mismatches, 0, "golden mismatches")


func test_release_all_matches_unity_layout() -> void:
	var h := HexRHaptics.new()
	var rel := h.build_release()
	assert_eq(rel.size(), 216, "release-all length")
	var frames := HexRFrames.split_frames(rel)
	assert_eq(frames.size(), 12, "release-all frame count")
	for ch in 6:
		assert_eq(frames[ch * 2][1], HexRTypes.Op.SET_VIBRATION, "vibration exit first for channel %d" % ch)
		assert_eq(frames[ch * 2 + 1][1], HexRTypes.Op.SET_PRESSURE, "then pressure exit for channel %d" % ch)
		assert_eq(frames[ch * 2][10], HexRTypes.STATE_EXIT, "exit state")


func test_pressure_clamps() -> void:
	var h := HexRHaptics.new()
	assert_eq(h.hexr_pressure(F.THUMB, true, 5.0, 5.0), h.hexr_pressure(F.THUMB, true, 1.0, 1.0), "upper clamp")
	assert_eq(h.hexr_pressure(F.THUMB, true, -1.0, 0.0), h.hexr_pressure(F.THUMB, true, 0.1, 0.1), "lower clamp")
	# Speed 0.1 is byte 10, speed 1 is byte 100.
	assert_eq(h.hexr_pressure(F.THUMB, true, 0.5, 0.1)[17], 10, "min speed byte")
	assert_eq(h.hexr_pressure(F.THUMB, true, 0.5, 1.0)[17], 100, "max speed byte")


func test_float32_speed_bytes() -> void:
	# The case that motivated HexRF32: 0.23 truncates to 22 in float32 (23 in float64).
	var h := HexRHaptics.new()
	assert_eq(h.hexr_pressure(F.INDEX, true, 0.5, 0.23)[17], 22, "speed 0.23")


func test_layouts_of_long_frames() -> void:
	var h := HexRHaptics.new()
	var pulse := h.hexr_pulse(F.RING, true, 12.0, 0.6, 250)
	assert_eq(pulse.size(), 21, "0x08 length")
	assert_eq(pulse[0], 21, "0x08 length byte")
	# [len][op] f32 freq (2..6), finger (7..8), state (9..10), f32 kPa (11..15), peak (16..17), u16 (18..20)
	assert_eq(pulse[18], HexRTlv.TAG_U16, "pulse count tag")
	assert_eq(pulse.decode_u16(19), 250, "pulse count little-endian")
	assert_eq(h.hexr_pulse(F.RING, true, 12.0, 0.6, 5000).decode_u16(19), 1000, "pulse count clamp")
	assert_eq(h.hexr_vibration_ramped(F.PALM, true, 1.0, 0.5, 0.5, 0.5, 0.0).size(), 25, "0x09 length")
	assert_eq(h.hexr_pulse_ramped(F.PALM, true, 1.0, 0.5, 0.5, 0.5, 3, 0.0).size(), 28, "0x0A length")
	assert_eq(HexRHaptics.set_pid(1.0, 0.5, 0.1).size(), 17, "0x05 length")


func test_multi_concatenates() -> void:
	var h := HexRHaptics.new()
	var multi := h.hexr_pressure_multi([F.THUMB, F.INDEX], [true, true], [0.5, 0.6], [1.0, 1.0])
	var single := h.hexr_pressure(F.THUMB, true, 0.5, 1.0)
	single.append_array(h.hexr_pressure(F.INDEX, true, 0.6, 1.0))
	assert_eq(multi, single, "multi equals concatenation")


func test_channel_log() -> void:
	var h := HexRHaptics.new()
	assert_eq(h.get_channel_state(F.INDEX).mode, HexRTypes.HapticMode.OFF, "starts off")
	h.hexr_pressure(F.INDEX, true, 0.8, 1.0)
	var s := h.get_channel_state(F.INDEX)
	assert_eq(s.mode, HexRTypes.HapticMode.PRESSURE, "pressure on")
	assert_almost(s.intensity, 0.8, 1e-6, "intensity recorded")
	assert_eq(h.get_activation_count(F.INDEX), 1, "one activation")
	h.hexr_pressure(F.INDEX, true, 0.8, 1.0)
	assert_eq(h.get_activation_count(F.INDEX), 2, "repeat counts")
	h.hexr_pressure(F.INDEX, false, 0.0, 1.0)
	assert_eq(h.get_channel_state(F.INDEX).mode, HexRTypes.HapticMode.OFF, "released")
	assert_eq(h.get_last_active_state(F.INDEX).mode, HexRTypes.HapticMode.PRESSURE, "last active kept")
	h.hexr_vibration(F.PALM, true, 18.0, 0.7)
	assert_eq(h.get_channel_state(F.PALM).mode, HexRTypes.HapticMode.VIBRATION, "vibration")
	assert_almost(h.get_channel_state(F.PALM).frequency, 18.0, 1e-6, "frequency")
	h.hexr_pulse(F.RING, true, 3.0, 0.5, 4)
	assert_eq(h.get_channel_state(F.RING).mode, HexRTypes.HapticMode.PULSE, "pulse")
	h.build_release()
	for f in 6:
		assert_eq(h.get_channel_state(f).mode, HexRTypes.HapticMode.OFF, "release turns channel %d off" % f)


func test_hand_from_device_name() -> void:
	assert_eq(HexRTypes.hand_from_device_name("HaptGloveAR Left"), HexRTypes.Hand.LEFT, "left")
	assert_eq(HexRTypes.hand_from_device_name(" HaptGloveAR Right "), HexRTypes.Hand.RIGHT, "right")
	assert_eq(HexRTypes.hand_from_device_name("HaptGloveAR"), -1, "no hand")
	assert_eq(HexRTypes.hand_from_device_name("Pixel Buds"), -1, "other device")
