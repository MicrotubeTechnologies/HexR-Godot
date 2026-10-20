@tool
extends RefCounted
## What the HexR menu's items do (port of the Unity package's HexRMenu): add the rig, the menu and
## HexR Remote to the open scene, build a demo scene, import the tutorial content, and upgrade
## scenes saved with HexR 0.1.

const DEMO_PATH := "res://hexr_demo.tscn"
const SAMPLES_FROM := "res://addons/hexr/samples/tutorial_content/"
const SAMPLES_TO := "res://hexr_samples/tutorial_content/"


# -- Create HexR Rig ------------------------------------------------------------------------

## Adds an XROrigin3D with a camera if the scene has none, and the rig under it: both tracked
## hands and both Pressure Controllers as nodes you can see and tune.
static func create_rig(plugin: EditorPlugin) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("open a 3D scene first.")
		return
	var existing := _find(root, "HexRRig")
	if existing:
		_say("this scene already has a HexR rig (%s)." % root.get_path_to(existing))
		_select(existing)
		return
	var origin := _find(root, "XROrigin3D") as XROrigin3D
	var new_origin := origin == null
	if new_origin:
		origin = _new_origin()
	var rig := new_rig()
	var ur := plugin.get_undo_redo()
	ur.create_action("Create HexR Rig")
	var added: Node = rig
	var parent: Node = origin
	if new_origin:
		origin.add_child(rig)
		added = origin
		parent = root
	ur.add_do_method(parent, "add_child", added, true)
	ur.add_do_reference(added)
	ur.add_undo_method(parent, "remove_child", added)
	_own_in(ur, added, root)
	ur.commit_action()
	_select(rig)
	_say("rig added. Next: HexR > Add HexR Menu, then HexR > Troubleshoot > Validate Scene Setup.")


## The rig, built off the tree so its own set-up never runs in the editor: Unity's "HexR Main".
static func new_rig() -> HexRRig:
	var rig := HexRRig.new()
	rig.name = "HexR Main"
	for hand in [HaptGloveHandler.HandType.LEFT, HaptGloveHandler.HandType.RIGHT]:
		var side := HexRTypes.hand_name(hand)
		var h := HexRTrackedHand.new()
		h.name = side + "Hand"
		h.hand_type = hand
		rig.add_child(h)
		var c := PressureTrackerMain.new()
		c.name = side + " Pressure Controller"
		c.hand_type = hand
		rig.add_child(c)
	return rig


static func _new_origin() -> XROrigin3D:
	var origin := XROrigin3D.new()
	origin.name = "XROrigin3D"
	var cam := XRCamera3D.new()
	cam.name = "XRCamera3D"
	cam.position = Vector3(0, 1.6, 0)
	origin.add_child(cam)
	return origin


# -- Add HexR Menu / Add HexR Remote --------------------------------------------------------

## The HexR menu, placed as Unity places it: in front of the rig and to the left, at chest height,
## facing the rig. SCENES and DEMOS start off, as Unity's menu item leaves them.
static func add_menu(plugin: EditorPlugin) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("open a 3D scene first.")
		return
	var existing := _find(root, "HexRFloatingMenu")
	if existing:
		_say("this scene already has a HexR menu.")
		_select(existing)
		return
	var menu := HexRFloatingMenu.new()
	menu.name = "HexR Floating Menu"
	menu.show_scene_switcher = false
	menu.show_demo_groups = false
	menu.transform = menu_placement(_find(root, "XROrigin3D") as Node3D, menu)
	_add(plugin, root, root, menu, "Add HexR Menu")
	_say("menu added in front of the rig, to the left. List your scenes in Project Settings > HexR > Scenes "
			+ "and tick Show Scene Switcher to switch between them from the menu.")


## Unity's placement relative to the rig: forward, to the side, and at 1.6 m plus the height offset.
static func menu_placement(origin: Node3D, menu: HexRFloatingMenu) -> Transform3D:
	var base := origin.global_transform if origin and origin.is_inside_tree() else Transform3D()
	var forward := -base.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var pos := base.origin + forward * menu.spawn_distance + right * menu.spawn_side_offset \
			+ Vector3.UP * (1.6 + menu.spawn_height_offset)
	var facing := pos - base.origin
	facing.y = 0.0
	# The quad's front (+Z) faces the rig.
	return Transform3D(Basis.looking_at(facing.normalized(), Vector3.UP), pos)


