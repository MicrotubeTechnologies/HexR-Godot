@tool
extends Node
## What the HexR Tools dock's Project Setup tab does (the Unity package's Project Setup): install
## the OpenXR Vendors plugin and Godot XR Tools, apply the XR project settings, add Meta Quest and
## PICO export presets, and check for and install HexR updates. A Node, because downloads run
## on an HTTPRequest that has to be in the tree.

signal progress(text: String)

## Versions the addon is tested with. A newer Godot minor may need newer ones.
const VENDORS := {"name": "OpenXR Vendors plugin", "version": "5.1.0", "dir": "godotopenxrvendors",
	"url": "https://github.com/GodotVR/godot_openxr_vendors/releases/download/5.1.0-stable/godotopenxrvendorsaddon.zip",
	"marker": "res://addons/godotopenxrvendors/plugin.gdextension", "plugin": ""}
const XR_TOOLS := {"name": "Godot XR Tools", "version": "4.5.2", "dir": "godot-xr-tools",
	"url": "https://github.com/GodotVR/godot-xr-tools/releases/download/4.5.2/godot-xr-tools.zip",
	"marker": "res://addons/godot-xr-tools/plugin.cfg", "plugin": "res://addons/godot-xr-tools/plugin.cfg"}
const RELEASES_API := "https://api.github.com/repos/MicrotubeTechnologies/HexR-Godot/releases?per_page=10"
const UPDATE_DIR := "res://.godot/hexr_update/"

## The settings a Quest or PICO hand-tracking app needs, as the tutorial project has them.
const XR_SETTINGS := {
	"xr/openxr/enabled": true,
	"xr/shaders/enabled": true,
	"xr/openxr/extensions/hand_tracking": true,
	"xr/openxr/extensions/hand_interaction_profile": true,
	"xr/openxr/reference_space": 2,
	"xr/openxr/foveation_level": 3,
	"xr/openxr/foveation_dynamic": true,
	"rendering/renderer/rendering_method": "mobile",
	"rendering/textures/vram_compression/import_etc2_astc": true,
}
const PRESET_COMMON := {
	"gradle_build/use_gradle_build": true,
	"architectures/armeabi-v7a": false,
	"architectures/arm64-v8a": true,
	"architectures/x86": false,
	"architectures/x86_64": false,
	"screen/immersive_mode": true,
	"xr_features/xr_mode": 1,
}
const PRESET_QUEST := {
	"gradle_build/min_sdk": "32",
	"xr_features/enable_meta_plugin": true,
	"meta_xr_features/hand_tracking": 1,
	"meta_xr_features/hand_tracking_frequency": 1,
	"meta_xr_features/quest_2_support": true,
	"meta_xr_features/quest_3_support": true,
	"meta_xr_features/quest_pro_support": true,
}
const PRESET_PICO := {
	"gradle_build/min_sdk": "29",
	"xr_features/enable_pico_plugin": true,
	"pico_xr_features/hand_tracking": 2,
}

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)


# -- what is there ----------------------------------------------------------------------------

static func is_installed(addon: Dictionary) -> bool:
	return FileAccess.file_exists(addon["marker"])


static func xr_settings_applied() -> bool:
	for key in XR_SETTINGS:
		if ProjectSettings.get_setting(key) != XR_SETTINGS[key]:
			return false
	return true


## "missing", "stale" (made by another Godot version) or "ok".
static func build_template_state() -> String:
	if not FileAccess.file_exists("res://android/.build_version"):
		return "missing"
	var have := FileAccess.get_file_as_string("res://android/.build_version").strip_edges()
	var v := Engine.get_version_info()
	var want := "%d.%d.%d.%s" % [v["major"], v["minor"], v["patch"], v["status"]] if v["patch"] > 0 \
			else "%d.%d.%s" % [v["major"], v["minor"], v["status"]]
	return "ok" if have == want else "stale"


