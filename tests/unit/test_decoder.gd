extends HexRTest
## Notifications from the glove: three checksummed frames, 50 times a second.


static func _pressure_frame(values: Array) -> PackedByteArray:
	var p := PackedByteArray()
	for v in values:
		p.append_array(HexRTlv.f32(v))
	return HexRFrameDecoder.build_inbound(HexRTypes.InOp.PRESSURE, p)


static func _position_frame(values: Array) -> PackedByteArray:
	var p := PackedByteArray()
	for v in values:
		p.append_array(HexRTlv.i32(v))
	return HexRFrameDecoder.build_inbound(HexRTypes.InOp.MICROTUBE, p)


static func _battery_frame(v: float) -> PackedByteArray:
	return HexRFrameDecoder.build_inbound(HexRTypes.InOp.BATTERY, HexRTlv.f32(v))


static func _bundle() -> PackedByteArray:
	# The glove's 74-byte notification: positions, pressures, battery.
	var b := _position_frame([100, 200, 300, 400, 500])
	b.append_array(_pressure_frame([1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 80.0]))
	b.append_array(_battery_frame(0.75))
	return b


func test_frame_lengths_match_firmware() -> void:
	assert_eq(_position_frame([0, 0, 0, 0, 0]).size(), 28, "0x04 is 28 bytes")
	assert_eq(_pressure_frame([0, 0, 0, 0, 0, 0, 0]).size(), 38, "0x01 is 38 bytes")
	assert_eq(_battery_frame(1.0).size(), 8, "0x06 is 8 bytes")
	assert_eq(_bundle().size(), 74, "bundle is 74 bytes")


func test_decodes_bundle() -> void:
	var d := HexRFrameDecoder.new()
	assert_eq(d.feed(_bundle()), 3, "three frames")
	assert_eq(d.finger_position, PackedInt32Array([100, 200, 300, 400, 500]), "positions")
	assert_almost(d.pressure_raw[0], 1.5, 1e-6, "thumb pressure")
	assert_almost(d.pressure_raw[6], 80.0, 1e-6, "source pressure")
	assert_almost(d.battery, 0.75, 1e-6, "battery")
	assert_true(d.seen, "seen")
	assert_eq(d.bad_frames, 0, "no bad frames")


func test_split_across_notifications() -> void:
	var d := HexRFrameDecoder.new()
	var b := _bundle()
	for i in b.size():
		d.feed(b.slice(i, i + 1))
	assert_eq(d.position_frames, 1, "positions after byte-by-byte feed")
	assert_eq(d.pressure_frames, 1, "pressures after byte-by-byte feed")
	assert_eq(d.battery_frames, 1, "battery after byte-by-byte feed")


func test_garbage_prefix_resyncs() -> void:
	var d := HexRFrameDecoder.new()
	var b := PackedByteArray([0x00, 0xff, 0x12, 0x33, 0x08])
	b.append_array(_bundle())
	assert_eq(d.feed(b), 3, "all frames after garbage")
	assert_almost(d.battery, 0.75, 1e-6, "battery after garbage")


func test_bad_checksum_costs_one_byte() -> void:
	var d := HexRFrameDecoder.new()
	var bad := _battery_frame(0.25)
	bad[bad.size() - 1] ^= 0xFF
	var b := bad
	b.append_array(_battery_frame(0.5))
	d.feed(b)
	assert_eq(d.bad_frames, 1, "one bad frame")
	assert_almost(d.battery, 0.5, 1e-6, "good frame after a bad one")


func test_buffer_is_capped() -> void:
	var d := HexRFrameDecoder.new()
	var junk := PackedByteArray()
	junk.resize(HexRFrameDecoder.MAX_BUFFER * 3)
	junk.fill(0x40)  # a plausible length byte with no valid function after it
	d.feed(junk)
	d.feed(_battery_frame(0.9))
	assert_almost(d.battery, 0.9, 1e-6, "decodes after a flood")


func test_clutch_frame_is_positions() -> void:
	var d := HexRFrameDecoder.new()
	var p := PackedByteArray()
	for v in [9, 8, 7, 6, 5]:
		p.append_array(HexRTlv.i32(v))
	d.feed(HexRFrameDecoder.build_inbound(HexRTypes.InOp.CLUTCH_ACTIVATED, p))
	assert_eq(d.finger_position[0], 9, "clutch frame decodes as positions")


func test_short_frame_counts_as_bad() -> void:
	var d := HexRFrameDecoder.new()
	d.feed(HexRFrameDecoder.build_inbound(HexRTypes.InOp.PRESSURE, HexRTlv.f32(1.0)))
	assert_eq(d.bad_frames, 1, "short pressure frame")
	assert_eq(d.pressure_frames, 0, "not applied")


func test_pressure_units() -> void:
	assert_almost(HexRFrameDecoder.raw_to_kpa(45.2), 45.2, 1e-5, "gauge kPa passes through")
	assert_almost(HexRFrameDecoder.raw_to_kpa(145200.0), 45.2, 1e-5, "absolute Pa converted")
	assert_true(HexRFrameDecoder.looks_like_absolute_pa(PackedFloat32Array([0, 101325])), "absolute detected")
	assert_false(HexRFrameDecoder.looks_like_absolute_pa(PackedFloat32Array([0, 30])), "gauge detected")
