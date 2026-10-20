class_name HaptGloveCollidersVisualizer
extends Node
## Shows or hides the touch points on both tracked hands: the fingertip and palm spheres that fire
## haptics (port of the Unity package's HaptGloveCollidersVisualizer). The floating menu's
## Show Colliders button drives it.
##
## The HexR autoload owns one, so the setting survives scene changes; reach it as
## [code]HexR.colliders_visualizer[/code] or [method find].

var _showing := false


## The running HexR manager's visualizer, or null.
static func find() -> HaptGloveCollidersVisualizer:
	var hub := HexRManager.get_instance()
	return hub.colliders_visualizer if hub else null


func is_showing() -> bool:
	return _showing


## Shows the touch points if they are hidden, hides them if they are showing.
func collider_toggle() -> void:
	set_visible(not _showing)


func show() -> void:
	set_visible(true)


func hide() -> void:
	set_visible(false)


func set_visible(visible: bool) -> void:
	_showing = visible
	refresh()


## Applies the setting to the tracked hands in the scene. Called every frame, so hands that a
## new scene brings pick it up.
func refresh() -> void:
	var hub := get_parent() as HexRManager
	if hub == null:
		hub = HexRManager.get_instance()
	if hub == null:
		return
	for h in [hub.left_tracked_hand, hub.right_tracked_hand]:
		if h != null and h.show_touch_points != _showing:
			h.show_touch_points = _showing


## True if the scene has any tracked hand to show.
func has_hands() -> bool:
	var hub := HexRManager.get_instance()
	return hub != null and (hub.left_tracked_hand != null or hub.right_tracked_hand != null)


func _process(_delta: float) -> void:
	refresh()
