@tool
extends EditorDock
## The HexR Tools dock (port of the Unity package's HexR Tools window), with its three tabs:
## HexR Haptics Tester, HexR Setup and Project Setup.
##
## The tester drives real gloves from the editor on Windows (no Play needed), or the gloves of a
## game running here or on a headset, through the debugger.

const Validator := preload("res://addons/hexr/editor/hexr_validator.gd")
const Setup := preload("res://addons/hexr/editor/hexr_project_setup.gd")
const FINGERS: Array[String] = ["Thumb", "Index", "Middle", "Ring", "Pinky", "Palm"]
const FINGER_ENUM: Array[String] = ["THUMB", "INDEX", "MIDDLE", "RING", "PINKY", "PALM"]
const DOCS_URL := "https://microtube.tech/hexr-guide-godot.html"
const API_URL := "https://github.com/MicrotubeTechnologies/HexR-Godot/blob/main/docs/API.md"
const TUTORIAL_URL := "https://github.com/MicrotubeTechnologies/HexR-Developer-Tutorial-Godot"

# The Unity HexR Tools window's palette.
const ORANGE := Color("#ff6a2b")
const ORANGE_DARK := Color("#d64f1a")
const ORANGE_LIGHT := Color("#ff9a5c")
const GREEN := Color("#5bce6b")
const RED := Color("#d93a24")
const TRACK := Color("#232323")
const PREVIEW_BG := Color("#101010")
const PREVIEW_TEXT := Color("#7fe0a0")
const DIM := Color("#8f8f8f")

var debugger: EditorDebuggerPlugin
var plugin: EditorPlugin

var _scale := 1.0
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
# tester
var _hub: HexRManager
var _target: OptionButton
var _preview_only: CheckBox
var _cards: Array[Dictionary] = [{}, {}]
var _hand := HaptGloveHandler.HandType.RIGHT
var _hand_buttons: Array[Button] = []
var _channel_buttons: Array[Button] = []
var _vibration := false
var _mode_buttons: Array[Button] = []
var _intensity: HSlider
var _speed: HSlider
var _frequency: HSlider
var _speed_row: Control
var _frequency_row: Control
var _bypass: CheckBox
var _trigger: Button
var _triggered := false
var _preview: Label
var _bars: Array[ProgressBar] = []
var _game_status: Array = []
var _game_kind := ""
# setup
var _summary: Label
var _checks: VBoxContainer
var _fix_all: Button
# project setup
var _installer: Node
var _setup_rows: VBoxContainer
var _quest: CheckBox
var _pico: CheckBox
var _progress: Label
var _update_url := ""


func _init() -> void:
	title = "HexR Tools"
	default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	name = "HexR Tools"


func _ready() -> void:
	_scale = EditorInterface.get_editor_scale()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", roundi(6 * _scale))
	add_child(col)
	var bar := HBoxContainer.new()
	col.add_child(bar)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stack)
	for t in [["● HexR Haptics Tester", _tester_page()], ["● HexR Setup", _setup_page()], ["● Project Setup", _project_page()]]:
		var b := Button.new()
		b.text = t[0]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", roundi(13 * _scale))
		var i := _tab_buttons.size()
		b.pressed.connect(func() -> void: show_tab(i))
		bar.add_child(b)
		_tab_buttons.append(b)
		var page: Control = t[1]
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(page)
		_pages.append(page)
	_installer = Setup.new()
	_installer.progress.connect(func(text: String) -> void: _progress.text = text)
	add_child(_installer)
	if debugger:
		debugger.status_received.connect(func(kind: String, hands: Array) -> void:
			_game_kind = kind
			_game_status = hands)
	show_tab(0)


func _exit_tree() -> void:
	if _hub:
		_hub.shutdown()
		_hub.free()
		_hub = null


## Shows one tab: 0 Haptics Tester, 1 HexR Setup, 2 Project Setup. HexR Setup re-checks when shown.
func show_tab(i: int) -> void:
	for t in _tab_buttons.size():
		_tab_buttons[t].button_pressed = t == i
		_tab_buttons[t].add_theme_color_override("font_color", ORANGE if t == i else DIM)
		for state in ["font_pressed_color", "font_hover_pressed_color"]:
			_tab_buttons[t].add_theme_color_override(state, ORANGE)
		_tab_buttons[t].add_theme_color_override("font_hover_color", ORANGE if t == i else Color.WHITE)
		_pages[t].visible = t == i
	if i == 1:
		refresh_checks()
	elif i == 2:
		refresh_project()


