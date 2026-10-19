@tool
extends VBoxContainer
## The HexR dock: a Haptics Tester for real gloves from the editor (Windows) or in a running game
## (any platform, through the debugger), and setup checks for the project and the open scene.
## Port of the Unity package's HexR Tools window.

const F_NAMES := ["Thumb", "Index", "Middle", "Ring", "Pinky", "Palm"]
const Validator := preload("res://addons/hexr/editor/hexr_validator.gd")

var debugger: EditorDebuggerPlugin
var _target: OptionButton
var _hub: HexRManager
var _hand_ui: Array = [{}, {}]
var _game_status: Array = []
var _game_kind := ""
var _checks: VBoxContainer
var _intensity: HSlider
var _frequency: HSlider


func _ready() -> void:
	name = "HexR"
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	tabs.add_child(_tester_tab())
	tabs.add_child(_setup_tab())
	tabs.set_tab_title(0, "Haptics Tester")
	tabs.set_tab_title(1, "Setup")
	if debugger:
		debugger.status_received.connect(func(kind: String, hands: Array) -> void:
			_game_kind = kind
			_game_status = hands)


func _exit_tree() -> void:
	if _hub:
		_hub.shutdown()
		_hub.free()
		_hub = null


# -- Haptics Tester -------------------------------------------------------------------------

func _tester_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Haptics Tester"
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	var row := HBoxContainer.new()
	row.add_child(_label("Target"))
	_target = OptionButton.new()
	_target.add_item("This PC (editor)")
	_target.add_item("Running game")
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_target)
	col.add_child(row)

	_intensity = _slider(col, "Intensity", 0.1, 1.0, 0.8, 0.05)
	_frequency = _slider(col, "Vibration Hz", 0.1, 40.0, 18.0, 0.1)

	for hand in [HexRTypes.Hand.LEFT, HexRTypes.Hand.RIGHT]:
		col.add_child(HSeparator.new())
		var head := HBoxContainer.new()
		var title := _label(HexRTypes.hand_name(hand) + " glove")
		title.add_theme_font_size_override("font_size", 16)
		head.add_child(title)
		var connect_button := Button.new()
		connect_button.text = "Connect"
		connect_button.pressed.connect(func() -> void: _toggle(hand))
		head.add_child(connect_button)
		col.add_child(head)
		var status := _label("")
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(status)
		var readings := _label("")
		readings.add_theme_font_size_override("font_size", 11)
		col.add_child(readings)
		var grid := GridContainer.new()
		grid.columns = 3
		for f in 6:
			var b := Button.new()
			b.text = F_NAMES[f]
			b.tooltip_text = "Press for one second"
			b.pressed.connect(func() -> void: _press(hand, f))
			grid.add_child(b)
		var vib := Button.new()
		vib.text = "Vibrate index"
		vib.pressed.connect(func() -> void: _vibrate(hand))
		grid.add_child(vib)
		var rel := Button.new()
		rel.text = "Release all"
		rel.pressed.connect(func() -> void: _release(hand))
		grid.add_child(rel)
		col.add_child(grid)
		_hand_ui[hand] = {"connect": connect_button, "status": status, "readings": readings}
	var note := _label("Editor Bluetooth needs Windows and the HexRBleWinRT extension. Without it the editor uses "
			+ "simulated gloves. A game running on a headset is reached through the debugger: pick \"Running game\".")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.6)
	col.add_child(note)
	return scroll


func _editor_hub() -> HexRManager:
	if _hub == null:
		_hub = HexRManager.new()
		_hub.drive_from_process = false
		_hub.setup(HexRBleTransport.create(), HexRDeviceStore.new())
		for g in [_hub.left, _hub.right]:
			g.verbose = true
	return _hub


func _game() -> bool:
	return _target.selected == 1


func _toggle(hand: int) -> void:
	if _game():
		debugger.send("toggle", [hand])
	else:
		_editor_hub().toggle_hand(hand)


func _press(hand: int, finger: int) -> void:
	if _game():
		debugger.send("press", [hand, finger, _intensity.value])
		await get_tree().create_timer(1.0).timeout
		debugger.send("release", [hand])
		return
	var g := _editor_hub().glove(hand)
	g.bt_send(g.haptics.hexr_pressure(finger, true, _intensity.value, 1.0))
	await get_tree().create_timer(1.0).timeout
	g.bt_send(g.haptics.hexr_pressure(finger, false, 0.0, 1.0))


