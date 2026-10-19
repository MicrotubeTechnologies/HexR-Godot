class_name HexRFingerUseTracking
extends RefCounted
## How curled each finger is, from 0 (fully curled) to 1 (fully extended). Port of the Unity
## package's FingerUseTracking: each finger's tip-to-knuckle distance, normalised against the
## smallest and largest seen so far, so it calibrates itself as the wearer moves their hand.
## Reach it as [code]HexR.tracked_hand(hand).finger_use[/code].

var thumb_use := 0.0
var index_use := 0.0
var middle_use := 0.0
var ring_use := 0.0
var little_use := 0.0

var _min := PackedFloat32Array([INF, INF, INF, INF, INF])
var _max := PackedFloat32Array([-INF, -INF, -INF, -INF, -INF])


## Feeds this frame's tip-to-knuckle distances, Thumb..Pinky.
func update(distances: PackedFloat32Array) -> void:
	var uses := PackedFloat32Array([0, 0, 0, 0, 0])
	for i in 5:
		var d := distances[i]
		_max[i] = maxf(_max[i], d)
		_min[i] = minf(_min[i], d)
		uses[i] = 0.0 if is_equal_approx(_max[i], _min[i]) else (d - _min[i]) / (_max[i] - _min[i])
	thumb_use = uses[0]
	index_use = uses[1]
	middle_use = uses[2]
	ring_use = uses[3]
	little_use = uses[4]


## The use of [param finger] (Thumb..Pinky); the palm has none.
func get_use(finger: int) -> float:
	match finger:
		HexRTypes.Finger.THUMB:
			return thumb_use
		HexRTypes.Finger.INDEX:
			return index_use
		HexRTypes.Finger.MIDDLE:
			return middle_use
		HexRTypes.Finger.RING:
			return ring_use
		HexRTypes.Finger.PINKY:
			return little_use
	return 0.0


## Every finger extended: what releases a [HexRGrabbable].
func is_hand_open() -> bool:
	return index_use > 0.95 and middle_use > 0.95 and ring_use > 0.95 and thumb_use > 0.9 and little_use > 0.95


func reset_calibration() -> void:
	_min = PackedFloat32Array([INF, INF, INF, INF, INF])
	_max = PackedFloat32Array([-INF, -INF, -INF, -INF, -INF])