## Brings the dock forward on a given tab (the HexR menu's HexR Tools and Validate Scene Setup).
func reveal(tab := -1) -> void:
	make_visible()
	if tab >= 0:
		show_tab(tab)


# -- HexR Haptics Tester ----------------------------------------------------------------------

func _tester_page() -> Control:
	var col := _page()
	var row := HBoxContainer.new()
	row.add_child(_dim("Target"))
	_target = OptionButton.new()
	_target.add_item("This PC (editor)")
	_target.add_item("Running game")
	_target.tooltip_text = "Running game: a game run from this editor, here or on a headset (Remote Deploy)."
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_target)
	col.add_child(row)
	_preview_only = CheckBox.new()
	_preview_only.text = "Preview only (don't send)"
	_preview_only.tooltip_text = "Show the call without sending it, for working without a glove."
	_preview_only.toggled.connect(func(_on: bool) -> void: _update_preview())
	col.add_child(_preview_only)

	col.add_child(_header("CONNECTION"))
	for hand in [HaptGloveHandler.HandType.LEFT, HaptGloveHandler.HandType.RIGHT]:
		col.add_child(_connection_card(hand))

	col.add_child(_header("TARGET HAND & CHANNELS"))
	var hands := HBoxContainer.new()
	for hand in [HaptGloveHandler.HandType.LEFT, HaptGloveHandler.HandType.RIGHT]:
		var b := _toggle(HexRTypes.hand_name(hand), hand == _hand)
		b.pressed.connect(func() -> void:
			_hand = hand
			for i in 2:
				_style_toggle(_hand_buttons[i], i == hand)
			_update_preview())
		hands.add_child(b)
		_hand_buttons.append(b)
	col.add_child(hands)
	var grid := GridContainer.new()
	grid.columns = 3
	for f in 6:
		var b := _toggle(FINGERS[f], f == Haptics.Finger.INDEX)
		b.pressed.connect(func() -> void:
			_style_toggle(b, b.button_pressed)
			_update_preview())
		grid.add_child(b)
		_channel_buttons.append(b)
	col.add_child(grid)

	col.add_child(_header("HAPTIC PARAMETERS"))
	var modes := HBoxContainer.new()
	for m in [["Pressure", false], ["Vibration", true]]:
		var vib: bool = m[1]
		var b := _toggle(m[0], vib == _vibration)
		b.pressed.connect(func() -> void:
			_vibration = vib
			_style_toggle(_mode_buttons[0], not vib)
			_style_toggle(_mode_buttons[1], vib)
			_speed_row.visible = not vib
			_frequency_row.visible = vib
			_update_preview())
		modes.add_child(b)
		_mode_buttons.append(b)
	col.add_child(modes)
	_intensity = _slider(col, "Intensity", 0.1, 1.0, 0.6, 0.05)
	_speed = _slider(col, "Speed", 0.1, 1.0, 0.5, 0.05)
	_speed_row = _speed.get_parent()
	_frequency = _slider(col, "Frequency (Hz)", 0.1, 40.0, 12.0, 0.1)
	_frequency_row = _frequency.get_parent()
	_frequency_row.visible = false
	_bypass = CheckBox.new()
	_bypass.text = "Bypass hand-near check"
	_bypass.button_pressed = true
	_bypass.toggled.connect(func(_on: bool) -> void: _update_preview())
	col.add_child(_bypass)

	var actions := HBoxContainer.new()
	_trigger = Button.new()
	_trigger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trigger.custom_minimum_size = Vector2(0, 34 * _scale)
	_trigger.pressed.connect(_on_trigger)
	actions.add_child(_trigger)
	var off := Button.new()
	off.text = "All OFF"
	off.custom_minimum_size = Vector2(80 * _scale, 34 * _scale)
	off.pressed.connect(_all_off)
	actions.add_child(off)
	col.add_child(actions)
	_style_trigger()

	col.add_child(_header("CALL PREVIEW"))
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _flat(PREVIEW_BG, 4, 8))
	_preview = Label.new()
	_preview.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_preview.add_theme_color_override("font_color", PREVIEW_TEXT)
	_preview.add_theme_font_override("font", EditorInterface.get_editor_theme().get_font("source", "EditorFonts"))
	box.add_child(_preview)
	col.add_child(box)

	col.add_child(_header("LIVE CHANNEL MONITOR"))
	for f in 7:
		var r := HBoxContainer.new()
		var l := _dim(FINGERS[f] if f < 6 else "Tank")
		l.custom_minimum_size = Vector2(56 * _scale, 0)
		r.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 60.0
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(0, 10 * _scale)
		bar.add_theme_stylebox_override("background", _flat(TRACK, 3))
		bar.add_theme_stylebox_override("fill", _flat(ORANGE if f < 6 else ORANGE_LIGHT, 3))
		r.add_child(bar)
		col.add_child(r)
		_bars.append(bar)
	var note := _dim("Editor Bluetooth needs Windows and the HexRBleWinRT extension; without it the editor uses "
			+ "simulated gloves. To reach a game on a headset, run it from here (Remote Deploy) and pick Running game.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	_update_preview()
	return col.get_parent()


func _connection_card(hand: int) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _flat(Color(1, 1, 1, 0.04), 6, 8))
	var col := VBoxContainer.new()
	var head := HBoxContainer.new()
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", DIM)
	head.add_child(dot)
	var name_label := Label.new()
	name_label.text = HexRTypes.hand_name(hand) + " glove"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var button := Button.new()
	button.text = "Connect"
	button.pressed.connect(func() -> void: _toggle_glove(hand))
	head.add_child(button)
	col.add_child(head)
	var status := _dim("Not connected")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)
	var battery := ProgressBar.new()
	battery.max_value = 100.0
	battery.custom_minimum_size = Vector2(0, 14 * _scale)
	battery.add_theme_stylebox_override("background", _flat(TRACK, 3))
	battery.add_theme_stylebox_override("fill", _flat(GREEN, 3))
	col.add_child(battery)
	card.add_child(col)
	_cards[hand] = {"dot": dot, "button": button, "status": status, "battery": battery}
	return card


