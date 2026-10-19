@tool
extends EditorExportPlugin
## Adds HexR's Android plugins to Android exports, and RECORD_AUDIO only when a HexR Remote
## shares the game's sound (Meta's store review asks about that permission).
##
## Android plugins need "Use Gradle Build" in the Android export preset, which the OpenXR vendors
## plugin needs anyway.

const BIN := "hexr/android/bin/"
const REMOTE_SCRIPT := "addons/hexr/remote/hexr_remote.gd"
const WINDOWS_EXTENSION := "res://addons/hexr/bin/hexr_ble_win.gdextension"

var _remote_scan_done := false
var _remote_used := false
var _remote_shares_sound := false


func _get_name() -> String:
	return "HexR"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return true


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_remote_scan_done = false
	if features.has("android") and not _uses_gradle_build():
		push_warning("HexR: turn on \"Use Gradle Build\" in the Android export preset. Without it the "
				+ "HexR Bluetooth plugin is left out and gloves cannot connect.")


func _export_file(path: String, _type: String, features: PackedStringArray) -> void:
	# The Bluetooth extension ships libraries for Windows, Linux, macOS and Android (stubs on all
	# but Windows). Anywhere else there is nothing to load, so leave it out.
	if path == WINDOWS_EXTENSION:
		for platform in ["windows", "linux", "macos", "android"]:
			if features.has(platform):
				return
		skip()


func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	var flavor := "debug" if debug else "release"
	var libs := PackedStringArray([BIN + "hexr-ble-%s.aar" % flavor])
	_scan_for_remote()
	if _remote_used:
		libs.append(BIN + "hexr-remote-%s.aar" % flavor)
	return libs


func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	_scan_for_remote()
	var mode: int = ProjectSettings.get_setting("hexr/remote/record_audio", 0)
	var wanted := _remote_shares_sound if mode == 0 else mode == 1
	if wanted:
		return "    <uses-permission android:name=\"android.permission.RECORD_AUDIO\" />\n"
	return ""


func _uses_gradle_build() -> bool:
	var preset := get_export_preset()
	return preset != null and bool(preset.get_or_env("gradle_build/use_gradle_build", ""))


## Looks through the project's scenes for HexR Remote nodes, and whether any shares sound
## (share_sound defaults to on, so a node without "share_sound = false" shares it).
func _scan_for_remote() -> void:
	if _remote_scan_done:
		return
	_remote_scan_done = true
	_remote_used = false
	_remote_shares_sound = false
	_scan_dir("res://")


func _scan_dir(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "android" or FileAccess.file_exists(dir_path.path_join(sub).path_join(".gdignore")):
			continue
		_scan_dir(dir_path.path_join(sub))
	for f in d.get_files():
		if f.ends_with(".tscn"):
			_scan_scene(dir_path.path_join(f))


func _scan_scene(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if not text.contains(REMOTE_SCRIPT):
		return
	var remote_ids: Array[String] = []
	for line in text.split("\n"):
		if line.begins_with("[ext_resource") and line.contains(REMOTE_SCRIPT):
			var at := line.find(" id=\"")
			if at >= 0:
				remote_ids.append(line.substr(at + 5, line.find("\"", at + 5) - at - 5))
	if remote_ids.is_empty():
		return
	# Walk node blocks; a block that sets the remote script is a HexR Remote node.
	for block in text.split("\n[node "):
		for id in remote_ids:
			if block.contains("script = ExtResource(\"%s\")" % id):
				_remote_used = true
				if not block.contains("share_sound = false"):
					_remote_shares_sound = true
