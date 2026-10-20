class_name SceneLoader
extends RefCounted
## Switches between the app's scenes (port of the Unity package's SceneLoader).
##
## Unity lists an app's scenes in Build Settings; Godot has no such list, so HexR keeps one in
## the project setting [code]hexr/scenes[/code] (Project Settings > HexR, or HexR Tools > Project
## Setup). The floating menu's SCENES section, HexR Remote and these calls all use it, so an
## index means the same scene everywhere.
## [codeblock]
## SceneLoader.load_scene("Hospital")      # by name, as Unity does
## SceneLoader.load_scene(2)               # by its place in hexr/scenes
## SceneLoader.load_next_scene()
## [/codeblock]

const SETTING := "hexr/scenes"


## The scenes listed in [code]hexr/scenes[/code], as res:// paths, in order.
static func scenes() -> PackedStringArray:
	var out := PackedStringArray()
	for s in ProjectSettings.get_setting(SETTING, PackedStringArray()):
		var path := _path_of(String(s))
		if not path.is_empty():
			out.append(path)
	return out


## Opens a scene by its index in [code]hexr/scenes[/code], its name ("Hospital", the file name
## without its extension), or its res:// path. Returns [constant OK], or an error when there is
## no such scene. Opening the scene already open does nothing, as in the floating menu.
static func load_scene(scene: Variant) -> Error:
	var path := _resolve(scene)
	if path.is_empty():
		push_warning("[HexR] SceneLoader: no scene %s in %s." % [str(scene), SETTING])
		return ERR_DOES_NOT_EXIST
	var tree := _tree()
	if tree == null:
		return ERR_UNAVAILABLE
	if tree.current_scene and tree.current_scene.scene_file_path == path:
		return OK
	return tree.change_scene_to_file(path)


## Reloads the scene that is open.
static func reload_current_scene() -> Error:
	var tree := _tree()
	return tree.reload_current_scene() if tree else ERR_UNAVAILABLE


## Opens the next scene in [code]hexr/scenes[/code], wrapping round to the first.
static func load_next_scene() -> Error:
	return _step(1)


## Opens the previous scene in [code]hexr/scenes[/code], wrapping round to the last.
static func load_previous_scene() -> Error:
	return _step(-1)


## The open scene's name: its file name without the extension, as Unity names scenes.
static func get_current_scene_name() -> String:
	var tree := _tree()
	if tree == null or tree.current_scene == null:
		return ""
	var path := tree.current_scene.scene_file_path
	return path.get_file().get_basename() if not path.is_empty() else String(tree.current_scene.name)


## The open scene's index in [code]hexr/scenes[/code], or -1 when it isn't listed.
static func get_current_scene_index() -> int:
	var tree := _tree()
	if tree == null or tree.current_scene == null:
		return -1
	return scenes().find(tree.current_scene.scene_file_path)


static func _step(delta: int) -> Error:
	var list := scenes()
	if list.is_empty():
		return ERR_DOES_NOT_EXIST
	var i := get_current_scene_index()
	return load_scene(list[posmod(i + delta, list.size())] if i >= 0 else list[0])


static func _resolve(scene: Variant) -> String:
	var list := scenes()
	if scene is int:
		return list[scene] if scene >= 0 and scene < list.size() else ""
	var s := String(scene)
	if s.begins_with("res://") or s.begins_with("uid://"):
		return _path_of(s)
	for path in list:
		if path.get_file().get_basename() == s or HexRRemoteProtocol.scene_display_name(path) == s:
			return path
	return ""


# The file picker can store uid:// paths; everything else compares res:// paths.
static func _path_of(s: String) -> String:
	if s.begins_with("uid://"):
		var id := ResourceUID.text_to_id(s)
		return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	return s


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
