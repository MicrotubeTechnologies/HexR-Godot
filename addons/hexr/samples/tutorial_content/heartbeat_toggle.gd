extends Node
## Switches every heart-beat zone in the scene between a regular and an irregular beat, and
## shows which on a label. Wire a HexRPhysicalButton's "pressed" signal to toggle(); it is also a
## HexR Remote command, so the phone can do it too.

@export var label: Label3D


func _ready() -> void:
	HexRRemote.register_command("toggle_heartbeat", "Toggle heartbeat", toggle)
	_show()


func _exit_tree() -> void:
	HexRRemote.unregister_command("toggle_heartbeat")


func toggle() -> void:
	for zone in _heart_beat_zones():
		zone.toggle_heart_regularity()
	_show()


func _heart_beat_zones() -> Array[SpecialHaptics]:
	var out: Array[SpecialHaptics] = []
	for n in get_tree().current_scene.find_children("*", "SpecialHaptics", true, false):
		var zone := n as SpecialHaptics
		if zone and zone.type_of_haptics == SpecialHaptics.Options.HEART_BEAT_EFFECT:
			out.append(zone)
	return out


func _show() -> void:
	if label == null:
		return
	var irregular := false
	for zone in _heart_beat_zones():
		irregular = zone.heartbeat == SpecialHaptics.HeartBeat.IRREGULAR
	label.text = "Pulse: " + ("IRREGULAR" if irregular else "regular")
