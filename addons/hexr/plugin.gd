@tool
extends EditorPlugin
## Registers the HexR autoload, the HexR menu (in the editor's menu bar, as Unity has it, and under
## Project > Tools), the HexR Tools dock, the inspector helpers, the Android export step, the
## debugger bridge and the project settings.

const AUTOLOAD_NAME := "HexR"
const AUTOLOAD_PATH := "res://addons/hexr/core/hexr_manager.gd"
const TOUCH_LAYER := 20
const INTERACTABLE_LAYER := 21
const HexRDock := preload("res://addons/hexr/editor/hexr_dock.gd")
const Tools := preload("res://addons/hexr/editor/hexr_scene_tools.gd")

const SETTINGS := [
	{"name": "hexr/bluetooth/force_simulated", "type": TYPE_BOOL, "default": false,
		"hint_string": "Use simulated gloves even where real Bluetooth is available."},
	{"name": "hexr/bluetooth/simulated_gloves", "type": TYPE_BOOL, "default": false,
		"hint_string": "Give the simulated transport a left and a right glove to connect to."},
	{"name": "hexr/remote/record_audio", "type": TYPE_INT, "default": 0, "hint": PROPERTY_HINT_ENUM,
		"hint_string": "Auto,Always,Never"},
	# The app's scenes, in order: Godot's stand-in for Unity's Build Settings list. The floating
	# menu's SCENES, HexR Remote and SceneLoader use it. Hint "4/13:..." is String / FILE.
	{"name": "hexr/scenes", "type": TYPE_PACKED_STRING_ARRAY, "default": [],
		"hint": PROPERTY_HINT_TYPE_STRING, "hint_string": "4/13:*.tscn,*.scn", "basic": true},
]

# The HexR menu's items, in the Unity package's order.
enum Item { TOOLS, DEMO, RIG, MENU, REMOTE, SAMPLES, VALIDATE, UPGRADE }

var _export_plugin: EditorExportPlugin
var _debugger: EditorDebuggerPlugin
var _inspector: EditorInspectorPlugin
var _dock: HexRDock
var _bar_menu: PopupMenu
var _toolbar_button: MenuButton
var _tools_menu: PopupMenu


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_name_physics_layers()


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	_export_plugin = preload("res://addons/hexr/editor/hexr_export_plugin.gd").new()
	add_export_plugin(_export_plugin)
	_debugger = preload("res://addons/hexr/editor/hexr_debugger_plugin.gd").new()
	add_debugger_plugin(_debugger)
	_inspector = preload("res://addons/hexr/editor/hexr_inspector_plugin.gd").new()
	_inspector.plugin = self
	add_inspector_plugin(_inspector)
	_dock = HexRDock.new()
	_dock.debugger = _debugger
	_dock.plugin = self
	add_dock(_dock)
	_add_menus()
	_add_settings()
	scene_changed.connect(_on_scene_changed)
	_offer_0_1_cleanup.call_deferred()


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
	if _debugger:
		remove_debugger_plugin(_debugger)
	if _inspector:
		remove_inspector_plugin(_inspector)
	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
	if _bar_menu and is_instance_valid(_bar_menu):
		_bar_menu.queue_free()
	if _toolbar_button:
		remove_control_from_container(CONTAINER_TOOLBAR, _toolbar_button)
		_toolbar_button.queue_free()
	remove_tool_menu_item("HexR")


# -- the HexR menu ----------------------------------------------------------------------------

func _add_menus() -> void:
	# A top-level HexR menu beside Help, as Unity has one. Godot has no API for this, so if the
	# editor's menu bar is not where it is expected, a HexR button in the toolbar stands in.
	var bars := EditorInterface.get_base_control().find_children("*", "MenuBar", true, false)
	if not bars.is_empty():
		var bar := bars[0] as MenuBar
		_bar_menu = _make_menu()
		_bar_menu.name = "HexR"
		bar.add_child(_bar_menu)
		for i in bar.get_child_count():
			if bar.get_child(i).name == "Help":
				bar.move_child(_bar_menu, i)
				break
	else:
		_toolbar_button = MenuButton.new()
		_toolbar_button.text = "HexR"
		_toolbar_button.flat = true
		_fill(_toolbar_button.get_popup())
		add_control_to_container(CONTAINER_TOOLBAR, _toolbar_button)
	_tools_menu = _make_menu()
	add_tool_submenu_item("HexR", _tools_menu)


