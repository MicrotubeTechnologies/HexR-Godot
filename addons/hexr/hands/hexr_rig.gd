class_name HexRRig
extends Node3D
## The HexR rig for a scene: both [HexRTrackedHand]s and both [PressureTrackerMain]s.
## Put it under your [XROrigin3D]. Missing parts are created when the scene runs, so an empty
## HexRRig node is a complete rig; HexR > Create HexR Rig adds them as nodes you can see and tune.
## It is the Godot side of the Unity package's "HexR Main" rig, and the node is named that.

## Switch the viewport to the headset when the scene starts, as Unity's XR Plug-in Management
## does. Harmless next to another start-up script such as XR Tools' StartXR.
@export var start_xr := true


func _ready() -> void:
	# Created by an editor tool, it is only being set up: it runs in the game.
	if Engine.is_editor_hint():
		return
	for hand in [HaptGloveHandler.HandType.LEFT, HaptGloveHandler.HandType.RIGHT]:
		var side := HexRTypes.hand_name(hand)
		if find_hand(hand) == null:
			var h := HexRTrackedHand.new()
			h.name = side + "Hand"
			h.hand_type = hand
			add_child(h)
		if find_controller(hand) == null:
			var c := PressureTrackerMain.new()
			c.name = side + "PressureController"
			c.hand_type = hand
			add_child(c)
	if start_xr:
		_start_xr.call_deferred()


func find_hand(hand: int) -> HexRTrackedHand:
	for c in get_children():
		if c is HexRTrackedHand and c.hand_type == hand:
			return c
	return null


func find_controller(hand: int) -> PressureTrackerMain:
	for c in get_children():
		if c is PressureTrackerMain and c.hand_type == hand:
			return c
	return null


func _start_xr() -> void:
	var xr := XRServer.find_interface("OpenXR")
	# Godot initialises OpenXR at start-up when Project Settings > XR > OpenXR is on; on a computer
	# without a headset runtime it stays off, and the scene runs flat.
	if xr == null or not xr.is_initialized():
		return
	var vp := get_viewport()
	if not vp.use_xr:
		vp.use_xr = true
		# The headset paces frames; vsync on the desktop window would hold them back.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