func _vibrate(hand: int) -> void:
	if _game():
		debugger.send("vibrate", [hand, HexRTypes.Finger.INDEX, _frequency.value, _intensity.value])
		await get_tree().create_timer(1.5).timeout
		debugger.send("release", [hand])
		return
	var g := _editor_hub().glove(hand)
	g.bt_send(g.haptics.hexr_vibration(HexRTypes.Finger.INDEX, true, _frequency.value, _intensity.value))
	await get_tree().create_timer(1.5).timeout
	g.release_all_channels()


func _release(hand: int) -> void:
	if _game():
		debugger.send("release", [hand])
	else:
		_editor_hub().glove(hand).release_all_channels()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _hub:
		_hub.tick(Time.get_ticks_msec())
	for hand in 2:
		var ui: Dictionary = _hand_ui[hand]
		if ui.is_empty():
			continue
		if _game():
			if _game_status.size() == 2:
				var s: Array = _game_status[hand]
				ui["connect"].text = "Disconnect" if s[0] else ("Cancel" if s[1] else "Connect")
				ui["status"].text = "[game, %s] %s" % [_game_kind, s[2]]
				ui["readings"].text = _readings(s[0], s[3], s[4], s[5], s[6])
			else:
				ui["status"].text = "Run the game (F5 or a headset deploy) to reach its gloves."
				ui["readings"].text = ""
		else:
			if _hub == null:
				ui["status"].text = "Not connected"
				ui["readings"].text = ""
				continue
			var g := _hub.glove(hand)
			ui["connect"].text = "Disconnect" if g.ble_connected else ("Cancel" if _hub.is_hand_connecting(hand) else "Connect")
			ui["status"].text = "[%s] %s" % [_hub.transport.get_kind(), g.status_text if not g.status_text.is_empty() else "Not connected"]
			ui["readings"].text = _readings(g.ble_connected, g.get_battery_level(), g.mtu,
					Array(g.get_air_pressure_kpa()), g.decoder.bad_frames)


func _readings(connected: bool, battery: float, mtu: int, kpa: Array, bad: int) -> String:
	if not connected:
		return ""
	var parts := PackedStringArray()
	for v in kpa:
		parts.append("%.1f" % float(v))
	return "battery %d%% · MTU %d · bad frames %d\nkPa %s" % [roundi(battery * 100.0), mtu, bad, " ".join(parts)]


# -- Setup ----------------------------------------------------------------------------------

func _setup_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Setup"
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var refresh := Button.new()
	refresh.text = "Check project and open scene"
	refresh.pressed.connect(refresh_checks)
	col.add_child(refresh)
	_checks = VBoxContainer.new()
	col.add_child(_checks)
	return scroll


func refresh_checks() -> void:
	for c in _checks.get_children():
		c.queue_free()
	_checks.add_child(_label("PROJECT"))
	for c in Validator.project_checks():
		_checks.add_child(_check_row(c))
	_checks.add_child(_label("OPEN SCENE"))
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_checks.add_child(_label("No scene open."))
	for c in Validator.scene_checks(root):
		_checks.add_child(_check_row(c))


func _check_row(c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var mark := _label("✔" if c["ok"] else "✖")
	mark.modulate = Color("#52d6a0") if c["ok"] else Color("#ff7a6b")
	row.add_child(mark)
	var text := _label(c["title"] + ("" if c["ok"] or String(c["detail"]).is_empty() else " — " + c["detail"]))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var fix: Callable = c["fix"]
	if not c["ok"] and fix.is_valid():
		var b := Button.new()
		b.text = "Fix"
		b.pressed.connect(func() -> void:
			fix.call()
			refresh_checks())
		row.add_child(b)
	return row


# -- helpers --------------------------------------------------------------------------------

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _slider(parent: Control, text: String, lo: float, hi: float, value: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	var l := _label(text)
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := _label(str(value))
	v.custom_minimum_size = Vector2(40, 0)
	s.value_changed.connect(func(x: float) -> void: v.text = str(snappedf(x, step)))
	row.add_child(v)
	parent.add_child(row)
	return s