## The names of the export presets for each headset that are already there.
static func presets() -> Dictionary:
	var cfg := ConfigFile.new()
	var found := {"quest": "", "pico": ""}
	if cfg.load("res://export_presets.cfg") != OK:
		return found
	for section in cfg.get_sections():
		if section.ends_with(".options") or cfg.get_value(section, "platform", "") != "Android":
			continue
		var opts := section + ".options"
		if cfg.get_value(opts, "xr_features/enable_meta_plugin", false):
			found["quest"] = cfg.get_value(section, "name", "")
		if cfg.get_value(opts, "xr_features/enable_pico_plugin", false):
			found["pico"] = cfg.get_value(section, "name", "")
	return found


static func installed_version() -> String:
	var cfg := ConfigFile.new()
	return cfg.get_value("plugin", "version", "?") if cfg.load("res://addons/hexr/plugin.cfg") == OK else "?"


# -- changes ----------------------------------------------------------------------------------

static func apply_xr_settings() -> void:
	for key in XR_SETTINGS:
		ProjectSettings.set_setting(key, XR_SETTINGS[key])
	ProjectSettings.save()


## Adds a Quest and/or a PICO preset with the tutorial's values. The editor keeps presets in
## memory and writes them back, so the caller restarts the editor straight after.
static func add_presets(quest: bool, pico: bool) -> PackedStringArray:
	var cfg := ConfigFile.new()
	cfg.load("res://export_presets.cfg")
	var have := presets()
	var next := 0
	while cfg.has_section("preset.%d" % next):
		next += 1
	var added := PackedStringArray()
	var app := String(ProjectSettings.get_setting("application/config/name", "HexR App"))
	var package := "com.example." + app.to_lower().validate_filename().replace(" ", "").replace("-", "")
	for want in [["quest", quest, "Meta Quest", PRESET_QUEST], ["pico", pico, "PICO", PRESET_PICO]]:
		if not want[1] or not String(have[want[0]]).is_empty():
			continue
		var section := "preset.%d" % next
		cfg.set_value(section, "name", want[2])
		cfg.set_value(section, "platform", "Android")
		cfg.set_value(section, "runnable", true)
		cfg.set_value(section, "custom_features", want[0])
		cfg.set_value(section, "export_filter", "all_resources")
		cfg.set_value(section, "export_path", "build/%s-%s.apk" % [app.validate_filename().replace(" ", "-"), want[0]])
		var opts := section + ".options"
		for key in PRESET_COMMON:
			cfg.set_value(opts, key, PRESET_COMMON[key])
		for key in want[3]:
			cfg.set_value(opts, key, want[3][key])
		cfg.set_value(opts, "package/unique_name", package)
		cfg.set_value(opts, "package/name", app)
		added.append(want[2])
		next += 1
	if not added.is_empty():
		cfg.save("res://export_presets.cfg")
	return added


## Downloads an addon's release zip and unpacks its addons/<dir>/ folder into the project.
## [param done] gets (ok: bool, message: String).
func install_addon(addon: Dictionary, done: Callable) -> void:
	progress.emit("Downloading %s %s…" % [addon["name"], addon["version"]])
	var zip_path := EditorInterface.get_editor_paths().get_cache_dir().path_join("hexr_%s.zip" % addon["dir"])
	var err := await _download(addon["url"], zip_path)
	if err != "":
		done.call(false, err)
		return
	progress.emit("Unpacking %s…" % addon["name"])
	var count := _unpack(zip_path, "addons/%s/" % addon["dir"], "res://addons/%s/" % addon["dir"])
	if count == 0:
		done.call(false, "The download had no addons/%s folder." % addon["dir"])
		return
	EditorInterface.get_resource_filesystem().scan()
	if addon["plugin"] != "":
		# Enabling it registers its autoloads; wait for the scan so the editor knows the plugin.
		await get_tree().create_timer(2.0).timeout
		EditorInterface.set_plugin_enabled(addon["plugin"], true)
	done.call(true, "%s %s installed (%d files). Restart the editor to load it." % [addon["name"], addon["version"], count])


