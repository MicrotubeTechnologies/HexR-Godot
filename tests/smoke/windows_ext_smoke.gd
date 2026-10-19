extends SceneTree
## CI check for the Windows Bluetooth extension. CI runners have no Bluetooth adapter, so this
## checks that the class loads, reports "unavailable" without crashing, cuts writes exactly like
## the GDScript and Java chunkers, and shuts down cleanly.
##
## Run on Linux or macOS it checks the stub instead: that it loads and has no Bluetooth.
##
##   godot --headless --path . -s res://tests/smoke/windows_ext_smoke.gd


func _initialize() -> void:
	var failures := 0
	if not ClassDB.class_exists("HexRBleWinRT"):
		print("FAIL: HexRBleWinRT is not registered")
		quit(1)
		return

	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/frames_split.json"))
	for c in data["cases"]:
		var got: Array = []
		for chunk in ClassDB.class_call_static("HexRBleWinRT", "chunk_for_mtu",
				String(c["hex"]).hex_decode(), int(c["max_payload"])):
			got.append((chunk as PackedByteArray).hex_encode())
		if got != c["chunks"]:
			failures += 1
			print("FAIL chunk_for_mtu %s: %s != %s" % [c["name"], got, c["chunks"]])

	var ext: Object = ClassDB.instantiate("HexRBleWinRT")
	print("is_available: %s (%s)" % [ext.is_available(), ext.get_last_error()])
	if OS.get_name() != "Windows":
		if ext.is_available():
			failures += 1
			print("FAIL: the stub reported Bluetooth as available")
	else:
		ext.start_scan(1500)
		var finished := false
		var deadline := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and not finished:
			for e: Dictionary in ext.poll_events():
				print("event: ", e)
				if e["type"] == "scan_finished":
					finished = true
			OS.delay_msec(50)
		if not finished:
			failures += 1
			print("FAIL: the scan never reported scan_finished")
	if ext.write("00:11:22:33:44:55", PackedByteArray([6, 2, 1, 1, 1, 80]), false):
		failures += 1
		print("FAIL: write to an unconnected glove reported success")
	ext.shutdown()
	print("%s: %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(failures)
