@tool
class_name HexRMenuPanel
extends Control
## The HexR menu's 2D content, laid out and styled as the Unity package's floating menu (its ARIS
## look): a header that is also the grab handle, then GLOVES, VIEW, HAPTICS, SCENES and DEMOS.
## Positions are Unity's, in its 360-pixel-wide panel, scaled to this panel's width.
##
## [HexRFloatingMenu] shows it in the room and gives every button in [member buttons] a press
## volume of its own; [method press] and [method release] are what those volumes call.

const UNITY_WIDTH := 360.0
# HexRFloatingMenu's layout, in Unity's panel pixels.
const MARGIN := 18.0
const HEADER_HEIGHT := 46.0
const SECTION_LABEL_HEIGHT := 24.0
const BUTTON_HEIGHT := 52.0
const GRID_BUTTON_HEIGHT := 42.0
const GRID_GAP := 12.0
const GAP := 16.0
const READOUT_ROW_HEIGHT := 22.0
const READOUT_ROW_GAP := 4.0
const READOUT_LABEL_WIDTH := 76.0
const EYEBROW_INDENT := 22.0
const PANEL_RADIUS := 22.0
const STROKE := 2.0
const CELL_RADIUS := 7.0
const READOUT_FLASH_MS := 200
const CHANNEL_NAMES: Array[String] = ["Thumb", "Index", "Middle", "Ring", "Pinky", "Palm"]

# HexRMenuLook's colours. The translucent whites are composited onto the panel colour in sRGB
# and kept opaque, as Unity does.
const PANEL := Color(0.035294, 0.039216, 0.054902, 0.94)
const LINE := Color("#222326")
const LINE2 := Color("#353639")
const TEXT := Color.WHITE
const MUTED := Color("#abacad")
const FAINT := Color("#757678")
const GHOST_FACE := Color("#18191c")
const GHOST_PRESSED := Color("#4a2411")
const CELL_FACE := Color("#15161a")
const ACCENT := Color("#f2661a")
const ACCENT_EDGE := Color(1.0, 0.615686, 0.270588, 0.6)
const ACCENT_DEEP := Color("#c84a0c")
const RIM := Color("#ff7a2e")
const OK := Color("#52d6a0")
const WARN := Color("#ff7a6b")

const FONT_DIR := "res://addons/hexr/ui/fonts/"
const _SceneLoader := preload("res://addons/hexr/core/scene_loader.gd")

## Show what each channel of each glove was last told to do.
var show_haptics_readout := true
## One button per scene in the project setting [code]hexr/scenes[/code], when it lists two or more.
var show_scene_switcher := true
## One button per "... Demo Components" node in the scene, one of them shown at a time.
var show_demo_groups := true
## Every pressable button: {"rect": Rect2 in panel pixels, "pill": the button}.
var buttons: Array[Dictionary] = []

var _s := 1.0  # panel pixels per Unity pixel
var _glove_labels: Array[Label] = []
var _glove_pills: Array[Pill] = []
var _shown_connected: Array[bool] = [false, false]
var _colliders_label: Label
var _hint: Label
var _shown_remote := -1
var _cells: Array[Panel] = []
var _values: Array[Label] = []
var _shown_count: Array[int] = []
var _shown_lit: Array[bool] = []
var _lit_until: Array[int] = []
var _last: Array[String] = []
var _readout_repaint := false
var _demo_groups: Array[Node] = []
var _demo_pills: Array[Pill] = []
var _attempt_hooked: HexRManager


## A pill button drawn in the Unity menu's style. It is pressed by a fingertip through the press
## volume [HexRFloatingMenu] puts over it, not by the mouse.
class Pill:
	extends Panel

	var label: Label
	var action: Callable
	var active := false:
		set(v):
			active = v
			_restyle()
	var finger_down := false:
		set(v):
			finger_down = v
			_restyle()
	## Not pressable: the scene already open, the demo already shown.
	var disabled := false

	func _restyle() -> void:
		var face := HexRMenuPanel.GHOST_FACE
		var ring := HexRMenuPanel.LINE2
		if active:
			face = HexRMenuPanel.ACCENT_DEEP if finger_down else HexRMenuPanel.ACCENT
			ring = HexRMenuPanel.RIM if finger_down else HexRMenuPanel.ACCENT_EDGE
		elif finger_down:
			face = HexRMenuPanel.GHOST_PRESSED
			ring = HexRMenuPanel.RIM
		add_theme_stylebox_override("panel", HexRMenuPanel.rounded(face, size.y * 0.5, ring, stroke))

	var stroke := 2


