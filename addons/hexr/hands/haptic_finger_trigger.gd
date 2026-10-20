class_name HapticFingerTrigger
extends Area3D
## A fingertip or the palm of a tracked hand (port of the Unity package's HapticFingerTrigger).
## [HexRTrackedHand] creates six of them and moves them with the hand's joints. Zones and
## components find out which finger touched them from the touch point that entered them:
## [codeblock]
## func _on_area_entered(area: Area3D) -> void:
##     if area is HapticFingerTrigger:
##         area.trigger_fix_pressure(0.6)
## [/codeblock]

@export var hand_type: HaptGloveHandler.HandType = HaptGloveHandler.HandType.LEFT
@export var finger_type: Haptics.Finger = Haptics.Finger.INDEX


func controller() -> PressureTrackerMain:
	var hub := HexRManager.get_instance()
	return hub.controller(hand_type) as PressureTrackerMain if hub else null


func glove() -> HaptGloveHandler:
	var hub := HexRManager.get_instance()
	return hub.glove(hand_type) if hub else null


func is_palm() -> bool:
	return finger_type == Haptics.Finger.PALM


## Presses this finger, skipping the hand-near check (the touch is the evidence).
func trigger_fix_pressure(intensity: float) -> void:
	var c := controller()
	if c:
		c.custom_single_haptics(finger_type, true, intensity, 1.0, true)
	else:
		var g := glove()
		if g:
			g.bt_send(g.haptics.hexr_pressure(finger_type, true, intensity, 1.0))


## Vibrates this finger. [param frequency] 0.1..40 Hz.
func trigger_vibration_pressure(frequency: float, intensity: float) -> void:
	var g := glove()
	if g:
		g.bt_send(g.haptics.hexr_vibration(finger_type, true, frequency, intensity))


func remove_vibration() -> void:
	var g := glove()
	if g:
		g.bt_send(g.haptics.hexr_vibration(finger_type, false, 0.0, 0.0))


func remove_haptics() -> void:
	var c := controller()
	if c:
		c.custom_single_haptics(finger_type, false, 0.0, 1.0, true)
	else:
		var g := glove()
		if g:
			g.bt_send(g.haptics.hexr_pressure(finger_type, false, 0.0, 1.0))
