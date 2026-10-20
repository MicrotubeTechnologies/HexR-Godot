extends Control
## Bluetooth smoke test: connect each glove, press each channel, watch its readings.
## Runs as a flat panel app on a headset (no XR needed), and on the desktop.

const F := Haptics.Finger
const H := HaptGloveHandler.HandType

var _labels := {}
var _log: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme_ := Theme.new()
	theme_.default_font_size = 22
	theme = theme_
	var bg := ColorRect.new()
	bg.color = Color("#0c0d12")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	margin.add_child(root)

	var title := Label.new()
	title.text = "HexR Bluetooth smoke test · transport: %s · addon %s" % [HexR.transport.get_kind(), HexRManager.VERSION]
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 32)
	root.add_child(columns)
	for hand in [H.LEFT, H.RIGHT]:
		columns.add_child(_hand_column(hand))

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 220)
	_log.scroll_following = true
	root.add_child(_log)

	HexR.status_changed.connect(func(h: int, t: String) -> void: _say("%s: %s" % [HexRTypes.hand_name(h), t]))
	HexR.glove_connected.connect(func(h: int) -> void: _say("%s connected, MTU %d" % [HexRTypes.hand_name(h), HexR.glove(h).mtu]))
	HexR.glove_disconnected.connect(func(h: int) -> void: _say("%s disconnected" % HexRTypes.hand_name(h)))
	HexR.connect_attempt_ended.connect(func(h: int) -> void: _say("%s connect ended without a glove" % HexRTypes.hand_name(h)))
	HexR.device_found.connect(func(id: String, n: String, rssi: int) -> void:
		if n.begins_with("HaptGlove"):
			_say("found %s [%s] %d dBm" % [n, id, rssi]))
	for g in [HexR.left, HexR.right]:
		g.verbose = true
	_say("transport %s, available %s %s, permissions needed %s" % [HexR.transport.get_kind(),
			HexR.transport.is_available(), HexR.transport.get_unavailable_reason(), HexR.transport.needs_permissions()])
	# Unattended device test: adb shell run-as <package> touch files/smoke_autotest
	if FileAccess.file_exists("user://smoke_autotest"):
		_autotest()


## Connects whichever gloves answer, presses every channel once, reads telemetry, releases,
## disconnects. Everything goes to the log (adb logcat -s godot).
func _autotest() -> void:
	_say("AUTOTEST start")
	HexR.connect_hand(H.LEFT)
	HexR.connect_hand(H.RIGHT)
	var t := 0.0
	while t < 25.0 and not (HexR.is_hand_connected(H.LEFT) and HexR.is_hand_connected(H.RIGHT)):
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	for hand in [H.LEFT, H.RIGHT]:
		var g := HexR.glove(hand)
		if not g.ble_connected:
			_say("AUTOTEST %s not connected: %s" % [HexRTypes.hand_name(hand), g.status_text])
			continue
		await get_tree().create_timer(3.0).timeout
		_say("AUTOTEST %s MTU %d battery %.2f frames pos/pres/bat %d/%d/%d bad %d kPa %s pos %s" % [
				HexRTypes.hand_name(hand), g.mtu, g.get_battery_level(), g.decoder.position_frames,
				g.decoder.pressure_frames, g.decoder.battery_frames, g.decoder.bad_frames,
				str(g.get_air_pressure_kpa()), str(g.get_finger_positions())])
		for f in 6:
			g.bt_send(g.haptics.hexr_pressure(f, true, 0.6, 1.0))
			await get_tree().create_timer(0.8).timeout
			_say("AUTOTEST %s %s pressed: kPa %.1f" % [HexRTypes.hand_name(hand), HexRTypes.finger_name(f),
					g.get_air_pressure_kpa()[f]])
			g.bt_send(g.haptics.hexr_pressure(f, false, 0.0, 1.0))
			await get_tree().create_timer(0.4).timeout
		g.bt_send(g.haptics.hexr_vibration(F.INDEX, true, 18.0, 0.8))
		await get_tree().create_timer(1.0).timeout
		g.release_all_channels()
		await get_tree().create_timer(0.5).timeout
		_say("AUTOTEST %s released: kPa %s" % [HexRTypes.hand_name(hand), str(g.get_air_pressure_kpa())])
	for hand in [H.LEFT, H.RIGHT]:
		HexR.disconnect_hand(hand)
	_say("AUTOTEST done")


