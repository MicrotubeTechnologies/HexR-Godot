extends OmniLight3D
## A flickering torch flame light.

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	light_energy = 1.6 + 0.35 * sin(_t * 23.0) + 0.2 * sin(_t * 37.0 + 1.3)
