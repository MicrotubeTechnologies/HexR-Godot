@tool
extends EditorInspectorPlugin
## The Unity package's custom inspectors, for Godot: ProximityCheck's Auto Set Up, SpecialHaptics
## showing only the settings its effect uses, and HexRInteractableHaptics saying what it follows.

const TOUCH := 1 << 19
# The settings each SpecialHaptics effect reads; the others are hidden.
const EFFECT_SETTINGS := {
	SpecialHaptics.Options.CUSTOM_VIBRATIONS: ["haptic_strength_value", "vibrations_frequency_value"],
	SpecialHaptics.Options.CUSTOM_HAPTICS: ["haptic_pressure"],
	SpecialHaptics.Options.FOUNTAIN_EFFECT: [],
	SpecialHaptics.Options.RAIN_DROP_EFFECT: ["haptic_strength_value"],
	SpecialHaptics.Options.HEART_BEAT_EFFECT: ["heart_beat_pressure", "heartbeat", "in_timer", "out_timer", "include_palm"],
	SpecialHaptics.Options.HAND_SQUEEZE_EFFECT: ["squeeze_tightness"],
}
const ALL_EFFECT_SETTINGS := ["haptic_strength_value", "vibrations_frequency_value", "haptic_pressure",
	"heart_beat_pressure", "heartbeat", "in_timer", "out_timer", "include_palm", "squeeze_tightness"]

var plugin: EditorPlugin


func _init() -> void:
	EditorInterface.get_inspector().property_edited.connect(_on_property_edited)


func _can_handle(object: Object) -> bool:
	return object is ProximityCheck or object is SpecialHaptics or object is HexRInteractableHaptics


func _parse_begin(object: Object) -> void:
	if object is ProximityCheck:
		var box := VBoxContainer.new()
		box.add_child(_note("Marks a hand as near while any of its fingertips or palm is inside, which opens "
				+ "the hand-near check on that hand's Pressure Controller. Wrap it round the space a hand has to "
				+ "be in."))
		var b := Button.new()
		b.text = "Auto Set Up"
		b.tooltip_text = "Adds a box collision shape if there is none and makes the zone watch the hexr_touch layer."
		b.pressed.connect(_auto_set_up.bind(object))
		box.add_child(b)
		add_custom_control(box)
	elif object is HexRInteractableHaptics:
		var parent := (object as Node).get_parent()
		if parent and parent.has_signal("picked_up"):
			add_custom_control(_note("Follows the XR Tools pickable it is on (%s): the chosen fingers press while "
					% parent.name + "it is held."))
		else:
			add_custom_control(_note("No XR Tools pickable above it. Put it on one, or call set_interactor_state() "
					+ "from your interaction toolkit's signals."))


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String,
		_usage: int, _wide: bool) -> bool:
	if object is SpecialHaptics and name in ALL_EFFECT_SETTINGS:
		var effect: int = object.get("type_of_haptics")
		return not name in EFFECT_SETTINGS.get(effect, [])
	return false


func _on_property_edited(property: String) -> void:
	if property == "type_of_haptics":
		var edited := EditorInterface.get_inspector().get_edited_object()
		if edited:
			edited.notify_property_list_changed()


func _auto_set_up(zone: Area3D) -> void:
	var ur := plugin.get_undo_redo()
	ur.create_action("ProximityCheck: Auto Set Up")
	var has_shape := false
	for c in zone.get_children():
		if c is CollisionShape3D:
			has_shape = true
	if not has_shape:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * 0.3
		cs.shape = box
		ur.add_do_method(zone, "add_child", cs, true)
		ur.add_do_method(cs, "set_owner", EditorInterface.get_edited_scene_root())
		ur.add_do_reference(cs)
		ur.add_undo_method(zone, "remove_child", cs)
	ur.add_do_property(zone, "collision_mask", zone.collision_mask | TOUCH)
	ur.add_undo_property(zone, "collision_mask", zone.collision_mask)
	ur.commit_action()


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	l.add_theme_color_override("font_color", Color("#8f8f8f"))
	return l