## Lays the panel out. Call again to rebuild it (the scene list and the demos are the scene's).
func build(width_px: int) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	buttons.clear()
	_glove_labels.clear()
	_glove_pills.clear()
	_demo_pills.clear()
	_cells.clear()
	_values.clear()
	_s = width_px / UNITY_WIDTH
	var y := 0.0
	y = _build_header(y)
	y = _build_gloves(y)
	y = _build_view(y)
	y = _build_haptics(y)
	y = _build_scenes(y)
	y = _build_demos(y)
	var height := (y + MARGIN) * _s
	size = Vector2(width_px, ceilf(height))
	custom_minimum_size = size
	# The glass and its hairline edge, under everything.
	var glass := Panel.new()
	glass.name = "Glass"
	glass.add_theme_stylebox_override("panel", rounded(PANEL, PANEL_RADIUS * _s, LINE2, _stroke()))
	glass.size = size
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glass)
	move_child(glass, 0)
	_shown_remote = -1
	_shown_connected = [false, false]
	_readout_repaint = true


## Every frame while the app runs: glove status, the haptics readout, the header hint.
func refresh() -> void:
	var hub := HexRManager.get_instance()
	if hub != null and _attempt_hooked != hub:
		_attempt_hooked = hub
		hub.connect_attempt_ended.connect(_on_connect_attempt_ended)
	_update_gloves(hub)
	_update_colliders_label()
	_update_readout(hub)
	_update_remote_hint()


## A fingertip entered [param pill]'s press volume.
func press(pill: Pill) -> void:
	pill.finger_down = true
	if not pill.disabled and pill.action.is_valid():
		pill.action.call()


## The fingertip left [param pill]'s press volume.
func release(pill: Pill) -> void:
	pill.finger_down = false


# -- sections, as Unity's HexRFloatingMenu.Build ---------------------------------------------

