extends Node3D
## A heart that beats harder when squeezed (the Unity tutorial's "Squeezing Heart"). Its
## heart-beat zone pulses the fingers holding it; a squeeze (the SpecialHaptics hand squeeze zone
## next to it) makes the beat stronger and quicker for a few seconds.

@export var beat_zone: SpecialHaptics
@export var squeeze_zone: SpecialHaptics
@export var mesh: Node3D

var _excited_until := 0.0
var _clock := 0.0


func _ready() -> void:
	if squeeze_zone:
		squeeze_zone.squeezed.connect(func(_hand: int) -> void: _excited_until = _clock + 3.0)


func _process(delta: float) -> void:
	_clock += delta
	var excited := _clock < _excited_until
	if beat_zone:
		beat_zone.heart_beat_pressure = 0.9 if excited else 0.5
		beat_zone.in_timer = 0.25 if excited else 0.4
		beat_zone.out_timer = 0.2 if excited else 0.3
	if mesh:
		var period := 0.45 if excited else 0.7
		var s := 1.0 + 0.08 * maxf(0.0, sin(_clock * TAU / period))
		mesh.scale = Vector3.ONE * s
