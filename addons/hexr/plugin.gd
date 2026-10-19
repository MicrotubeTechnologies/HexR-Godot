@tool
extends EditorPlugin
## Registers the HexR autoload, the HexR dock (Haptics Tester and setup checks), the Android
## export step, the debugger bridge, the project settings and the Project > Tools > HexR menu.

const AUTOLOAD_NAME := "HexR"
const AUTOLOAD_PATH := "res://addons/hexr/core/hexr_manager.gd"
const TOUCH_LAYER := 20
const INTERACTABLE_LAYER := 21
const HexRDock := preload("res://addons/hexr/editor/hexr_dock.gd")

const SETTINGS := [
	{"name": "hexr/bluetooth/force_simulated", "type": TYPE_BOOL, "default": false,
		"hint_string": "Use simulated gloves even where real Bluetooth is available."},
	{"name": "hexr/bluetooth/simulated_gloves", "type": TYPE_BOOL, "default": false,
		"hint_string": "Give the simulated transport a left and a right glove to connect to."},
	{"name": "hexr/remote/record_audio", "type": TYPE_INT, "default": 0, "hint": PROPERTY_HINT_ENUM,
		"hint_string": "Auto,Always,Never"},
]

var _export_plugin: EditorExportPlugin
var _debugger: EditorDebuggerPlugin
var _dock: HexRDock
var _menu: PopupMenu


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
	_dock = HexRDock.new()
	_dock.debugger = _debugger
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	_menu = PopupMenu.new()
	_menu.add_item("Create HexR Rig", 0)
	_menu.add_item("Add HexR Menu", 1)
	_menu.add_item("Add HexR Remote", 2)
	_menu.add_separator()
	_menu.add_item("Check Setup", 3)
	_menu.id_pressed.connect(_on_menu)
	add_tool_submenu_item("HexR", _menu)
	_add_settings()


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
	if _debugger:
		remove_debugger_plugin(_debugger)
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	remove_tool_menu_item("HexR")


func _on_menu(id: int) -> void:
	match id:
		0:
			_create_rig()
		1:
			_add_to_origin(HexRFloatingMenu.new(), "HexRFloatingMenu", Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(40), 0)), Vector3(-0.62, 1.22, -0.42)))
		2:
			_add_to_origin(HexRRemote.new(), "HexRRemote", Transform3D())
		3:
			_dock.refresh_checks()


## Adds an XROrigin3D (if the scene has none) and a HexRRig with both tracked hands and both
## Pressure Controllers as visible nodes.
func _create_rig() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("HexR: open a 3D scene first.")
		return
	var ur := get_undo_redo()
	ur.create_action("Create HexR Rig")
	var origin := _find_origin(root)
	if origin == null:
		origin = XROrigin3D.new()
		origin.name = "XROrigin3D"
		var cam := XRCamera3D.new()
		cam.name = "XRCamera3D"
		cam.position = Vector3(0, 1.6, 0)
		ur.add_do_method(root, "add_child", origin, true)
		ur.add_do_method(origin, "set_owner", root)
		ur.add_do_method(origin, "add_child", cam, true)
		ur.add_do_method(cam, "set_owner", root)
		ur.add_do_reference(origin)
		ur.add_undo_method(root, "remove_child", origin)
	var rig := HexRRig.new()
	rig.name = "HexRRig"
	ur.add_do_method(origin, "add_child", rig, true)
	ur.add_do_method(rig, "set_owner", root)
	for hand in [HexRTypes.Hand.LEFT, HexRTypes.Hand.RIGHT]:
		var side := HexRTypes.hand_name(hand)
		var h := HexRTrackedHand.new()
		h.name = side + "Hand"
		h.hand = hand
		var c := HexRPressureController.new()
		c.name = side + "PressureController"
		c.hand = hand
		for n in [h, c]:
			ur.add_do_method(rig, "add_child", n, true)
			ur.add_do_method(n, "set_owner", root)
	ur.add_do_reference(rig)
	ur.add_undo_method(origin, "remove_child", rig)
	ur.commit_action()


func _add_to_origin(node: Node, node_name: String, xf: Transform3D) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("HexR: open a 3D scene first.")
		return
	var parent: Node = _find_origin(root)
	if parent == null:
		parent = root
	node.name = node_name
	if node is Node3D:
		(node as Node3D).transform = xf
	var ur := get_undo_redo()
	ur.create_action("Add " + node_name)
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()


func _find_origin(root: Node) -> XROrigin3D:
	if root is XROrigin3D:
		return root
	var found := root.find_children("*", "XROrigin3D", true, false)
	return found[0] if not found.is_empty() else null


func _add_settings() -> void:
	for s: Dictionary in SETTINGS:
		var setting_name: String = s["name"]
		if not ProjectSettings.has_setting(setting_name):
			ProjectSettings.set_setting(setting_name, s["default"])
		ProjectSettings.set_initial_value(setting_name, s["default"])
		ProjectSettings.add_property_info({"name": setting_name, "type": s["type"],
				"hint": s.get("hint", PROPERTY_HINT_NONE), "hint_string": s.get("hint_string", "")})


## Names the two physics layers the touch points and zones use, unless the project already
## uses those names for something else.
func _name_physics_layers() -> void:
	for pair in [[TOUCH_LAYER, "hexr_touch"], [INTERACTABLE_LAYER, "hexr_interactable"]]:
		var key := "layer_names/3d_physics/layer_%d" % pair[0]
		if String(ProjectSettings.get_setting(key, "")).is_empty():
			ProjectSettings.set_setting(key, pair[1])
	ProjectSettings.save()
