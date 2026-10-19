class_name HexRTest
extends Node
## Base class for HexR tests. Put test files in tests/unit or tests/integration, name them
## test_*.gd, and name test methods test_*. Methods may await.

var _failures: PackedStringArray = []
## Set to true in a test that expects engine errors (push_error) and checks them itself.
var allow_errors := false


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	if condition:
		fail(message)


func assert_eq(got: Variant, want: Variant, message: String = "") -> void:
	if typeof(got) != typeof(want) and not (_is_number(got) and _is_number(want)):
		fail("%s: type %s != %s (got %s, want %s)" % [message, type_string(typeof(got)),
				type_string(typeof(want)), str(got), str(want)])
	elif got != want:
		fail("%s: got %s, want %s" % [message, str(got), str(want)])


func assert_almost(got: float, want: float, epsilon: float = 1e-5, message: String = "") -> void:
	if absf(got - want) > epsilon:
		fail("%s: got %f, want %f (±%f)" % [message, got, want, epsilon])


func assert_bytes(got: PackedByteArray, want_hex: String, message: String = "") -> void:
	var want := HexRFrames.from_hex(want_hex)
	if got != want:
		fail("%s:\n    got  %s\n    want %s" % [message, HexRFrames.to_hex(got), HexRFrames.to_hex(want)])


func wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func wait_ms(ms: int) -> void:
	await get_tree().create_timer(ms / 1000.0).timeout


func load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		fail("could not read " + path)
		return null
	return JSON.parse_string(text)


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
