class_name HexRXRToolsBinding
extends RefCounted
## Connects a Godot XR Tools pickable to a [HexRInteractableHaptics]. Duck-typed: the addon does
## not need XR Tools installed, and nothing here runs unless the object has its signals.
##
## Picking up marks the hand as grabbing on its Pressure Controller (opening the hand-near check)
## and reports "selecting"; a highlight reports "hovering" for the hand of the nearest pickup.

var _pickable: Object
var _sink: HexRInteractableHaptics
var _held_by := -1


## Binds [param start] (or its nearest ancestor with a picked_up signal). Returns null if
## there is nothing to bind to.
static func bind(start: Node, sink: HexRInteractableHaptics) -> HexRXRToolsBinding:
	var n := start
	while n != null and not (n.has_signal("picked_up") and n.has_signal("dropped")):
		n = n.get_parent()
		if n is Window:
			return null
	if n == null:
		return null
	var b := HexRXRToolsBinding.new()
	b._pickable = n
	b._sink = sink
	n.connect("picked_up", b._on_picked_up)
	n.connect("dropped", b._on_dropped)
	if n.has_signal("highlight_updated"):
		n.connect("highlight_updated", b._on_highlight_updated)
	return b


func describe() -> String:
	return "XR Tools pickable %s" % (_pickable as Node).name if is_instance_valid(_pickable) else "nothing"


func _on_picked_up(_p: Variant) -> void:
	_held_by = _hand_of_holder()
	var c := _controller(_held_by)
	if c:
		c.hand_grabbing_check(true)
	_sink.set_interactor_state(&"xr_tools_hold", _held_by, false, true)


func _on_dropped(_p: Variant) -> void:
	var c := _controller(_held_by)
	if c:
		c.hand_grabbing_check(false)
	_sink.clear_interactor(&"xr_tools_hold")
	_held_by = -1


func _on_highlight_updated(_p: Variant, enable: bool) -> void:
	_sink.set_interactor_state(&"xr_tools_hover", -1, enable, false)


## Which hand holds the pickable: from its controller's tracker name ("left_hand"...).
func _hand_of_holder() -> int:
	var controller: Variant = null
	if _pickable.has_method("get_picked_up_by_controller"):
		controller = _pickable.call("get_picked_up_by_controller")
	if controller == null:
		controller = _pickable.get("by_controller")
	if controller == null:
		var by: Variant = _pickable.get("picked_up_by")
		var n := by as Node
		while n != null and not (n is XRController3D):
			n = n.get_parent()
		controller = n
	if controller is XRController3D:
		var tracker := String((controller as XRController3D).tracker)
		if tracker.contains("left"):
			return HaptGloveHandler.HandType.LEFT
		if tracker.contains("right"):
			return HaptGloveHandler.HandType.RIGHT
	return -1


func _controller(hand: int) -> PressureTrackerMain:
	if hand < 0:
		return null
	var hub := HexRManager.get_instance()
	return hub.controller(hand) if hub else null
