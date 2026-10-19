class_name HexRPressureController
extends Node
## A hand's "Pressure Controller" (port of the Unity package's PressureTrackerMain). Every
## haptic for that hand goes through here; a hand without one produces no haptics. Reach it as
## [code]HexR.controller(HexRTypes.Hand.LEFT)[/code].
##
## Calls other than the [code]remove_*[/code] ones only fire while the hand is near something:
## grabbing, poke-hovering, or touching a [HexRProximityCheck] (the "hand-near check"). Pass
## [code]bypass_hand_check[/code] to the custom calls to skip it.
##
## Intensity is 0.1..1 (about 15..50 kPa). Components use a 10..60 strength scale; convert with
## [method strength_to_intensity].

const F := HexRTypes.Finger

@export var hand: HexRTypes.Hand = HexRTypes.Hand.LEFT

## Set by grab interactions (HexRGrabbable, the XR Tools binding).
var hand_grabbing := false
## Set by poke interactions.
var poke_hovering := false

var _manual_collision_near := false
var _near_sources: Dictionary = {}
var _warned_no_glove := false


func _enter_tree() -> void:
	var hub := HexRManager.get_instance()
	if hub:
		hub._register_controller(self, hand)


func _exit_tree() -> void:
	var hub := HexRManager.get_instance()
	if hub:
		hub._unregister_controller(self)


## Unity StrengthToIntensity: the 10..60 component scale to 0.1..1 intensity.
static func strength_to_intensity(strength: float) -> float:
	return clampf(0.1 + 0.9 * (strength - 10.0) / 50.0, 0.1, 1.0)


## This hand's glove, or null.
func glove() -> HexRGlove:
	var hub := HexRManager.get_instance()
	return hub.glove(hand) if hub else null


## This hand's tracked hand (joints, touch points, finger curl), or null.
func tracked_hand() -> HexRTrackedHand:
	var hub := HexRManager.get_instance()
	return hub.tracked_hand(hand) if hub else null


# -- hand-near check -----------------------------------------------------------------------

func hand_grabbing_check(is_grabbing: bool) -> void:
	hand_grabbing = is_grabbing


func poke_hovering_check(is_hovering: bool) -> void:
	poke_hovering = is_hovering


## Sets the physics-contact flag directly (Unity IsPhysicsCollisionNear).
func is_physics_collision_near(near: bool) -> void:
	_manual_collision_near = near


## Proximity zones report here; the hand counts as near while any of them says so.
func set_near_source(source: Object, near: bool) -> void:
	var key := source.get_instance_id()
	if near:
		_near_sources[key] = true
	else:
		_near_sources.erase(key)


func collision_near() -> bool:
	return _manual_collision_near or not _near_sources.is_empty()


func is_hand_near() -> bool:
	return hand_grabbing or poke_hovering or collision_near()


# -- single channel -------------------------------------------------------------------------

func single_thumb_haptic(intensity: float) -> void:
	_gated_press(F.THUMB, intensity)


func single_index_haptic(intensity: float) -> void:
	_gated_press(F.INDEX, intensity)


func single_middle_haptic(intensity: float) -> void:
	_gated_press(F.MIDDLE, intensity)


func single_ring_haptic(intensity: float) -> void:
	_gated_press(F.RING, intensity)


func single_pinky_haptic(intensity: float) -> void:
	_gated_press(F.PINKY, intensity)


func single_palm_haptic(intensity: float) -> void:
	_gated_press(F.PALM, intensity)


func remove_thumb_haptics() -> void:
	_release(F.THUMB)


func remove_index_haptics() -> void:
	_release(F.INDEX)


func remove_middle_haptics() -> void:
	_release(F.MIDDLE)


func remove_ring_haptics() -> void:
	_release(F.RING)


func remove_pinky_haptics() -> void:
	_release(F.PINKY)


func remove_palm_haptics() -> void:
	_release(F.PALM)


## Pressure on one channel. [param on] false releases it.
func custom_single_haptics(finger: int, on: bool, intensity: float, speed: float = 1.0,
		bypass_hand_check: bool = false) -> void:
	var g := _glove_or_warn()
	if g and (bypass_hand_check or is_hand_near()):
		g.bt_send(g.haptics.hexr_pressure(finger, on, intensity, speed))


