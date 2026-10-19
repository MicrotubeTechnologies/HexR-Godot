class_name HexRMenuPanel
extends PanelContainer
## The HexR menu's 2D content: glove connection, battery and pump, a live haptics readout, and a
## few tools. Built in code, because everything on it is runtime state. [HexRFloatingMenu] shows
## it in the room; it also works as an ordinary Control in a flat UI.

signal recenter_requested
signal touch_points_toggled(visible: bool)
signal scene_requested(path: String)

const PANEL := Color("#090a0e")
const LINE := Color(1, 1, 1, 0.10)
const MUTED := Color(1, 1, 1, 0.66)
const FAINT := Color(1, 1, 1, 0.44)
const ACCENT := Color("#f2661a")
const ACCENT_HOVER := Color("#ff8a3d")
const OK := Color("#52d6a0")
const WARN := Color("#ff7a6b")
const FONT_DIR := "res://addons/hexr/ui/fonts/"

## Show what each channel of each glove is doing.
var show_haptics_readout := true
## Scene paths offered as buttons. Empty hides the section.
var scenes: PackedStringArray = []

var _status: Array[Label] = []
var _battery: Array[Label] = []
var _connect: Array[Button] = []
var _cells: Array = [[], []]
var _pressure: Array[Label] = []
var _touch_points_visible := false
var _refresh_at := 0


func _ready() -> void:
	custom_minimum_size = Vector2(640, 0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PANEL, 0.94)
	box.set_corner_radius_all(22)
	box.border_color = LINE
	box.set_border_width_all(2)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 22
	box.content_margin_bottom = 24
	add_theme_stylebox_override("panel", box)
	theme = _make_theme()

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	add_child(col)

	var head := HBoxContainer.new()
	var word := Label.new()
	word.text = "HEXR"
	word.add_theme_font_override("font", _font("Archivo-ExtraBold"))
	word.add_theme_font_size_override("font_size", 40)
	head.add_child(word)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var ver := Label.new()
	ver.text = "Godot addon %s" % HexRManager.VERSION
	ver.add_theme_color_override("font_color", FAINT)
	head.add_child(ver)
	col.add_child(head)

	var gloves := HBoxContainer.new()
	gloves.add_theme_constant_override("separation", 14)
	for hand in [HexRTypes.Hand.LEFT, HexRTypes.Hand.RIGHT]:
		gloves.add_child(_glove_card(hand))
	col.add_child(gloves)

	if show_haptics_readout:
		col.add_child(_section("HAPTICS"))
		col.add_child(_readout())

	col.add_child(_section("TOOLS"))
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.add_child(_ghost_button("Release all", func() -> void:
		var hub := HexRManager.get_instance()
		if hub:
			hub.left.release_all_channels()
			hub.right.release_all_channels()))
	tools.add_child(_ghost_button("Show touch points", func() -> void:
		_touch_points_visible = not _touch_points_visible
		touch_points_toggled.emit(_touch_points_visible)))
	tools.add_child(_ghost_button("Recenter", func() -> void: recenter_requested.emit()))
	col.add_child(tools)

	if not scenes.is_empty():
		col.add_child(_section("SCENES"))
		var grid := GridContainer.new()
		grid.columns = 2
		for path in scenes:
			var p := path
			grid.add_child(_ghost_button(p.get_file().get_basename().capitalize(), func() -> void: scene_requested.emit(p)))
		col.add_child(grid)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _refresh_at:
		return
	_refresh_at = now + 200
	var hub := HexRManager.get_instance()
	if hub == null or hub.left == null:
		return
	for hand in 2:
		var g := hub.glove(hand)
		var side := HexRTypes.hand_name(hand)
		if g.ble_connected:
			_status[hand].text = g.status_text if not g.status_text.is_empty() else side + " connected"
			_status[hand].add_theme_color_override("font_color", OK)
			_connect[hand].text = "Disconnect"
			var pct := roundi(g.get_battery_level() * 100.0)
			_battery[hand].text = "Battery %d%%" % pct if pct > 0 else "Battery —"
		else:
			_status[hand].text = g.status_text if not g.status_text.is_empty() else side + " not connected"
			_status[hand].add_theme_color_override("font_color", MUTED if hub.is_hand_connecting(hand) or g.status_text.is_empty() else WARN)
			_connect[hand].text = "Cancel" if hub.is_hand_connecting(hand) else "Connect"
			_battery[hand].text = ""
		if show_haptics_readout:
			for f in 6:
				var s := g.haptics.get_channel_state(f)
				var cell: Label = _cells[hand][f]
				match s.mode:
					HexRTypes.HapticMode.PRESSURE:
						cell.text = "%d" % roundi(s.intensity * 100.0)
					HexRTypes.HapticMode.VIBRATION:
						cell.text = "%g Hz" % snappedf(s.frequency, 0.1)
					HexRTypes.HapticMode.PULSE:
						cell.text = "pulse"
					_:
						cell.text = "·"
				cell.add_theme_color_override("font_color", ACCENT if s.is_on() else FAINT)
			if g.ble_connected:
				var kpa := g.get_air_pressure_kpa()
				_pressure[hand].text = "kPa  " + "  ".join(Array(kpa).slice(0, 6).map(func(v: float) -> String: return "%d" % roundi(v))) \
						+ "   source %d" % roundi(kpa[6])
			else:
				_pressure[hand].text = ""