## Asks GitHub for HexR releases newer than the installed one. [param done] gets
## (newest_version: String, zip_url: String, notes: String), or ("", "", reason).
func check_for_update(done: Callable) -> void:
	_http.download_file = ""
	var err := _http.request(RELEASES_API, ["User-Agent: HexR-Godot-addon", "Accept: application/vnd.github+json"])
	if err != OK:
		done.call("", "", "Could not reach GitHub (%s)." % error_string(err))
		return
	var r: Array = await _http.request_completed
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		done.call("", "", "GitHub answered %d." % r[1])
		return
	var releases: Variant = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	var best := installed_version()
	var best_url := ""
	var notes := ""
	for rel: Dictionary in (releases if releases is Array else []):
		var v := String(rel.get("tag_name", "")).trim_prefix("v")
		if not _newer(v, best):
			continue
		for a: Dictionary in rel.get("assets", []):
			if String(a.get("name", "")) in ["HexR-Godot-%s.zip" % v, "HexR-Godot.zip"]:
				best = v
				best_url = a.get("browser_download_url", "")
				notes = String(rel.get("body", "")).left(400)
	done.call(best if best_url != "" else "", best_url, notes)


## Installs a HexR release over this one and restarts the editor. Refuses while a scene is
## playing: the running game holds the Bluetooth extension's library open.
func apply_update(zip_url: String, done: Callable) -> void:
	if EditorInterface.is_playing_scene():
		done.call(false, "Stop the running scene first.")
		return
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	var zip_path := ProjectSettings.globalize_path(UPDATE_DIR + "HexR-Godot.zip")
	progress.emit("Downloading the update…")
	var err := await _download(zip_url, zip_path)
	if err != "":
		done.call(false, err)
		return
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK or not reader.file_exists("addons/hexr/plugin.cfg"):
		done.call(false, "The download is not a HexR addon.")
		return
	reader.close()
	EditorInterface.save_all_scenes()
	# One pass with no awaits, so no editor script reloads half way: write each file beside its
	# target and move it over, then drop what the new version no longer ships.
	var shipped := {}
	var count := _unpack(zip_path, "addons/hexr/", "res://addons/hexr/", shipped)
	for path in _files_under("res://addons/hexr/"):
		var name := path.get_file()
		if not shipped.has(path) and not name.begins_with("~") and not name.ends_with(".uid") \
				and not name.ends_with(".import"):
			DirAccess.remove_absolute(path)
	done.call(true, "Updated (%d files). Restarting the editor…" % count)
	EditorInterface.restart_editor(false)


# -- plumbing ---------------------------------------------------------------------------------

func _download(url: String, to: String) -> String:
	_http.download_file = to
	var err := _http.request(url, ["User-Agent: HexR-Godot-addon"])
	if err != OK:
		return "Could not start the download (%s)." % error_string(err)
	var r: Array = await _http.request_completed
	_http.download_file = ""
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return "The download failed (result %d, HTTP %d)." % [r[0], r[1]]
	return ""


## Unpacks the entries under [param inside] (wherever it sits in the zip) into [param to].
## Each file is written beside its target and moved over it. Returns how many files.
static func _unpack(zip_path: String, inside: String, to: String, written := {}) -> int:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return 0
	var count := 0
	for entry in reader.get_files():
		var at := entry.find(inside)
		if at < 0 or entry.ends_with("/"):
			continue
		var target := to + entry.substr(at + inside.length())
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f := FileAccess.open(target + ".hexr_new", FileAccess.WRITE)
		if f == null:
			continue
		f.store_buffer(reader.read_file(entry))
		f.close()
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
		DirAccess.rename_absolute(target + ".hexr_new", target)
		written[target] = true
		count += 1
	reader.close()
	return count


static func _files_under(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files_under(dir.path_join(d)))
	return out


static func _newer(a: String, b: String) -> bool:
	var x := a.split(".")
	var y := b.split(".")
	for i in 3:
		var p := int(x[i]) if i < x.size() else 0
		var q := int(y[i]) if i < y.size() else 0
		if p != q:
			return p > q
	return false
