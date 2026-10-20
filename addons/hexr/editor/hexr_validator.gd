@tool
extends RefCounted
## What a HexR project and scene need, each as a check the HexR Tools dock lists with a Fix where it
## can be fixed for you (port of the Unity package's HexRSetupValidator).
##
## A check is {"ok": bool, "title": String, "detail": String, "fix": Callable, "warn": bool}.
## A warning ("warn") is shown but does not count as a failure.

const Setup := preload("res://addons/hexr/editor/hexr_project_setup.gd")
const Tools := preload("res://addons/hexr/editor/hexr_scene_tools.gd")
const TOUCH := 1 << 19
const ZONES := ["SpecialHaptics", "HexRGrabbable", "HexRPhysicalButton", "ProximityCheck", "HexRUsable"]


static func project_checks() -> Array:
	var out := []
	out.append(_check(ProjectSettings.has_setting("autoload/HexR"), "HexR autoload",
			"The HexR plugin adds it when enabled.",
			func() -> void: _save_setting("autoload/HexR", "*res://addons/hexr/core/hexr_manager.gd")))
	for s in [["xr/openxr/enabled", "OpenXR enabled", "Project Settings > XR > OpenXR > Enabled."],
			["xr/shaders/enabled", "XR shaders enabled", "Project Settings > XR > Shaders > Enabled."],
			["xr/openxr/extensions/hand_tracking", "Hand tracking", "The touch points follow the OpenXR hand tracker."],
			["xr/openxr/extensions/hand_interaction_profile", "Hand interaction profile",
				"Lets the headset report pinches and pokes from tracked hands."]]:
		var key: String = s[0]
		out.append(_check(bool(ProjectSettings.get_setting(key, false)), s[1], s[2], func() -> void: _save_setting(key, true)))
	for l in [[20, "hexr_touch", "The touch points live on layer 20; zones watch it."],
			[21, "hexr_interactable", "Layer 21 is HexR's, for objects a hand interacts with."]]:
		var key := "layer_names/3d_physics/layer_%d" % l[0]
		var want: String = l[1]
		out.append(_check(String(ProjectSettings.get_setting(key, "")) == want, "Physics layer %d named %s" % [l[0], want],
				l[2], func() -> void: _save_setting(key, want)))
	out.append(_check(Setup.is_installed(Setup.VENDORS), "OpenXR Vendors plugin",
			"Meta Quest and PICO builds need it. HexR Tools > Project Setup installs it.", Callable()))
	var template := Setup.build_template_state()
	out.append(_check(template == "ok", "Android build template",
			"Missing: Project > Install Android Build Template." if template == "missing"
			else "Made by another Godot version: install it again from the Project menu.", Callable()))
	out.append(_check(FileAccess.file_exists("res://addons/hexr/android/bin/hexr-ble-release.aar"), "Android Bluetooth plugin",
			"addons/hexr/android/bin/*.aar ships in the release zip. Install the addon from the release.", Callable()))
	if OS.get_name() == "Windows":
		out.append(_check(FileAccess.file_exists("res://addons/hexr/bin/windows/hexr_ble_win.windows.template_debug.x86_64.dll"),
				"Windows Bluetooth extension", "addons/hexr/bin/windows/*.dll ships in the release zip. Without it the "
				+ "editor uses simulated gloves.", Callable()))
	var presets := Setup.presets()
	out.append(_check(presets["quest"] != "" or presets["pico"] != "", "Headset export preset",
			"No Meta Quest or PICO preset yet. HexR Tools > Project Setup adds them.", Callable()))
	for p in _android_presets():
		var opts: Dictionary = p["options"]
		var name: String = p["name"]
		if not opts.get("gradle_build/use_gradle_build", false):
			out.append(_check(false, "%s preset uses Gradle build" % name, "Export > %s > Use Gradle Build. HexR's "
					% name + "Bluetooth plugin needs it.", Callable()))
		if (opts.get("xr_features/enable_meta_plugin", false) or opts.get("xr_features/enable_pico_plugin", false)) \
				and int(opts.get("xr_features/xr_mode", 0)) != 1:
			out.append(_check(false, "%s preset runs in OpenXR" % name, "Export > %s > XR Mode: OpenXR." % name, Callable()))
	for path in PackedStringArray(ProjectSettings.get_setting("hexr/scenes", PackedStringArray())):
		if not ResourceLoader.exists(path):
			out.append(_check(false, "Scene list entry %s" % path, "Project Settings > HexR > Scenes lists a scene "
					+ "that is not there.", Callable()))
	if not Tools.stale_0_1_files().is_empty():
		out.append(_check(false, "Files left from HexR 0.1", "An install over 0.1 left its old scripts behind.",
				Tools.delete_stale_0_1_files))
	return out