func _make_menu() -> PopupMenu:
	var m := PopupMenu.new()
	_fill(m)
	return m


func _fill(m: PopupMenu) -> void:
	m.add_item("HexR Tools", Item.TOOLS)
	m.add_separator()
	m.add_item("Create Demo Scene", Item.DEMO)
	m.add_separator()
	m.add_item("Create HexR Rig", Item.RIG)
	m.add_item("Add HexR Menu", Item.MENU)
	m.add_item("Add HexR Remote", Item.REMOTE)
	m.add_item("Import Tutorial Content", Item.SAMPLES)
	m.add_separator()
	var troubleshoot := PopupMenu.new()
	troubleshoot.add_item("Validate Scene Setup", Item.VALIDATE)
	troubleshoot.id_pressed.connect(_on_item)
	m.add_submenu_node_item("Troubleshoot", troubleshoot)
	var migration := PopupMenu.new()
	migration.add_item("Upgrade 0.1 Scenes", Item.UPGRADE)
	migration.id_pressed.connect(_on_item)
	m.add_submenu_node_item("Migration", migration)
	m.id_pressed.connect(_on_item)
	# Items that need an open scene are greyed out without one, as Unity's are.
	m.about_to_popup.connect(func() -> void:
		var open := EditorInterface.get_edited_scene_root() != null
		for id in [Item.RIG, Item.MENU, Item.REMOTE]:
			m.set_item_disabled(m.get_item_index(id), not open))


func _on_item(id: int) -> void:
	match id:
		Item.TOOLS:
			_dock.reveal(0)
		Item.DEMO:
			Tools.create_demo_scene()
		Item.RIG:
			Tools.create_rig(self)
		Item.MENU:
			Tools.add_menu(self)
		Item.REMOTE:
			Tools.add_remote(self)
		Item.SAMPLES:
			Tools.import_tutorial_content()
		Item.VALIDATE:
			_dock.reveal(1)
		Item.UPGRADE:
			Tools.upgrade_0_1_scenes()


func _on_scene_changed(_root: Node) -> void:
	if _dock:
		_dock.refresh_checks()


## An install of 0.2 over 0.1 leaves 0.1's scripts behind under their old names. Offer to remove them.
func _offer_0_1_cleanup() -> void:
	var stale := Tools.stale_0_1_files()
	if stale.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "HexR 0.2"
	dialog.dialog_text = ("HexR 0.2 found %d script(s) left from HexR 0.1, which now have other names:\n\n%s\n\n"
			+ "Delete them? Then run HexR > Migration > Upgrade 0.1 Scenes, and restart the editor.") \
			% [stale.size(), "\n".join(stale)]
	dialog.ok_button_text = "Delete"
	dialog.confirmed.connect(func() -> void:
		Tools.delete_stale_0_1_files()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


# -- settings ---------------------------------------------------------------------------------

func _add_settings() -> void:
	for s: Dictionary in SETTINGS:
		var setting_name: String = s["name"]
		var default: Variant = s["default"]
		if s["type"] == TYPE_PACKED_STRING_ARRAY:
			default = PackedStringArray(default)  # a constant can't hold one
		if not ProjectSettings.has_setting(setting_name):
			ProjectSettings.set_setting(setting_name, default)
		ProjectSettings.set_initial_value(setting_name, default)
		ProjectSettings.add_property_info({"name": setting_name, "type": s["type"],
				"hint": s.get("hint", PROPERTY_HINT_NONE), "hint_string": s.get("hint_string", "")})
		ProjectSettings.set_as_basic(setting_name, s.get("basic", false))


## Names the two physics layers the touch points and zones use, unless the project already
## uses those names for something else.
func _name_physics_layers() -> void:
	for pair in [[TOUCH_LAYER, "hexr_touch"], [INTERACTABLE_LAYER, "hexr_interactable"]]:
		var key := "layer_names/3d_physics/layer_%d" % pair[0]
		if String(ProjectSettings.get_setting(key, "")).is_empty():
			ProjectSettings.set_setting(key, pair[1])
	ProjectSettings.save()
