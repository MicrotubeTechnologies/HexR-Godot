class_name HexRRig
extends Node3D
## The HexR rig for a scene: both [HexRTrackedHand]s and both [PressureTrackerMain]s.
## Put it under your [XROrigin3D]. Missing parts are created when the scene runs, so an empty
## HexRRig node is a complete rig; Project > Tools > HexR > Create HexR Rig adds them as nodes you
## can see and tune.


func _ready() -> void:
	for hand in [HaptGloveHandler.HandType.LEFT, HaptGloveHandler.HandType.RIGHT]:
		var side := HexRTypes.hand_name(hand)
		if find_hand(hand) == null:
			var h := HexRTrackedHand.new()
			h.name = side + "Hand"
			h.hand = hand
			add_child(h)
		if find_controller(hand) == null:
			var c := PressureTrackerMain.new()
			c.name = side + "PressureController"
			c.hand = hand
			add_child(c)


func find_hand(hand: int) -> HexRTrackedHand:
	for c in get_children():
		if c is HexRTrackedHand and c.hand == hand:
			return c
	return null


func find_controller(hand: int) -> PressureTrackerMain:
	for c in get_children():
		if c is PressureTrackerMain and c.hand == hand:
			return c
	return null