func _hand_column(hand: int) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var head := Label.new()
	head.text = HexRTypes.hand_name(hand) + " glove"
	head.add_theme_font_size_override("font_size", 26)
	col.add_child(head)

	var connect_button := Button.new()
	connect_button.text = "Connect / Disconnect"
	connect_button.pressed.connect(func() -> void: HexR.toggle_hand(hand))
	col.add_child(connect_button)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)
	var readings := Label.new()
	col.add_child(readings)
	_labels[hand] = [status, readings]

	var grid := GridContainer.new()
	grid.columns = 3
	col.add_child(grid)
	for f in 6:
		var b := Button.new()
		b.text = "Press " + HexRTypes.finger_name(f)
		b.pressed.connect(func() -> void: _press(hand, f))
		grid.add_child(b)
	for spec in [["Vibrate index 18 Hz", 0], ["Pulse palm ×3", 1], ["Release all", 2], ["Pump on/off", 3],
			["Ramp middle 1 Hz", 4], ["Forget glove", 5]]:
		var b := Button.new()
		b.text = spec[0]
		var which: int = spec[1]
		b.pressed.connect(func() -> void: _action(hand, which))
		grid.add_child(b)
	return col


func _press(hand: int, finger: int) -> void:
	var g := HexR.glove(hand)
	g.bt_send(g.haptics.hexr_pressure(finger, true, 0.8, 1.0))
	_say("%s: press %s" % [HexRTypes.hand_name(hand), HexRTypes.finger_name(finger)])
	await get_tree().create_timer(1.0).timeout
	g.bt_send(g.haptics.hexr_pressure(finger, false, 0.0, 1.0))


func _action(hand: int, which: int) -> void:
	var g := HexR.glove(hand)
	match which:
		0:
			g.bt_send(g.haptics.hexr_vibration(F.INDEX, true, 18.0, 0.8))
			await get_tree().create_timer(1.5).timeout
			g.bt_send(g.haptics.hexr_vibration(F.INDEX, false, 18.0, 0.8))
		1:
			g.bt_send(g.haptics.hexr_pulse(F.PALM, true, 3.0, 0.7, 3))
		2:
			g.release_all_channels()
		3:
			g.air_pressure_source_control()
		4:
			g.bt_send(g.haptics.hexr_vibration_ramped(F.MIDDLE, true, 1.0, 0.8, 0.5, 0.6, 0.0))
			await get_tree().create_timer(3.0).timeout
			g.bt_send(g.haptics.hexr_vibration_ramped(F.MIDDLE, false, 1.0, 0.8, 0.5, 0.6, 0.0))
		5:
			g.forget_device()
			_say("%s: forgot the remembered glove" % HexRTypes.hand_name(hand))


func _process(_delta: float) -> void:
	for hand in [H.LEFT, H.RIGHT]:
		var g := HexR.glove(hand)
		var labels: Array = _labels[hand]
		labels[0].text = g.status_text if not g.status_text.is_empty() else "Not connected"
		if g.ble_connected:
			var kpa := g.get_air_pressure_kpa()
			var parts := PackedStringArray()
			for v in kpa:
				parts.append("%.1f" % v)
			labels[1].text = "MTU %d · battery %d%% · frames %d/%d/%d bad %d\nkPa %s\npositions %s" % [
				g.mtu, roundi(g.get_battery_level() * 100.0), g.decoder.position_frames, g.decoder.pressure_frames,
				g.decoder.battery_frames, g.decoder.bad_frames, " ".join(parts), str(g.get_finger_positions())]
		else:
			labels[1].text = ""


func _say(text: String) -> void:
	print("[smoke] " + text)
	if _log:
		_log.append_text(Time.get_time_string_from_system() + "  " + text + "\n")
