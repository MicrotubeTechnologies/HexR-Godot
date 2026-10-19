extends HexRTest
## Cutting batched frames into writes that fit one packet. The same fixture is checked by the
## Android (Java) and Windows (C++) chunkers.


func test_shared_fixture() -> void:
	var data: Dictionary = load_json("res://tests/fixtures/frames_split.json")
	for c in data["cases"]:
		var chunks := HexRFrames.chunk_for_mtu(String(c["hex"]).hex_decode(), int(c["max_payload"]))
		var got: Array = []
		for ch in chunks:
			got.append(ch.hex_encode())
		assert_eq(got, c["chunks"], String(c["name"]))


func test_never_splits_a_frame() -> void:
	var h := HexRHaptics.new()
	var rel := h.build_release()
	for chunk in HexRFrames.chunk_for_mtu(rel, 20):
		assert_eq(chunk.size(), 18, "one release frame per write at MTU 23")
	var total := 0
	for chunk in HexRFrames.chunk_for_mtu(rel, 244):
		total += chunk.size()
		assert_true(chunk.size() <= 244, "fits MTU 247")
	assert_eq(total, 216, "nothing lost")


func test_split_stops_at_bad_length() -> void:
	var h := HexRHaptics.new()
	var data := h.hexr_pressure(1, true, 0.5, 0.5)
	data.append_array(PackedByteArray([0x40, 0x04]))
	assert_eq(HexRFrames.split_frames(data).size(), 1, "stops at impossible length")
