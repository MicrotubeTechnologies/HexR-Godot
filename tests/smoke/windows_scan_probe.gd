extends SceneTree
## Manual check on a Windows PC with Bluetooth: scan for 5 s and list what the extension sees.
##   godot --headless --path . -s res://tests/smoke/windows_scan_probe.gd
func _initialize() -> void:
	var ext: Object = ClassDB.instantiate("HexRBleWinRT")
	print("available: %s %s" % [ext.is_available(), ext.get_last_error()])
	ext.start_scan(5000)
	var seen := {}
	var end := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < end:
		for e: Dictionary in ext.poll_events():
			if e["type"] == "device_found" and not seen.has(e["id"]):
				seen[e["id"]] = true
				print("found %s  %s  %d dBm" % [e["id"], e["name"], e["rssi"]])
			elif e["type"] == "scan_finished":
				print("scan finished: '%s'" % e["error"])
		OS.delay_msec(50)
	ext.shutdown()
	print("devices seen: %d" % seen.size())
	quit()
