extends SceneTree
## Renders the floating menu to PNGs in a few states, to compare with the Unity panel's look.
## Needs a window (no --headless, which renders nothing):
##   godot --path . -s res://tests/visual/render_menu.gd -- --out=<folder>

var _out := "user://menu_renders"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	ProjectSettings.set_setting(SceneLoader.SETTING, PackedStringArray(
			["res://scenes/1_basic_tutorial.tscn", "res://scenes/2_hospital_tutorial.tscn", "res://scenes/3_water_effects.tscn"]))
	var sim := HexRSimulatedTransport.new()
	sim.add_glove(HexRSimulatedGlove.new("SIM:LEFT", HexRTypes.NAME_LEFT))
	sim.add_glove(HexRSimulatedGlove.new("SIM:RIGHT", HexRTypes.NAME_RIGHT))
	var hub := HexRManager.new()
	hub.drive_from_process = false
	hub.setup(sim, HexRDeviceStore.new(""))
	root.add_child(hub)
	hub.make_current()
	var hand := HexRTrackedHand.new()
	root.add_child(hand)
	var menu := HexRFloatingMenu.new()
	root.add_child(menu)
	await _frames(4)
	await _save(menu, "1_idle")

	var now := 1000
	hub.connect_hand(HaptGloveHandler.HandType.LEFT)
	hub.connect_hand(HaptGloveHandler.HandType.RIGHT)
	for i in 200:
		now += 20
		hub.tick(now)
	var lh := hub.left_hand
	lh.bt_send(lh.haptics.hexr_pressure(Haptics.Finger.INDEX, true, 0.5, 1.0))
	lh.bt_send(lh.haptics.hexr_vibration(Haptics.Finger.PALM, true, 30.0, 0.55))
	var rh := hub.right_hand
	rh.bt_send(rh.haptics.hexr_pulse(Haptics.Finger.THUMB, true, 10.0, 0.3, 5))
	rh.bt_send(rh.haptics.hexr_pressure(Haptics.Finger.MIDDLE, true, 0.8, 1.0))
	rh.bt_send(rh.haptics.hexr_pressure(Haptics.Finger.MIDDLE, false, 0.8, 1.0))
	await _frames(3)
	await _save(menu, "2_connected_haptics")

	var remote := HexRRemote.new()
	HexRRemote.instance = remote
	remote._viewers = 1
	menu.panel.press(menu.panel.buttons[0]["pill"])
	await _frames(3)
	await _save(menu, "3_watching_pressed")
	HexRRemote.instance = null
	remote.free()
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(menu: HexRFloatingMenu, file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(file + ".png")
	menu._viewport.get_texture().get_image().save_png(path)
	print("wrote ", path)