func _editor_hub() -> HexRManager:
	if _hub == null:
		_hub = HexRManager.new()
		_hub.drive_from_process = false
		_hub.setup(HexRBleTransport.create(), HexRDeviceStore.new())
		for g in [_hub.left_hand, _hub.right_hand]:
			g.verbose = true
	return _hub


func _game() -> bool:
	return _target.selected == 1


func _toggle_glove(hand: int) -> void:
	if _game():
		debugger.send("toggle", [hand])
	else:
		_editor_hub().toggle_hand(hand)


func _selected_fingers() -> Array[int]:
	var out: Array[int] = []
	for f in 6:
		if _channel_buttons[f].button_pressed:
			out.append(f)
	return out


## The latching Trigger IN / Release OUT button: the same call with state true, then false.
func _on_trigger() -> void:
	_triggered = not _triggered
	_style_trigger()
	_update_preview()
	if _preview_only.button_pressed:
		return
	var on := _triggered
	var value := _frequency.value if _vibration else _speed.value
	for f in _selected_fingers():
		if _game():
			debugger.send("custom", [_hand, f, _vibration, on, _intensity.value, value, _bypass.button_pressed])
		else:
			var g := _editor_hub().glove(_hand)
			if _vibration:
				g.bt_send(g.haptics.hexr_vibration(f, on, value, _intensity.value))
			else:
				g.bt_send(g.haptics.hexr_pressure(f, on, _intensity.value, value))


func _all_off() -> void:
	_triggered = false
	_style_trigger()
	_update_preview()
	if _preview_only.button_pressed:
		return
	for hand in 2:
		if _game():
			debugger.send("all_off", [hand])
		elif _hub:
			_hub.glove(hand).release_all_channels()


func _style_trigger() -> void:
	_trigger.text = "■ Release OUT (state = false)" if _triggered else "● Trigger IN (state = true)"
	_trigger.add_theme_stylebox_override("normal", _flat(ORANGE_DARK if _triggered else ORANGE, 4, 6))
	_trigger.add_theme_stylebox_override("hover", _flat(ORANGE_LIGHT, 4, 6))
	_trigger.add_theme_color_override("font_color", Color.WHITE)


