extends HexRTest
## The editor tools that can run without the editor: HexR > Migration > Upgrade 0.1 Scenes'
## rewrite of a scene file, and the update check's version comparison.

const Tools := preload("res://addons/hexr/editor/hexr_scene_tools.gd")
const Setup := preload("res://addons/hexr/editor/hexr_project_setup.gd")

const SCENE_0_1 := """[gd_scene load_steps=6 format=3 uid="uid://b0"]

[ext_resource type="Script" uid="uid://s1" path="res://addons/hexr/components/hexr_special_haptics.gd" id="1_sh"]
[ext_resource type="Script" uid="uid://s2" path="res://addons/hexr/components/hexr_grabbable.gd" id="2_gr"]
[ext_resource type="Script" uid="uid://s3" path="res://addons/hexr/components/hexr_physical_button.gd" id="3_pb"]
[ext_resource type="Script" uid="uid://s4" path="res://addons/hexr/components/hexr_usable.gd" id="4_us"]
[ext_resource type="Script" uid="uid://s5" path="res://addons/hexr/ui/hexr_floating_menu.gd" id="5_fm"]

[node name="Root" type="Node3D"]

[node name="Beat" type="Area3D" parent="."]
script = ExtResource("1_sh")
effect = 4
heart_beat = 1
haptic_strength = 0.6

[node name="Press" type="Area3D" parent="."]
script = ExtResource("1_sh")

[node name="Foam" type="Area3D" parent="."]
script = ExtResource("2_gr")
grab_type = 1

[node name="Button" type="Area3D" parent="."]
script = ExtResource("3_pb")
fingers = 3

[node name="Can" type="Area3D" parent="."]
script = ExtResource("4_us")

[node name="Menu" type="Node3D" parent="."]
script = ExtResource("5_fm")
scenes = PackedStringArray("res://a.tscn", "res://b.tscn")
"""


func _node(text: String, node_name: String) -> String:
	var at := text.find('[node name="%s"' % node_name)
	var end := text.find("\n[", at + 1)
	return text.substr(at, (end if end > 0 else text.length()) - at)


func test_upgrade_rewrites_a_0_1_scene() -> void:
	var listed := PackedStringArray()
	var out := Tools.upgrade_scene_text(SCENE_0_1, listed)
	assert_true(out.contains('path="res://addons/hexr/components/special_haptics.gd"'), "moved script path")
	var beat := _node(out, "Beat")
	assert_true(beat.contains("type_of_haptics = 4") and beat.contains("heartbeat = 1")
			and beat.contains("haptic_strength_value = 0.6"), "renamed: " + beat)
	assert_false(beat.contains("effect = "), "old name gone")
	assert_true(_node(out, "Press").contains("type_of_haptics = 1"), "0.1's default (custom haptics) written out")
	assert_true(_node(out, "Foam").contains("type_of_grab = 1"), "grab_type")
	var button := _node(out, "Button")
	assert_true(button.contains("thumb = true") and button.contains("index = true") and button.contains("palm = false"),
			"fingers bitmask as tick boxes: " + button)
	var can := _node(out, "Can")
	assert_true(can.contains("index_finger = true") and can.contains("little_finger = false"),
			"0.1's default (index only) written out: " + can)
	var menu := _node(out, "Menu")
	assert_true(menu.contains("show_scene_switcher = true") and not menu.contains("scenes = "), "menu scenes")
	assert_eq(listed, PackedStringArray(["res://a.tscn", "res://b.tscn"]), "scene list collected for hexr/scenes")


func test_upgrade_leaves_a_0_2_scene_alone() -> void:
	var once := Tools.upgrade_scene_text(SCENE_0_1, PackedStringArray())
	assert_eq(Tools.upgrade_scene_text(once, PackedStringArray()), once, "running it twice changes nothing")


func test_version_comparison() -> void:
	assert_true(Setup._newer("0.2.0", "0.1.0"), "0.2.0 > 0.1.0")
	assert_true(Setup._newer("0.10.0", "0.9.9"), "numeric, not text")
	assert_false(Setup._newer("0.2.0", "0.2.0"), "same")
	assert_false(Setup._newer("0.1.9", "0.2.0"), "older")