func _glove_card(hand: int) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = HexRTypes.hand_name(hand).to_upper() + " GLOVE"
	title.add_theme_font_override("font", _font("Archivo-Bold"))
	title.add_theme_color_override("font_color", MUTED)
	col.add_child(title)
	var b := Button.new()
	b.text = "Connect"
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_stylebox_override("normal", _filled(ACCENT))
	b.add_theme_stylebox_override("hover", _filled(ACCENT_HOVER))
	b.add_theme_stylebox_override("pressed", _filled(Color("#c84a0c")))
	b.pressed.connect(func() -> void:
		var hub := HexRManager.get_instance()
		if hub:
			hub.toggle_hand(hand))
	col.add_child(b)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(0, 56)
	col.add_child(status)
	var battery := Label.new()
	battery.add_theme_color_override("font_color", FAINT)
	col.add_child(battery)
	card.add_child(col)
	_connect.append(b)
	_status.append(status)
	_battery.append(battery)
	return card


func _readout() -> Control:
	var col := VBoxContainer.new()
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_child(Label.new())
	for f in 6:
		var h := Label.new()
		h.text = HexRTypes.finger_name(f)
		h.add_theme_color_override("font_color", FAINT)
		h.add_theme_font_size_override("font_size", 18)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.custom_minimum_size = Vector2(76, 0)
		grid.add_child(h)
	for hand in 2:
		var side := Label.new()
		side.text = "L" if hand == HexRTypes.Hand.LEFT else "R"
		side.add_theme_font_override("font", _font("Archivo-Bold"))
		grid.add_child(side)
		for f in 6:
			var cell := Label.new()
			cell.text = "·"
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(cell)
			_cells[hand].append(cell)
	col.add_child(grid)
	for hand in 2:
		var p := Label.new()
		p.add_theme_font_size_override("font_size", 18)
		p.add_theme_color_override("font_color", FAINT)
		col.add_child(p)
		_pressure.append(p)
	return col


func _section(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font("Archivo-Bold"))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", FAINT)
	return l


func _ghost_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_stylebox_override("normal", _filled(Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("hover", _filled(Color(1, 1, 1, 0.12)))
	b.add_theme_stylebox_override("pressed", _filled(Color(ACCENT, 0.28)))
	b.pressed.connect(on_press)
	return b


func _filled(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font("Inter-Medium")
	t.default_font_size = 22
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_font("font", "Button", _font("Inter-SemiBold"))
	var focus := StyleBoxEmpty.new()
	t.set_stylebox("focus", "Button", focus)
	return t


static func _font(file: String) -> Font:
	var f := load(FONT_DIR + file + ".ttf") as Font
	return f if f else ThemeDB.fallback_font
