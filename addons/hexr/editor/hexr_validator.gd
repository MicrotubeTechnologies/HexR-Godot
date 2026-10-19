@tool
extends RefCounted
## What a HexR project and scene need, each as a check the dock shows with a Fix button where one
## can be fixed automatically. Port of the Unity package's HexRSetupValidator, for Godot.


## Returns [{"ok": bool, "title": String, "detail": String, "fix": Callable}].
static func project_checks() -> Array:
	var out := []
	out.append(_check(ProjectSettings.has_setting("autoload/HexR"), "HexR autoload",
			"The HexR plugin registers it when enabled. Disable and re-enable the plugin to add it.", Callable()))
	out.append(_check(bool(ProjectSettings.get_setting("xr/openxr/enabled", false)), "OpenXR enabled",
			"Project Settings > XR > OpenXR > Enabled.", func() -> void: _save_setting("xr/openxr/enabled", true)))
	out.append(_check(bool(ProjectSettings.get_setting("xr/shaders/enabled", false)), "XR shaders enabled",
			"Project Settings > XR > Shaders > Enabled.", func() -> void: _save_setting("xr/shaders/enabled", true)))
	out.append(_check(bool(ProjectSettings.get_setting("xr/openxr/extensions/hand_tracking", false)), "Hand tracking",
			"Touch points follow the OpenXR hand tracker.", func() -> void: _save_setting("xr/openxr/extensions/hand_tracking", true)))
	out.append(_check(String(ProjectSettings.get_setting("layer_names/3d_physics/layer_20", "")) == "hexr_touch",
			"Physics layer 20 named hexr_touch", "Touch points live on layer 20; zones watch it.",
			func() -> void: _save_setting("layer_names/3d_physics/layer_20", "hexr_touch")))
	out.append(_check(FileAccess.file_exists("res://addons/hexr/android/bin/hexr-ble-release.aar"), "Android Bluetooth plugin",
			"addons/hexr/android/bin/*.aar ships in the release zip. Reinstall the addon.", Callable()))
	if OS.get_name() == "Windows":
		out.append(_check(FileAccess.file_exists("res://addons/hexr/bin/windows/hexr_ble_win.windows.template_debug.x86_64.dll"),
				"Windows Bluetooth extension", "addons/hexr/bin/windows/*.dll ships in the release zip. Without it the editor uses simulated gloves.", Callable()))
	var android := _android_preset()
	if android != null:
		out.append(_check(bool(android.get_value(android.get_meta("options"), "gradle_build/use_gradle_build", false)),
				"Android preset uses Gradle build", "Export > Android > Use Gradle Build. Plugins need it.", Callable()))
	return out


## Checks for the scene open in the editor.
static func scene_checks(root: Node) -> Array:
	var out := []
	if root == null:
		return out
	var origins := root.find_children("*", "XROrigin3D", true, false)
	out.append(_check(not origins.is_empty(), "XROrigin3D in the scene", "Hands are tracked relative to it.", Callable()))
	var rigs := root.find_children("*", "HexRRig", true, false)
	if rigs.is_empty():
		for n in root.find_children("*", "", true, false):
			if n.get_script() and n.get_script().resource_path.ends_with("hexr_rig.gd"):
				rigs.append(n)
	var has_rig := not rigs.is_empty() or _has_instance_with(root, "HexRRig")
	out.append(_check(has_rig, "HexR rig", "Project > Tools > HexR > Create HexR Rig.", Callable()))
	var zones := 0
	for cls in ["HexRSpecialHaptics", "HexRGrabbable", "HexRPhysicalButton", "HexRProximityCheck", "HexRUsable"]:
		for z in root.find_children("*", cls, true, false):
			zones += 1
			var a := z as Area3D
			if a and (a.collision_mask & (1 << 19)) == 0:
				out.append(_check(false, "%s watches hexr_touch" % z.name,
						"Its collision mask must include layer 20 or no finger is ever felt.",
						func() -> void: a.collision_mask |= 1 << 19))
	out.append(_check(true, "%d HexR zone(s) in the scene" % zones, "", Callable()))
	return out


static func _has_instance_with(root: Node, cls: String) -> bool:
	for n in root.find_children("*", "Node", true, false):
		var script: Script = n.get_script()
		if script and script.get_global_name() == cls:
			return true
	return false


static func _check(ok: bool, title: String, detail: String, fix: Callable) -> Dictionary:
	return {"ok": ok, "title": title, "detail": detail, "fix": fix}


static func _save_setting(setting: String, value: Variant) -> void:
	ProjectSettings.set_setting(setting, value)
	ProjectSettings.save()


static func _android_preset() -> ConfigFile:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return null
	for section in cfg.get_sections():
		if section.ends_with(".options"):
			continue
		if cfg.get_value(section, "platform", "") == "Android":
			cfg.set_meta("options", section + ".options")
			return cfg
	return null