## Checks for the scene open in the editor. Fixes go through [param ur], so they can be undone.
static func scene_checks(root: Node, ur: EditorUndoRedoManager = null) -> Array:
	var out := []
	if root == null:
		return out
	var origins := _all(root, "XROrigin3D")
	out.append(_check(not origins.is_empty(), "XROrigin3D in the scene", "Hands are tracked relative to it. "
			+ "HexR > Create HexR Rig adds one.", Callable()))
	var rigs := _all(root, "HexRRig")
	out.append(_check(not rigs.is_empty(), "HexR rig", "HexR > Create HexR Rig.", Callable()))
	if rigs.size() > 1:
		out.append(_check(false, "One HexR rig", "This scene has %d; the gloves follow one pair of hands." % rigs.size(),
				Callable()))
	for rig in rigs:
		var under := false
		var p := rig.get_parent()
		while p:
			if p is XROrigin3D:
				under = true
			p = p.get_parent()
		if not under:
			out.append(_check(false, "%s is under the XROrigin3D" % rig.name, "Move it there: hands are placed "
					+ "relative to the origin.", Callable()))
	out.append(_check(not _all(root, "HexRFloatingMenu").is_empty(), "HexR menu",
			"The wearer connects the gloves from it. HexR > Add HexR Menu.", Callable()))
	var zones := 0
	for cls in ZONES:
		for z in _all(root, cls):
			zones += 1
			var a := z as Area3D
			if a and (a.collision_mask & TOUCH) == 0:
				out.append(_check(false, "%s watches hexr_touch" % z.name,
						"Its collision mask must include layer 20 or no finger is ever felt.",
						func() -> void: _set_with_undo(ur, a, "collision_mask", a.collision_mask | TOUCH)))
	for ih in _all(root, "HexRInteractableHaptics"):
		var parent := ih.get_parent()
		var bound := parent != null and parent.has_signal("picked_up")
		if not bound:
			out.append({"ok": false, "warn": true, "title": "%s is on a pickable" % ih.name,
					"detail": "It follows an XR Tools pickable's grab. Without one, call set_interactor_state() "
					+ "from your toolkit's signals.", "fix": Callable()})
	out.append(_check(true, "%d HexR zone(s) in the scene" % zones, "", Callable()))
	return out


## Runs every fix the checks offer. Returns how many it ran.
static func fix_all(root: Node, ur: EditorUndoRedoManager) -> int:
	var n := 0
	for c in project_checks() + scene_checks(root, ur):
		var fix: Callable = c["fix"]
		if not c["ok"] and not c.get("warn", false) and fix.is_valid():
			fix.call()
			n += 1
	return n


static func _all(root: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	if Tools._is(root, cls):
		out.append(root)
	for n in root.find_children("*", "", true, false):
		if Tools._is(n, cls):
			out.append(n)
	return out


static func _check(ok: bool, title: String, detail: String, fix: Callable) -> Dictionary:
	return {"ok": ok, "title": title, "detail": detail, "fix": fix, "warn": false}


static func _save_setting(setting: String, value: Variant) -> void:
	ProjectSettings.set_setting(setting, value)
	ProjectSettings.save()


static func _set_with_undo(ur: EditorUndoRedoManager, obj: Object, prop: String, value: Variant) -> void:
	if ur == null:
		obj.set(prop, value)
		return
	ur.create_action("HexR: fix %s" % prop)
	ur.add_do_property(obj, prop, value)
	ur.add_undo_property(obj, prop, obj.get(prop))
	ur.commit_action()


static func _android_presets() -> Array:
	var cfg := ConfigFile.new()
	var out := []
	if cfg.load("res://export_presets.cfg") != OK:
		return out
	for section in cfg.get_sections():
		if section.ends_with(".options") or cfg.get_value(section, "platform", "") != "Android":
			continue
		var opts := {}
		if cfg.has_section(section + ".options"):
			for key in cfg.get_section_keys(section + ".options"):
				opts[key] = cfg.get_value(section + ".options", key)
		out.append({"name": cfg.get_value(section, "name", section), "options": opts})
	return out
