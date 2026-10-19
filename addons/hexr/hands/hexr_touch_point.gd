class_name HexRTouchPoint
extends Area3D
## A fingertip or the palm of a tracked hand (port of the Unity package's HapticFingerTrigger).
## [HexRTrackedHand] creates six of them and moves them with the hand's joints. Zones and
## components find out which finger touched them from the touch point that entered them:
## [codeblock]
## func _on_area_entered(area: Area3D) -> void:
##     if area is HexRTouchPoint:
##         area.trigger_fix_pressure(0.6)
## [/codeblock]

@export var hand: HexRTypes.Hand = HexRTypes.Hand.LEFT
@export var finger: HexRTypes.Finger = HexRTypes.Finger.INDEX


func controller() -> HexRPressureController:
	var hub := HexRManager.get_instance()
	return hub.controller(hand) as HexRPressureController if hub else null


func glove() -> HexRGlove:
	var hub := HexRManager.get_instance()
	return hub.glove(hand) if hub else null


func is_palm() -> bool:
	return finger == HexRTypes.Finger.PALM


## Presses this finger, skipping the hand-near check (the touch is the evidence).
func trigger_fix_pressure(intensity: float) -> void:
	var c := controller()
	if c:
		c.custom_single_haptics(finger, true, intensity, 1.0, true)
	else:
		var g := glove()
		if g:
			g.bt_send(g.haptics.hexr_pressure(finger, true, intensity, 1.0))


## Vibrates this finger. [param frequency] 0.1..40 Hz.
func trigger_vibration_pressure(frequency: float, intensity: float) -> void:
	var g := glove()
	if g:
		g.bt_send(g.haptics.hexr_vibration(finger, true, frequency, intensity))


func remove_vibration() -> void:
	var g := glove()
	if g:
		g.bt_send(g.haptics.hexr_vibration(finger, false, 0.0, 0.0))


func remove_haptics() -> void:
	var c := controller()
	if c:
		c.custom_single_haptics(finger, false, 0.0, 1.0, true)
	else:
		var g := glove()
		if g:
			g.bt_send(g.haptics.hexr_pressure(finger, false, 0.0, 1.0))
