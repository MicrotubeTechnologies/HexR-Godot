class_name HexRInteractableHaptics
extends Node
## Haptics for an object picked up through an interaction toolkit (port of the Unity package's
## HexRInteractableHaptics). The recommended way to make an existing grabbable object felt.
##
## Make it a child of a Godot XR Tools [code]XRToolsPickable[/code] and it binds itself: the
## chosen fingers press while the object is held (or hovered, see [member fire_on]). For other
## toolkits, call [method set_interactor_state] from their signals.
##
## With [member follow_grip], pressure follows how tightly the hand is closed, between
## [member min_strength] and [member strength]: squeeze harder, feel more.

enum FireOn { SELECT, HOVER, SELECT_AND_HOVER }

@export var fire_on: FireOn = FireOn.SELECT
@export_group("Fingers")
@export var thumb := true
@export var index := true
@export var middle := true
@export var ring := false
@export var pinky := false
@export var palm := true
@export_group("Strength")
## 10 (lightest) to 60 (firm). 30 suits a small prop, 40 something heavier. Below 5, nothing.
@export_range(0.0, 60.0, 1.0) var strength := 30.0
@export var follow_grip := true
@export_range(0.0, 60.0, 1.0) var min_strength := 10.0
@export_group("Binding")
## Find an XR Tools pickable on the parent and follow its pick-up and highlight signals.
@export var auto_bind_xr_tools := true

var _engagements: Dictionary = {}  # interactor key -> {hand, hovering, selecting}
var _active: Array[bool] = [false, false]
var _applied: Array[float] = [-1.0, -1.0]
var _binding: HexRXRToolsBinding


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if auto_bind_xr_tools:
		_binding = HexRXRToolsBinding.bind(get_parent(), self)


func _exit_tree() -> void:
	_engagements.clear()
	for hand in 2:
		_disengage(hand)


## What the binding is attached to, for diagnostics.
func bound_to() -> String:
	return _binding.describe() if _binding else "nothing"


## Reports what one interactor (a hand, a ray, a controller) is doing with this object.
## [param hand] is [enum HaptGloveHandler.HandType], or -1 when the toolkit cannot tell.
func set_interactor_state(interactor_key: Variant, hand: int, hovering: bool, selecting: bool) -> void:
	if not hovering and not selecting:
		_engagements.erase(interactor_key)
	else:
		_engagements[interactor_key] = {"hand": hand, "hovering": hovering, "selecting": selecting}
	_recompute()


func clear_interactor(interactor_key: Variant) -> void:
	if _engagements.erase(interactor_key):
		_recompute()


func _wants(e: Dictionary) -> bool:
	match fire_on:
		FireOn.SELECT:
			return e["selecting"]
		FireOn.HOVER:
			return e["hovering"] or e["selecting"]
	return e["hovering"] or e["selecting"]


func _recompute() -> void:
	var wanted: Array[bool] = [false, false]
	for e: Dictionary in _engagements.values():
		if not _wants(e):
			continue
		var hand: int = e["hand"]
		if hand < 0:
			# Unknown hand: whichever glove is there, right first.
			hand = HaptGloveHandler.HandType.RIGHT if _controller(HaptGloveHandler.HandType.RIGHT) else HaptGloveHandler.HandType.LEFT
		wanted[hand] = true
	for hand in 2:
		if wanted[hand]:
			_engage(hand)
		else:
			_disengage(hand)


func _engage(hand: int) -> void:
	if _controller(hand) == null:
		return
	if not _active[hand]:
		_active[hand] = true
		_applied[hand] = -1.0
	_push(hand, _pressure_from_grip(hand) if follow_grip else strength)


func _disengage(hand: int) -> void:
	if not _active[hand]:
		return
	_remove_all(hand)
	_active[hand] = false
	_applied[hand] = -1.0


func _process(_delta: float) -> void:
	if not follow_grip:
		return
	for hand in 2:
		if _active[hand]:
			_push(hand, _pressure_from_grip(hand))


func _pressure_from_grip(hand: int) -> float:
	var hub := HexRManager.get_instance()
	var use := hub.finger_use(hand) if hub else null
	if use == null:
		return strength
	var total := 0.0
	var n := 0
	for pair in [[thumb, use.thumb_use], [index, use.index_use], [middle, use.middle_use],
			[ring, use.ring_use], [pinky, use.little_use]]:
		if pair[0]:
			total += pair[1]
			n += 1
	if n == 0:
		return strength
	var openness := total / n
	if openness <= 0.0:
		return strength  # not calibrated yet
	return lerpf(min_strength, strength, clampf(1.0 - openness, 0.0, 1.0))


## Sends only when the 10-step value changes, so a held object does not flood the glove.
func _push(hand: int, pressure: float) -> void:
	var c := _controller(hand)
	if c == null:
		return
	var stepped := roundf(clampf(pressure, 0.0, 60.0) / 10.0) * 10.0
	if is_equal_approx(stepped, _applied[hand]):
		return
	_applied[hand] = stepped
	if stepped <= 0.0:
		_remove_all(hand)
		return
	var intensity := PressureTrackerMain.strength_to_intensity(stepped)
	if thumb:
		c.single_thumb_haptic(intensity)
	if index:
		c.single_index_haptic(intensity)
	if middle:
		c.single_middle_haptic(intensity)
	if ring:
		c.single_ring_haptic(intensity)
	if pinky:
		c.single_pinky_haptic(intensity)
	if palm:
		c.single_palm_haptic(intensity)


func _remove_all(hand: int) -> void:
	var c := _controller(hand)
	if c == null:
		return
	if thumb:
		c.remove_thumb_haptics()
	if index:
		c.remove_index_haptics()
	if middle:
		c.remove_middle_haptics()
	if ring:
		c.remove_ring_haptics()
	if pinky:
		c.remove_pinky_haptics()
	if palm:
		c.remove_palm_haptics()


func _controller(hand: int) -> PressureTrackerMain:
	var hub := HexRManager.get_instance()
	return hub.controller(hand) if hub else null