## The exact call the trigger button makes next, as you would write it in a game script.
func _update_preview() -> void:
	if _preview == null:
		return
	var state := not _triggered
	var side := "LEFT" if _hand == HaptGloveHandler.HandType.LEFT else "RIGHT"
	var lines := PackedStringArray()
	for f in _selected_fingers():
		if _vibration:
			lines.append("HexR.controller(HaptGloveHandler.HandType.%s).custom_single_vibrations(Haptics.Finger.%s, %s, %s, %s, %s)"
					% [side, FINGER_ENUM[f], str(state), _n(_intensity.value), _n(_frequency.value), str(_bypass.button_pressed)])
		else:
			lines.append("HexR.controller(HaptGloveHandler.HandType.%s).custom_single_haptics(Haptics.Finger.%s, %s, %s, %s, %s)"
					% [side, FINGER_ENUM[f], str(state), _n(_intensity.value), _n(_speed.value), str(_bypass.button_pressed)])
	_preview.text = "\n".join(lines) if not lines.is_empty() else "# pick a channel"


static func _n(x: float) -> String:
	return String.num(snappedf(x, 0.01), 2)


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _pages.is_empty() or not _pages[0].visible:
		return
	if _hub:
		_hub.tick(Time.get_ticks_msec())
	var kpa := []
	for hand in 2:
		var card: Dictionary = _cards[hand]
		var connected := false
		var connecting := false
		var text := "Not connected"
		var battery := 0.0
		var pressures := []
		if _game():
			if _game_status.size() == 2:
				var s: Array = _game_status[hand]
				connected = s[0]
				connecting = s[1]
				text = "[game, %s] %s" % [_game_kind, s[2]]
				battery = s[3]
				pressures = s[5]
			else:
				text = "Run the game (F5, or Remote Deploy to a headset) to reach its gloves."
		elif _hub:
			var g := _hub.glove(hand)
			connected = g.ble_connected
			connecting = _hub.is_hand_connecting(hand)
			text = "[%s] %s" % [_hub.transport.get_kind(), g.status_text if not g.status_text.is_empty() else "Not connected"]
			battery = g.get_battery_level()
			pressures = Array(g.get_air_pressure_kpa())
		card["dot"].add_theme_color_override("font_color", GREEN if connected else DIM)
		card["button"].text = "Disconnect" if connected else ("Cancel" if connecting else "Connect")
		card["button"].add_theme_stylebox_override("normal", _flat(Color(1, 1, 1, 0.08) if connected else ORANGE_DARK, 4, 4))
		card["status"].text = text
		card["battery"].value = roundf(battery * 100.0) if connected else 0.0
		if hand == _hand:
			kpa = pressures
	for f in 7:
		_bars[f].value = float(kpa[f]) if f < kpa.size() else 0.0


# -- HexR Setup -------------------------------------------------------------------------------

func _setup_page() -> Control:
	var col := _page()
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_summary)
	var buttons := HBoxContainer.new()
	_fix_all = Button.new()
	_fix_all.text = "Fix all"
	_fix_all.pressed.connect(func() -> void:
		Validator.fix_all(EditorInterface.get_edited_scene_root(), plugin.get_undo_redo() if plugin else null)
		refresh_checks())
	buttons.add_child(_fix_all)
	var rescan := Button.new()
	rescan.text = "Re-scan"
	rescan.pressed.connect(refresh_checks)
	buttons.add_child(rescan)
	col.add_child(buttons)
	_checks = VBoxContainer.new()
	col.add_child(_checks)
	return col.get_parent()


## Runs every check on the project and the open scene, and lists them.
func refresh_checks() -> void:
	if _checks == null:
		return
	for c in _checks.get_children():
		c.queue_free()
	var root := EditorInterface.get_edited_scene_root()
	var project := Validator.project_checks()
	var scene := Validator.scene_checks(root, plugin.get_undo_redo() if plugin else null)
	var failing := 0
	for c in project + scene:
		if not c["ok"] and not c.get("warn", false):
			failing += 1
	_checks.add_child(_header("PROJECT"))
	for c in project:
		_checks.add_child(_check_row(c))
	_checks.add_child(_header("OPEN SCENE"))
	if root == null:
		_checks.add_child(_dim("No scene open."))
	for c in scene:
		_checks.add_child(_check_row(c))
	if failing == 0:
		_summary.text = "All checks pass — this scene is ready to build to the headset."
		_summary.add_theme_color_override("font_color", GREEN)
	else:
		_summary.text = "%d check(s) need attention. Fix all runs every fix listed below." % failing
		_summary.add_theme_color_override("font_color", ORANGE_LIGHT)
	_fix_all.add_theme_stylebox_override("normal", _flat(ORANGE_DARK if failing else Color(1, 1, 1, 0.08), 4, 4))


