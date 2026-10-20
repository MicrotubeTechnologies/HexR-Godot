extends MeshInstance3D
## A bulb the physical button switches. Wire a HexRPhysicalButton's "pressed" signal to toggle().

@export var on_color := Color("#ffcf66")
@export var on := false:
	set(v):
		on = v
		_apply()

var _light: OmniLight3D


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.omni_range = 1.2
	_light.light_color = on_color
	add_child(_light)
	_apply()


func toggle() -> void:
	on = not on


func _apply() -> void:
	if not is_inside_tree():
		return
	var mat := material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		material_override = mat
	mat.albedo_color = on_color if on else Color(0.85, 0.85, 0.8, 0.6)
	mat.emission_enabled = on
	mat.emission = on_color
	mat.emission_energy_multiplier = 3.0
	if _light:
		_light.visible = on