## Vibration on one channel. [param frequency] 0.1..40 Hz.
func custom_single_vibrations(finger: int, on: bool, intensity: float, frequency: float,
		bypass_hand_check: bool = false) -> void:
	var g := _glove_or_warn()
	if g and (bypass_hand_check or is_hand_near()):
		g.bt_send(g.haptics.hexr_vibration(finger, on, frequency, intensity))


# -- several channels -----------------------------------------------------------------------

func trigger_all_haptics_increase(intensity: float) -> void:
	trigger_custom_haptics_increase([true, true, true, true, true, true], intensity, 1.0)


## [param fingers_on]: six booleans, Thumb..Palm. A false entry releases that channel.
func trigger_custom_haptics_increase(fingers_on: Array, intensity: float, speed: float = 1.0) -> void:
	var g := _glove_or_warn()
	if g and is_hand_near():
		g.bt_send(g.haptics.hexr_pressure_multi(HexRTypes.ALL_FINGERS, fingers_on,
				[intensity, intensity, intensity, intensity, intensity, intensity], [speed, speed, speed, speed, speed, speed]))


func trigger_pinch_pressure(intensity: float) -> void:
	var g := _glove_or_warn()
	if g and is_hand_near():
		g.bt_send(g.haptics.hexr_pressure_multi([F.THUMB, F.INDEX], [true, true], [intensity, intensity], [1.0, 1.0]))


func remove_pinch_pressure() -> void:
	var g := _glove_or_warn()
	if g and is_hand_near():
		g.bt_send(g.haptics.hexr_pressure_multi([F.THUMB, F.INDEX], [false, false], [0.0, 0.0], [1.0, 1.0]))


## Every channel vibrating at [param frequency] Hz, at half intensity.
func trigger_all_vibrations(frequency: float) -> void:
	trigger_custom_vibrations([true, true, true, true, true, true], 0.5, frequency)


func trigger_custom_vibrations(fingers_on: Array, intensity: float, frequency: float) -> void:
	var g := _glove_or_warn()
	if g and is_hand_near():
		g.bt_send(g.haptics.hexr_vibration_multi(HexRTypes.ALL_FINGERS, fingers_on,
				[frequency, frequency, frequency, frequency, frequency, frequency],
				[intensity, intensity, intensity, intensity, intensity, intensity]))


## Releases every channel's pressure. Not gated by the hand-near check.
func remove_all_haptics() -> void:
	var g := _glove_or_warn()
	if g:
		g.bt_send(g.haptics.hexr_pressure_multi(HexRTypes.ALL_FINGERS, [false, false, false, false, false, false],
				[0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]))


## Stops every channel's vibration. Not gated by the hand-near check.
func remove_all_vibrations() -> void:
	var g := _glove_or_warn()
	if g:
		var out := PackedByteArray()
		for f in HexRTypes.ALL_FINGERS:
			out.append_array(g.haptics.hexr_vibration_ramped(f, false, 0.0, 0.0, 0.8, 1.0, 0.0))
		g.bt_send(out)


## One short pulse on every channel. Replaces the Unity package's TriggerPulseIt, which used a
## deprecated command.
func trigger_pulse_all(intensity: float = 0.3) -> void:
	var g := _glove_or_warn()
	if g:
		var out := PackedByteArray()
		for f in HexRTypes.ALL_FINGERS:
			out.append_array(g.haptics.hexr_pulse(f, true, 10.0, intensity, 1))
		g.bt_send(out)


## The glove's pressure readings in gauge kPa (Thumb..Palm, then the air source).
func get_pressures_kpa() -> PackedFloat32Array:
	var g := glove()
	return g.get_air_pressure_kpa() if g else PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])


func _gated_press(finger: int, intensity: float) -> void:
	var g := _glove_or_warn()
	if g and is_hand_near():
		g.bt_send(g.haptics.hexr_pressure(finger, true, intensity, 1.0))


func _release(finger: int) -> void:
	var g := _glove_or_warn()
	if g:
		g.bt_send(g.haptics.hexr_pressure(finger, false, 0.0, 1.0))


func _glove_or_warn() -> HexRGlove:
	var g := glove()
	if g == null and not _warned_no_glove:
		_warned_no_glove = true
		push_warning("[HexR] %s Pressure Controller has no HexR autoload to send to, so haptics are skipped."
				% HexRTypes.hand_name(hand))
	return g