func _check_row(c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var mark := Label.new()
	var warn: bool = c.get("warn", false)
	mark.text = "✓" if c["ok"] else "!"
	mark.add_theme_color_override("font_color", GREEN if c["ok"] else (ORANGE if warn else RED))
	mark.custom_minimum_size = Vector2(16 * _scale, 0)
	row.add_child(mark)
	var text := Label.new()
	text.text = c["title"] + ("" if c["ok"] or String(c["detail"]).is_empty() else " — " + c["detail"])
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


# -- Project Setup ----------------------------------------------------------------------------

func _project_page() -> Control:
	var col := _page()
	col.add_child(_header("HEADSETS"))
	var heads := HBoxContainer.new()
	_quest = CheckBox.new()
	_quest.text = "Meta Quest"
	_quest.button_pressed = true
	heads.add_child(_quest)
	_pico = CheckBox.new()
	_pico.text = "PICO"
	_pico.button_pressed = true
	heads.add_child(_pico)
	col.add_child(heads)
	_setup_rows = VBoxContainer.new()
	col.add_child(_setup_rows)
	_progress = _dim("")
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_progress)
	col.add_child(_header("QUICK LINKS"))
	for l in [["Godot docs", DOCS_URL], ["API reference", API_URL], ["Tutorial project", TUTORIAL_URL],
			["Microtube", "https://microtube.tech"]]:
		var link := LinkButton.new()
		link.text = l[0]
		link.uri = l[1]
		col.add_child(link)
	return col.get_parent()


## Re-reads what is installed and set up, and lists it with what to do.
func refresh_project() -> void:
	if _setup_rows == null:
		return
	for c in _setup_rows.get_children():
		c.queue_free()
	_setup_rows.add_child(_header("REQUIRED"))
	_setup_rows.add_child(_status_row(Setup.is_installed(Setup.VENDORS), "OpenXR Vendors plugin %s" % Setup.VENDORS["version"],
			"Quest and PICO support.", "Install", func() -> void: _install(Setup.VENDORS)))
	_setup_rows.add_child(_status_row(Setup.xr_settings_applied(), "XR project settings",
			"OpenXR, hand tracking, XR shaders, mobile renderer, ETC2/ASTC.", "Apply", func() -> void:
				Setup.apply_xr_settings()
				_progress.text = "Applied the XR project settings."
				refresh_project()))
	var template := Setup.build_template_state()
	_setup_rows.add_child(_status_row(template == "ok", "Android build template",
			"Project > Install Android Build Template." if template == "missing"
			else ("Made by another Godot version: install it again from the Project menu." if template == "stale" else ""),
			"", Callable()))
	var p := Setup.presets()
	var have := PackedStringArray()
	for k in ["quest", "pico"]:
		if p[k] != "":
			have.append(p[k])
	var want_more: bool = (_quest.button_pressed and p["quest"] == "") or (_pico.button_pressed and p["pico"] == "")
	_setup_rows.add_child(_status_row(not want_more, "Export presets",
			("Have: " + ", ".join(have)) if not have.is_empty() else "None for a headset yet.",
			"Add & restart", _add_presets))
	_setup_rows.add_child(_header("OPTIONAL"))
	_setup_rows.add_child(_status_row(Setup.is_installed(Setup.XR_TOOLS), "Godot XR Tools %s" % Setup.XR_TOOLS["version"],
			"Start-up, pick-ups and locomotion; HexRInteractableHaptics binds to its pickables.", "Install",
			func() -> void: _install(Setup.XR_TOOLS)))
	_setup_rows.add_child(_header("SCENES (Godot's Build Settings)"))
	var scenes := PackedStringArray(ProjectSettings.get_setting("hexr/scenes", PackedStringArray()))
	_setup_rows.add_child(_note("The HexR menu's SCENES, HexR Remote and SceneLoader list these, in order."
			if not scenes.is_empty() else "None listed. The HexR menu and HexR Remote offer scene switching from this list."))
	for s in scenes:
		var entry := _note("  " + s)
		entry.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_setup_rows.add_child(entry)
	var scene_buttons := HBoxContainer.new()
	var add_open := Button.new()
	add_open.text = "Add open scene"
	add_open.pressed.connect(func() -> void:
		var root := EditorInterface.get_edited_scene_root()
		if root and not root.scene_file_path.is_empty() and not scenes.has(root.scene_file_path):
			scenes.append(root.scene_file_path)
			ProjectSettings.set_setting("hexr/scenes", scenes)
			ProjectSettings.save()
		refresh_project())
	scene_buttons.add_child(add_open)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func() -> void:
		ProjectSettings.set_setting("hexr/scenes", PackedStringArray())
		ProjectSettings.save()
		refresh_project())
	scene_buttons.add_child(clear)
	_setup_rows.add_child(scene_buttons)
	_setup_rows.add_child(_header("HEXR VERSION"))
	var version := HBoxContainer.new()
	var installed := Label.new()
	installed.text = "Installed: %s" % Setup.installed_version()
	installed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.add_child(installed)
	var check := Button.new()
	check.text = "Check for updates"
	check.pressed.connect(_check_update)
	version.add_child(check)
	if _update_url != "":
		var upd := Button.new()
		upd.text = "Update"
		upd.add_theme_stylebox_override("normal", _flat(ORANGE_DARK, 4, 4))
		upd.pressed.connect(func() -> void: _installer.apply_update(_update_url, _done))
		version.add_child(upd)
	_setup_rows.add_child(version)


