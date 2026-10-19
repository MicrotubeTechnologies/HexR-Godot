@tool
extends EditorPlugin
## Registers the HexR autoload, the Android export step and the project settings.

const AUTOLOAD_NAME := "HexR"
const AUTOLOAD_PATH := "res://addons/hexr/core/hexr_manager.gd"
const TOUCH_LAYER := 20
const INTERACTABLE_LAYER := 21

const SETTINGS := [
	{"name": "hexr/bluetooth/force_simulated", "type": TYPE_BOOL, "default": false,
		"hint_string": "Use simulated gloves even where real Bluetooth is available."},
	{"name": "hexr/bluetooth/simulated_gloves", "type": TYPE_BOOL, "default": false,
		"hint_string": "Give the simulated transport a left and a right glove to connect to."},
	{"name": "hexr/remote/record_audio", "type": TYPE_INT, "default": 0, "hint": PROPERTY_HINT_ENUM,
		"hint_string": "Auto,Always,Never"},
]

var _export_plugin: EditorExportPlugin


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_name_physics_layers()


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	_export_plugin = preload("res://addons/hexr/editor/hexr_export_plugin.gd").new()
	add_export_plugin(_export_plugin)
	_add_settings()


func _exit_tree() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


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