static func add_remote(plugin: EditorPlugin) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("open a 3D scene first.")
		return
	var existing := _find(root, "HexRRemote")
	if existing:
		_say("this scene already has HexR Remote.")
		_select(existing)
		return
	var remote := HexRRemote.new()
	remote.name = "HexR Remote"
	_add(plugin, root, root, remote, "Add HexR Remote")
	_say("HexR Remote added. One is enough: it outlives scene changes. Phones on the same Wi-Fi find "
			+ "the app in the HexR Companion's Headsets tab.")


# -- Create Demo Scene ----------------------------------------------------------------------

## Unity's demo scene: a floor, a cube to grab with the palm (with a ProximityCheck), and a haptic
## zone, plus a rig and the menu. Saved as res://hexr_demo.tscn and opened.
static func create_demo_scene() -> void:
	var root := Node3D.new()
	root.name = "HexR Demo"
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var plane := MeshInstance3D.new()
	plane.name = "Mesh"
	plane.mesh = PlaneMesh.new()
	(plane.mesh as PlaneMesh).size = Vector2(4, 4)
	floor_body.add_child(plane)
	floor_body.add_child(_shape(BoxShape3D.new(), Vector3(4, 0.02, 4), Vector3(0, -0.01, 0)))
	root.add_child(floor_body)

	var origin := _new_origin()
	origin.add_child(new_rig())
	root.add_child(origin)

	var menu := HexRFloatingMenu.new()
	menu.name = "HexR Floating Menu"
	menu.show_scene_switcher = false
	menu.show_demo_groups = false
	root.add_child(menu)
	menu.transform = menu_placement(null, menu)

	# A cube held with the palm, floating at chest height until grabbed.
	var cube := RigidBody3D.new()
	cube.name = "Grabbable Cube"
	cube.position = Vector3(-0.12, 1.0, -0.35)
	cube.gravity_scale = 0.0
	var cube_mesh := MeshInstance3D.new()
	cube_mesh.name = "Mesh"
	cube_mesh.mesh = BoxMesh.new()
	(cube_mesh.mesh as BoxMesh).size = Vector3.ONE * 0.07
	cube.add_child(cube_mesh)
	cube.add_child(_shape(BoxShape3D.new(), Vector3.ONE * 0.07))
	var grab := HexRGrabbable.new()
	grab.name = "HexRGrabbable"
	grab.type_of_grab = HexRGrabbable.Options.PALM_GRAB
	grab.haptic_strength = 20.0
	grab.add_child(_shape(BoxShape3D.new(), Vector3.ONE * 0.09))
	cube.add_child(grab)
	var near := ProximityCheck.new()
	near.name = "Proximity Check"
	near.add_child(_shape(BoxShape3D.new(), Vector3.ONE * 0.175))
	cube.add_child(near)
	root.add_child(cube)

	# A sphere that presses whichever fingers are inside it.
	var zone := SpecialHaptics.new()
	zone.name = "Haptic Zone"
	zone.position = Vector3(0.12, 1.0, -0.35)
	zone.type_of_haptics = SpecialHaptics.Options.CUSTOM_HAPTICS
	zone.haptic_pressure = 30.0
	var ball := MeshInstance3D.new()
	ball.name = "Mesh"
	ball.mesh = SphereMesh.new()
	(ball.mesh as SphereMesh).radius = 0.06
	(ball.mesh as SphereMesh).height = 0.12
	zone.add_child(ball)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.06
	zone.add_child(_shape(sphere, Vector3.ZERO))
	root.add_child(zone)

	_own(root, root)
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	var path := _free_path(DEMO_PATH)
	var err := ResourceSaver.save(scene, path)
	if err != OK:
		_say("could not save the demo scene (%s)." % error_string(err))
		return
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	_say("demo scene saved as %s and opened. Next: HexR > Troubleshoot > Validate Scene Setup, then run it on a "
			% path + "headset with your hands, or on Windows with the HexR Tools dock's Haptics Tester.")