func _status_row(ok: bool, title_text: String, detail: String, action: String, on_press: Callable) -> Control:
	var row := HBoxContainer.new()
	var mark := Label.new()
	mark.text = "✓" if ok else "!"
	mark.add_theme_color_override("font_color", GREEN if ok else RED)
	mark.custom_minimum_size = Vector2(16 * _scale, 0)
	row.add_child(mark)
	var text := Label.new()
	text.text = title_text + ("" if detail.is_empty() else " — " + detail)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	if not ok and not action.is_empty() and on_press.is_valid():
		var b := Button.new()
		b.text = action
		b.add_theme_stylebox_override("normal", _flat(ORANGE_DARK, 4, 4))
		b.pressed.connect(on_press)
		row.add_child(b)
	return row


func _install(addon: Dictionary) -> void:
	_installer.install_addon(addon, _done)


func _add_presets() -> void:
	var added := Setup.add_presets(_quest.button_pressed, _pico.button_pressed)
	if added.is_empty():
		_progress.text = "The presets are already there."
		return
	_progress.text = "Added %s. Restarting the editor so it loads them…" % ", ".join(added)
	EditorInterface.restart_editor(true)


func _check_update() -> void:
	_progress.text = "Checking GitHub for HexR releases…"
	_installer.check_for_update(func(version: String, url: String, notes: String) -> void:
		_update_url = url
		if version == "":
			_progress.text = notes if url == "" and notes != "" else "HexR %s is the newest." % Setup.installed_version()
		else:
			_progress.text = "HexR %s is out. Update replaces addons/hexr and restarts the editor." % version
		refresh_project())


func _done(ok: bool, message: String) -> void:
	_progress.text = message
	_progress.add_theme_color_override("font_color", GREEN if ok else RED)
	refresh_project()


# -- building blocks --------------------------------------------------------------------------

func _page() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", roundi(4 * _scale))
	scroll.add_child(col)
	return col


## A section header: small, dim, uppercase, as in the Unity window.
func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", roundi(11 * _scale))
	l.add_theme_constant_override("line_spacing", roundi(8 * _scale))
	return l


## A dim line that wraps to the dock's width.
func _note(text: String) -> Label:
	var l := _dim(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", DIM)
	return l


func _toggle(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_toggle(b, on)
	return b


func _style_toggle(b: Button, on: bool) -> void:
	b.button_pressed = on
	b.add_theme_stylebox_override("normal", _flat(ORANGE if on else Color(1, 1, 1, 0.06), 4, 4))
	b.add_theme_stylebox_override("pressed", _flat(ORANGE, 4, 4))
	b.add_theme_color_override("font_color", Color.WHITE if on else DIM)


func _slider(parent: Control, text: String, lo: float, hi: float, value: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	var l := _dim(text)
	l.custom_minimum_size = Vector2(100 * _scale, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := Label.new()
	v.text = _n(value)
	v.custom_minimum_size = Vector2(40 * _scale, 0)
	s.value_changed.connect(func(x: float) -> void:
		v.text = _n(x)
		_update_preview())
	row.add_child(v)
	parent.add_child(row)
	return s


func _flat(color: Color, radius := 0, margin := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(roundi(radius * _scale))
	sb.set_content_margin_all(roundi(margin * _scale))
	return sb