func _build_header(y: float) -> float:
	_box(Rect2(MARGIN, y + HEADER_HEIGHT * 0.5 - 1.5, 16, 3), ACCENT)
	var title := _label(Rect2(MARGIN + 26, y, UNITY_WIDTH - MARGIN * 2 - 26, HEADER_HEIGHT), "HEXR", 17,
			_tracked("Archivo-ExtraBold", 0.10, 17), TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	# "HEXR  MENU": the wordmark split, heavy then muted.
	var menu_word := _label(Rect2(0, 0, 0, 0), "MENU", 17, _tracked("Archivo-ExtraBold", 0.10, 17), MUTED,
			HORIZONTAL_ALIGNMENT_LEFT)
	var font: Font = title.get_theme_font("font")
	var word_w := font.get_string_size("HEXR ", HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
	menu_word.position = title.position + Vector2(word_w, 0)
	menu_word.size = Vector2(title.size.x - word_w, title.size.y)
	_hint = _label(Rect2(MARGIN, y, UNITY_WIDTH - MARGIN * 2, HEADER_HEIGHT), "grab to move", 11,
			_font("Inter-Medium"), FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	_box(Rect2(MARGIN, y + HEADER_HEIGHT - 1, UNITY_WIDTH - MARGIN * 2, 1.5), LINE)
	return y + HEADER_HEIGHT + GAP


func _build_gloves(y: float) -> float:
	y = _section_label("GLOVES", y)
	for hand in [HaptGloveHandler.HandType.LEFT, HaptGloveHandler.HandType.RIGHT]:
		var side := HexRTypes.hand_name(hand)
		var pill := _pill(Rect2(MARGIN, y, UNITY_WIDTH - MARGIN * 2, BUTTON_HEIGHT), "Connect %s Glove" % side, 15,
				false, _connect.bind(hand))
		_glove_pills.append(pill)
		_glove_labels.append(pill.label)
		y += BUTTON_HEIGHT + GAP
	return y


func _build_view(y: float) -> float:
	y = _section_label("VIEW", y)
	var pill := _pill(Rect2(MARGIN, y, UNITY_WIDTH - MARGIN * 2, BUTTON_HEIGHT), "Show Colliders", 15, false,
			_toggle_colliders)
	_colliders_label = pill.label
	_update_colliders_label()
	return y + BUTTON_HEIGHT + GAP


func _build_haptics(y: float) -> float:
	if not show_haptics_readout:
		return y
	y = _section_label("HAPTICS", y)
	var value_w := (UNITY_WIDTH - MARGIN * 2 - READOUT_LABEL_WIDTH - GRID_GAP) * 0.5
	var left_x := MARGIN + READOUT_LABEL_WIDTH
	var right_x := left_x + value_w + GRID_GAP
	var head_font := _tracked("Archivo-Bold", 0.16, 11)
	_label(Rect2(left_x, y, value_w, READOUT_ROW_HEIGHT), "LEFT", 11, head_font, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(Rect2(right_x, y, value_w, READOUT_ROW_HEIGHT), "RIGHT", 11, head_font, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	y += READOUT_ROW_HEIGHT
	var cells: Array = [[], []]
	var values: Array = [[], []]
	for c in 6:
		_label(Rect2(MARGIN, y, READOUT_LABEL_WIDTH, READOUT_ROW_HEIGHT), CHANNEL_NAMES[c], 13,
				_font("Inter-Medium"), MUTED, HORIZONTAL_ALIGNMENT_LEFT)
		for hand in 2:
			var cell := Panel.new()
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_place(cell, Rect2(left_x if hand == 0 else right_x, y, value_w, READOUT_ROW_HEIGHT))
			cell.add_theme_stylebox_override("panel", rounded(CELL_FACE, CELL_RADIUS * _s))
			add_child(cell)
			var value := _label(Rect2(6, 0, value_w - 12, READOUT_ROW_HEIGHT), "-", 13, _font("Inter-Medium"), MUTED,
					HORIZONTAL_ALIGNMENT_CENTER, cell)
			cells[hand].append(cell)
			values[hand].append(value)
		y += READOUT_ROW_HEIGHT + READOUT_ROW_GAP
	# Left hand's six channels, then the right's, as Unity keeps them.
	for hand in 2:
		_cells.append_array(cells[hand])
		_values.append_array(values[hand])
	if _shown_count.is_empty():
		_shown_count.resize(12)
		_shown_count.fill(0)
		_lit_until.resize(12)
		_lit_until.fill(0)
		_last.resize(12)
		_last.fill("")
	_shown_lit.resize(12)
	_shown_lit.fill(false)
	return y + GAP - READOUT_ROW_GAP


func _build_scenes(y: float) -> float:
	if not show_scene_switcher:
		return y
	var list := _SceneLoader.scenes()
	if list.size() < 2:
		# Nowhere to go, and a section saying so is worse than no section.
		return y
	y = _section_label("SCENES", y)
	var root := _scene_root()
	var current := list.find(root.scene_file_path) if root else -1
	for i in list.size():
		var pill := _pill(_grid_cell(i, y), HexRRemoteProtocol.scene_display_name(list[i]), 12, i == current,
				func() -> void: _SceneLoader.load_scene(i))
		# The scene you are already in is not somewhere to go.
		pill.disabled = i == current
	return y + _grid_height(list.size()) + GAP


func _build_demos(y: float) -> float:
	if not show_demo_groups:
		return y
	_demo_groups.clear()
	var root := _scene_root()
	if root:
		for n in root.find_children("* Demo Components", "", true, false):
			_demo_groups.append(n)
	if _demo_groups.is_empty():
		return y
	y = _section_label("DEMOS", y)
	for i in _demo_groups.size():
		var group := _demo_groups[i]
		_demo_pills.append(_pill(_grid_cell(i, y), String(group.name).trim_suffix(" Components"), 12, false,
				_show_demo.bind(group)))
	_refresh_demo_pills()
	return y + _grid_height(_demo_groups.size()) + GAP


# -- actions ---------------------------------------------------------------------------------

func _connect(hand: int) -> void:
	_glove_labels[hand].add_theme_color_override("font_color", MUTED)
	var hub := HexRManager.get_instance()
	if hub == null:
		_set_glove_text(hand, "No HexR rig in this scene")
		return
	if hand == HaptGloveHandler.HandType.LEFT:
		hub.connect_left_bt()
	else:
		hub.connect_right_bt()


# The button owns the state, so its label and what is drawn cannot drift apart.
func _toggle_colliders() -> void:
	var v := HaptGloveCollidersVisualizer.find()
	if v:
		v.set_visible(not v.is_showing())
	_update_colliders_label()


func _show_demo(group: Node) -> void:
	for g in _demo_groups:
		if is_instance_valid(g):
			_set_active(g, g == group)
	_refresh_demo_pills()


func _refresh_demo_pills() -> void:
	for i in mini(_demo_pills.size(), _demo_groups.size()):
		var on := is_instance_valid(_demo_groups[i]) and _is_active(_demo_groups[i])
		_demo_pills[i].active = on
		_demo_pills[i].disabled = on


# Unity's SetActive: hidden and out of processing and physics.
static func _set_active(n: Node, on: bool) -> void:
	if n is Node3D or n is CanvasItem:
		n.visible = on
	n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


static func _is_active(n: Node) -> bool:
	return n.process_mode != Node.PROCESS_MODE_DISABLED and (not (n is Node3D or n is CanvasItem) or n.visible)


# -- every frame -----------------------------------------------------------------------------

func _update_gloves(hub: HexRManager) -> void:
	for hand in _glove_labels.size():
		var g := hub.glove(hand) if hub else null
		if g == null:
			continue
		if not g.status_text.is_empty() and _glove_labels[hand].text != g.status_text:
			_set_glove_text(hand, g.status_text)
		# Only the change is acted on: a drop already reported has turned the label to the
		# warning colour, which stays.
		var connected := g.ble_connected
		if connected == _shown_connected[hand]:
			continue
		_shown_connected[hand] = connected
		if connected:
			_glove_labels[hand].add_theme_color_override("font_color", OK)
		elif _glove_labels[hand].get_theme_color("font_color") == OK:
			_glove_labels[hand].add_theme_color_override("font_color", TEXT)


func _on_connect_attempt_ended(hand: int) -> void:
	if hand < _glove_labels.size() and is_instance_valid(_glove_labels[hand]):
		_glove_labels[hand].add_theme_color_override("font_color", WARN)


func _set_glove_text(hand: int, text: String) -> void:
	_glove_labels[hand].text = text
	_fit(_glove_labels[hand], 15, 8)


func _update_colliders_label() -> void:
	if _colliders_label == null:
		return
	var v := HaptGloveCollidersVisualizer.find()
	if v == null or not v.has_hands():
		# Nothing to draw colliders for: say so rather than offer a button that does nothing.
		_colliders_label.text = "Colliders  -  no rig"
		_colliders_label.add_theme_color_override("font_color", MUTED)
		return
	_colliders_label.text = "Hide Colliders" if v.is_showing() else "Show Colliders"
	_colliders_label.add_theme_color_override("font_color", TEXT)


func _update_readout(hub: HexRManager) -> void:
	if _values.is_empty():
		return
	var now := Time.get_ticks_msec()
	for hand in 2:
		var g := hub.glove(hand) if hub else null
		for c in 6:
			var i := hand * 6 + c
			var changed := _readout_repaint
			var on := false
			if g != null:
				on = g.haptics.get_channel_state(c).is_on()
				# The activation count, not the state, says "triggered": it moves for a tap that
				# was already off by this frame, and for a repeat of the same value.
				var count := g.haptics.get_activation_count(c)
				if count != _shown_count[i]:
					_shown_count[i] = count
					_last[i] = format_channel(g.haptics.get_last_active_state(c))
					_lit_until[i] = now + READOUT_FLASH_MS
					changed = true
			var lit := on or now < _lit_until[i]
			if not changed and lit == _shown_lit[i]:
				continue
			_shown_lit[i] = lit
			_values[i].text = _last[i] if not _last[i].is_empty() else "-"
			_fit(_values[i], 13, 8)
			_values[i].add_theme_color_override("font_color", TEXT if lit else MUTED)
			_cells[i].add_theme_stylebox_override("panel", rounded(ACCENT if lit else CELL_FACE, CELL_RADIUS * _s))
	_readout_repaint = false


## Unity's readout text: "0.5" for pressure, "0.5  30Hz" for vibration, "0.5  pulse" for pulses.
static func format_channel(state: Haptics.ChannelState) -> String:
	var value := _num(state.intensity, 0.01)
	match state.mode:
		Haptics.HapticMode.VIBRATION:
			return value + "  " + _num(state.frequency, 0.1) + "Hz" \
					if state.frequency > 0.0 and state.frequency < 255.0 else value + "  vib"
		Haptics.HapticMode.PULSE:
			return value + "  pulse"
	return value


# C#'s "0.##": the decimals [param step] allows, none trailing.
static func _num(x: float, step: float) -> String:
	var s := String.num(snappedf(x, step), 2)
	return s.rstrip("0").rstrip(".") if s.contains(".") else s


# Tells the wearer when a phone is connected through HexR Remote, and above all when one is
# watching their view. Shown where "grab to move" sits, so the layout does not change.
func _update_remote_hint() -> void:
	if _hint == null:
		return
	var remote := HexRRemote.instance
	var state := 0
	if remote != null and is_instance_valid(remote):
		state = 2 if remote.phones_watching() > 0 else (1 if remote.phones_connected() > 0 else 0)
	if state == _shown_remote:
		return
	_shown_remote = state
	match state:
		2:
			_hint.text = "phone watching"
			_hint.add_theme_color_override("font_color", ACCENT)
		1:
			_hint.text = "phone connected"
			_hint.add_theme_color_override("font_color", MUTED)
		_:
			_hint.text = "grab to move"
			_hint.add_theme_color_override("font_color", FAINT)


# -- building blocks -------------------------------------------------------------------------

## A section label as an ARIS eyebrow: small spaced capitals, muted, behind a short accent rule.
func _section_label(text: String, y: float) -> float:
	_label(Rect2(MARGIN + EYEBROW_INDENT, y, UNITY_WIDTH - MARGIN * 2 - EYEBROW_INDENT, SECTION_LABEL_HEIGHT), text, 11,
			_tracked("Archivo-Bold", 0.22, 11), MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_box(Rect2(MARGIN, y + SECTION_LABEL_HEIGHT * 0.5 - 1.25, 14, 2.5), ACCENT)
	return y + SECTION_LABEL_HEIGHT


func _pill(r: Rect2, text: String, font_size: float, active: bool, action: Callable) -> Pill:
	var pill := Pill.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.stroke = _stroke()
	_place(pill, r)
	pill.action = action
	add_child(pill)
	pill.label = _label(Rect2(8, 0, r.size.x - 16, r.size.y), text, font_size, _font("Inter-SemiBold"), TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, pill)
	_fit(pill.label, font_size, 8)
	pill.active = active
	buttons.append({"rect": pill.get_rect(), "pill": pill})
	return pill


func _grid_cell(index: int, top: float) -> Rect2:
	var w := (UNITY_WIDTH - MARGIN * 2 - GRID_GAP) * 0.5
	return Rect2(MARGIN + (index % 2) * (w + GRID_GAP), top + (index / 2) * (GRID_BUTTON_HEIGHT + GRID_GAP), w,
			GRID_BUTTON_HEIGHT)


func _grid_height(count: int) -> float:
	return ((count + 1) / 2) * (GRID_BUTTON_HEIGHT + GRID_GAP)


func _box(r: Rect2, color: Color) -> ColorRect:
	var b := ColorRect.new()
	b.color = color
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(b, r)
	add_child(b)
	return b


func _label(r: Rect2, text: String, font_size: float, font: Font, color: Color, align: HorizontalAlignment,
		parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", roundi(font_size * _s))
	l.add_theme_color_override("font_color", color)
	_place(l, r)
	(parent if parent else self).add_child(l)
	return l


# Rects are given in Unity's panel pixels, top-left based, and scaled here.
func _place(c: Control, r: Rect2) -> void:
	c.position = r.position * _s
	c.size = r.size * _s


func _stroke() -> int:
	return maxi(1, roundi(STROKE * _s))


## Shrinks a label until its text fits, down to [param min_size] (Unity pixels), as TextMesh Pro's
## auto-size does on the menu's buttons and cells.
func _fit(l: Label, max_size: float, min_size: float) -> void:
	var font: Font = l.get_theme_font("font")
	var px := roundi(max_size * _s)
	var floor_px := roundi(min_size * _s)
	while px > floor_px and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > l.size.x:
		px -= 1
	l.add_theme_font_size_override("font_size", px)


func _scene_root() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene


static func rounded(color: Color, radius: float, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(roundi(radius))
	sb.anti_aliasing = true
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	return sb


static var _fonts := {}


static func _font(file: String) -> Font:
	if not _fonts.has(file):
		var f := load(FONT_DIR + file + ".ttf") as Font
		_fonts[file] = f if f else ThemeDB.fallback_font
	return _fonts[file]


## Spaced capitals, without kerning: the fonts' kerning pairs are drawn for normal spacing, and
## under wide tracking they pull some letters together.
func _tracked(file: String, em: float, unity_size: float) -> Font:
	var v := FontVariation.new()
	v.base_font = _font(file)
	v.spacing_glyph = roundi(em * unity_size * _s)
	v.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("kern"): 0}
	return v