static func _shape(shape: Shape3D, size: Vector3, at := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	if shape is BoxShape3D:
		(shape as BoxShape3D).size = size
	cs.shape = shape
	cs.position = at
	return cs


static func _free_path(path: String) -> String:
	if not ResourceLoader.exists(path):
		return path
	var i := 2
	while ResourceLoader.exists(path.get_basename() + "_%d.tscn" % i):
		i += 1
	return path.get_basename() + "_%d.tscn" % i


# -- Import Tutorial Content ----------------------------------------------------------------

## Copies the tutorial scripts into res://hexr_samples/, as Unity's Package Manager imports a
## package sample into Assets/Samples.
static func import_tutorial_content() -> void:
	DirAccess.make_dir_recursive_absolute(SAMPLES_TO)
	var copied := 0
	for f in DirAccess.get_files_at(SAMPLES_FROM):
		if f.begins_with("."):
			continue
		if DirAccess.copy_absolute(SAMPLES_FROM + f, SAMPLES_TO + f) == OK:
			copied += 1
	EditorInterface.get_resource_filesystem().scan()
	_say("imported %d files into %s (see its README)." % [copied, SAMPLES_TO])


# -- Migration: Upgrade 0.1 scenes ----------------------------------------------------------

# Scripts HexR 0.1 had under other names: old path -> new path.
const MOVED_0_1 := {
	"res://addons/hexr/core/hexr_glove.gd": "res://addons/hexr/core/hapt_glove_handler.gd",
	"res://addons/hexr/core/hexr_haptics.gd": "res://addons/hexr/core/haptics.gd",
	"res://addons/hexr/hands/hexr_touch_point.gd": "res://addons/hexr/hands/haptic_finger_trigger.gd",
	"res://addons/hexr/haptics/hexr_pressure_controller.gd": "res://addons/hexr/haptics/pressure_tracker_main.gd",
	"res://addons/hexr/hands/hexr_finger_use_tracking.gd": "res://addons/hexr/hands/finger_use_tracking.gd",
	"res://addons/hexr/components/hexr_proximity_check.gd": "res://addons/hexr/components/proximity_check.gd",
	"res://addons/hexr/components/hexr_special_haptics.gd": "res://addons/hexr/components/special_haptics.gd",
}
# Property renames per script (by the script's 0.2 file name).
const RENAMED_0_1 := {
	"special_haptics.gd": {"effect": "type_of_haptics", "haptic_strength": "haptic_strength_value",
			"vibration_frequency": "vibrations_frequency_value", "heart_beat": "heartbeat"},
	"hexr_grabbable.gd": {"grab_type": "type_of_grab", "target": "the_object"},
	"haptic_finger_trigger.gd": {"hand": "hand_type", "finger": "finger_type"},
	"pressure_tracker_main.gd": {"hand": "hand_type"},
	"hexr_tracked_hand.gd": {"hand": "hand_type"},
}
const BUTTON_FINGERS := ["thumb", "index", "middle", "ring", "pinky", "palm"]
const USABLE_FINGERS := ["thumb", "index_finger", "middle_finger", "ring_finger", "little_finger"]


## Rewrites every scene in the project (outside addons/) that was saved with HexR 0.1, so it opens
## with HexR 0.2's names: moved scripts, renamed properties, the per-finger tick boxes, and the
## defaults that changed. Run it before opening those scenes: the editor drops properties it does
## not recognise when it saves. Returns how many scenes changed.
static func upgrade_0_1_scenes() -> int:
	var changed := 0
	var scenes := PackedStringArray()
	var listed := PackedStringArray()
	for path in _scene_files("res://"):
		var text := FileAccess.get_file_as_string(path)
		var out := upgrade_scene_text(text, listed)
		if out != text:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(out)
			f.close()
			changed += 1
			scenes.append(path)
	if not listed.is_empty() and PackedStringArray(ProjectSettings.get_setting("hexr/scenes", PackedStringArray())).is_empty():
		ProjectSettings.set_setting("hexr/scenes", listed)
		ProjectSettings.save()
	EditorInterface.get_resource_filesystem().scan()
	_say("upgraded %d scene(s) from HexR 0.1%s." % [changed, (": " + ", ".join(scenes)) if changed else ""])
	return changed


## One scene file's text, upgraded. Scene lists found on 0.1 menus and remotes are added to
## [param scene_list] (the 0.2 project setting hexr/scenes).
static func upgrade_scene_text(text: String, scene_list: PackedStringArray) -> String:
	for old in MOVED_0_1:
		text = text.replace('path="%s"' % old, 'path="%s"' % MOVED_0_1[old])
	# Which ext_resource id is which HexR script.
	var script_of := {}
	var rx := RegEx.create_from_string('\\[ext_resource type="Script"[^\\]]*path="res://addons/hexr/[^"]*/([a-z_]+\\.gd)"[^\\]]*id="([^"]+)"\\]')
	for m in rx.search_all(text):
		script_of[m.get_string(2)] = m.get_string(1)
	var lines := text.split("\n")
	var out := PackedStringArray()
	var i := 0
	while i < lines.size():
		var line := lines[i]
		out.append(line)
		i += 1
		if not line.begins_with("[node "):
			continue
		# The node's properties, up to the next section.
		var props := PackedStringArray()
		while i < lines.size() and not lines[i].begins_with("["):
			props.append(lines[i])
			i += 1
		var script := ""
		for p in props:
			var sm := RegEx.create_from_string('^script = ExtResource\\("([^"]+)"\\)').search(p)
			if sm and script_of.has(sm.get_string(1)):
				script = script_of[sm.get_string(1)]
		out.append_array(_upgrade_node(script, props, scene_list))
	return "\n".join(out)


static func _upgrade_node(script: String, props: PackedStringArray, scene_list: PackedStringArray) -> PackedStringArray:
	if script.is_empty():
		return props
	var renames: Dictionary = RENAMED_0_1.get(script, {})
	var out := PackedStringArray()
	var seen := {}
	for p in props:
		var key := p.get_slice(" = ", 0)
		var value := p.get_slice(" = ", 1) if p.contains(" = ") else ""
		seen[key] = true
		if renames.has(key):
			out.append("%s = %s" % [renames[key], value])
		elif key == "fingers" and script in ["hexr_physical_button.gd", "hexr_usable.gd"]:
			out.append_array(_finger_bools(int(value), BUTTON_FINGERS if script == "hexr_physical_button.gd" else USABLE_FINGERS))
		elif key == "scenes" and script in ["hexr_floating_menu.gd", "hexr_remote.gd"]:
			for s in RegEx.create_from_string('"([^"]+)"').search_all(value):
				if not scene_list.has(s.get_string(1)):
					scene_list.append(s.get_string(1))
			if script == "hexr_floating_menu.gd" and value.contains('"'):
				out.append("show_scene_switcher = true")
		else:
			out.append(p)
	# Defaults that changed: 0.1 did not save them, so say what they were.
	var insert_at := out.size()
	while insert_at > 0 and out[insert_at - 1].strip_edges().is_empty():
		insert_at -= 1
	if script == "special_haptics.gd" and not seen.has("effect") and not seen.has("type_of_haptics"):
		out.insert(insert_at, "type_of_haptics = 1")  # 0.1's default was custom haptics
	if script == "hexr_usable.gd" and not seen.has("fingers") and not seen.has("thumb"):
		var bools := _finger_bools(2, USABLE_FINGERS)  # 0.1's default was the index finger only
		for b in range(bools.size() - 1, -1, -1):
			out.insert(insert_at, bools[b])
	return out


static func _finger_bools(mask: int, names: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for f in names.size():
		out.append("%s = %s" % [names[f], "true" if mask & (1 << f) else "false"])
	return out


static func _scene_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or (dir == "res://" and d in ["addons", "android"]):
			continue
		out.append_array(_scene_files(dir.path_join(d)))
	return out


## Scripts an unzip-over install of 0.2 leaves behind from 0.1.
static func stale_0_1_files() -> PackedStringArray:
	var out := PackedStringArray()
	for old in MOVED_0_1:
		if FileAccess.file_exists(old):
			out.append(old)
	return out


static func delete_stale_0_1_files() -> void:
	for old in stale_0_1_files():
		DirAccess.remove_absolute(old)
		if FileAccess.file_exists(old + ".uid"):
			DirAccess.remove_absolute(old + ".uid")
	EditorInterface.get_resource_filesystem().scan()


# -- helpers ----------------------------------------------------------------------------------

static func _add(plugin: EditorPlugin, root: Node, parent: Node, node: Node, action: String) -> void:
	var ur := plugin.get_undo_redo()
	ur.create_action(action)
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	_own_in(ur, node, root)
	ur.commit_action()
	_select(node)


# The undo step's set_owner calls for a subtree, so the scene saves all of it.
static func _own_in(ur: EditorUndoRedoManager, node: Node, owner: Node) -> void:
	ur.add_do_method(node, "set_owner", owner)
	for c in node.find_children("*", "", true, false):
		ur.add_do_method(c, "set_owner", owner)


## Gives [param node] and everything under it to [param owner], so the scene saves them.
static func _own(node: Node, owner: Node) -> void:
	if node != owner:
		node.owner = owner
	for c in node.get_children():
		_own(c, owner)


static func _find(root: Node, cls: String) -> Node:
	if _is(root, cls):
		return root
	for n in root.find_children("*", "", true, false):
		if _is(n, cls):
			return n
	return null


static func _is(n: Node, cls: String) -> bool:
	if n.is_class(cls):
		return true
	var s: Script = n.get_script()
	while s:
		if s.get_global_name() == cls:
			return true
		s = s.get_base_script()
	return false


## Selects [param node] and shows it in the Inspector (Unity's select-and-ping).
static func _select(node: Node) -> void:
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(node)
	EditorInterface.edit_node(node)


static func _say(text: String) -> void:
	print_rich("[color=#ff6a2b][b]HexR[/b][/color]: " + text)
