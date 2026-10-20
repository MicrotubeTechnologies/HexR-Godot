class_name SpecialHaptics
extends Area3D
## A zone with a ready-made haptic effect for the fingers inside it (port of the Unity
## package's SpecialHaptics). Effects skip the hand-near check: being in the zone is enough.
##
## [br]- Custom vibrations: touching fingers vibrate at [member vibrations_frequency_value].
## [br]- Custom haptics: touching fingers press at [member haptic_pressure] (10..60).
## [br]- Fountain: touching fingers vibrate at 18 Hz, as if under running water.
## [br]- Rain drop: the palm gets random patterns of drops.
## [br]- Heart beat: touching fingers pulse like a pulse point, regular or irregular.
## [br]- Hand squeeze: emits [signal squeezed] when a hand closes around the zone.

signal squeezed(hand: int)

## Unity's effect types (the order is the same as the Unity package's).
enum Options { CUSTOM_VIBRATIONS, CUSTOM_HAPTICS, FOUNTAIN_EFFECT, RAIN_DROP_EFFECT, HEART_BEAT_EFFECT, HAND_SQUEEZE_EFFECT }
enum HeartBeat { REGULAR, IRREGULAR }

const FINGERS := 6

@export var type_of_haptics: Options = Options.CUSTOM_VIBRATIONS
## Intensity (0.1..1) for custom vibrations and rain drops.
@export_range(0.1, 1.0, 0.05) var haptic_strength_value := 0.5
## Custom vibrations frequency in Hz.
@export_range(0.1, 40.0, 0.1) var vibrations_frequency_value := 1.0
## Custom haptics pressure on the 10..60 strength scale.
@export_range(10.0, 60.0, 10.0) var haptic_pressure := 10.0
## Intensity (0.1..1) of each beat.
@export_range(0.1, 1.0, 0.1) var heart_beat_pressure := 0.5
@export var heartbeat: HeartBeat = HeartBeat.REGULAR
## Seconds each beat presses, then rests (regular beats).
@export var in_timer := 0.4
@export var out_timer := 0.3
## Let the palm feel the beat too.
@export var include_palm := false
## The squeeze fires when a finger enters the zone while every finger's use (0 curled .. 1
## extended) is at least this value. The Unity package's rule, kept as is.
@export_range(0.0, 1.0, 0.05) var squeeze_tightness := 0.2

# Which channels this zone has turned on, per hand, so it can release exactly those.
var _applied: Array = [[false, false, false, false, false, false], [false, false, false, false, false, false]]
var _clock := 0.0
var _next_tick := 0.0
# Custom haptics: removal due times per touch point, after a short grace on exit.
var _pending_removal: Dictionary = {}
var _pressed_points: Dictionary = {}
# Rain.
var _ready_to_drop := true
var _drop_rearm_at := 0.0
var _drop_release_at: Array[float] = [-1.0, -1.0]
# Heart beat.
var _beat_in := true
var _beat_phase_end := 0.0
var _beat_activated: Array[bool] = [false, false]



# Scenes saved with HexR 0.1 use the old property names.
const _RENAMED_0_1 := {&"effect": &"type_of_haptics", &"haptic_strength": &"haptic_strength_value",
		&"vibration_frequency": &"vibrations_frequency_value", &"heart_beat": &"heartbeat"}


func _set(property: StringName, value: Variant) -> bool:
	if not _RENAMED_0_1.has(property):
		return false
	set(_RENAMED_0_1[property], value)
	HexRTypes.warn_renamed(self, property, _RENAMED_0_1[property])
	return true

func _init() -> void:
	collision_layer = 0
	collision_mask = 1 << 19
	monitorable = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	_start_beat_in()


## Switches the heart beat between regular and irregular.
func toggle_heart_regularity() -> void:
	heartbeat = HeartBeat.REGULAR if heartbeat == HeartBeat.IRREGULAR else HeartBeat.IRREGULAR


## Touching fingers per hand: [hand][finger] -> HapticFingerTrigger or null.
func _touching() -> Array:
	var out := [[null, null, null, null, null, null], [null, null, null, null, null, null]]
	for area in get_overlapping_areas():
		if area is HapticFingerTrigger:
			out[area.hand_type][area.finger_type] = area
	return out


func _physics_process(delta: float) -> void:
	_clock += delta
	match type_of_haptics:
		Options.CUSTOM_VIBRATIONS:
			_tick_vibration(0.2, vibrations_frequency_value, haptic_strength_value)
		Options.FOUNTAIN_EFFECT:
			_tick_vibration(0.3, 18.0, 0.8)
		Options.CUSTOM_HAPTICS:
			_tick_custom_haptics()
		Options.RAIN_DROP_EFFECT:
			_tick_rain()
		Options.HEART_BEAT_EFFECT:
			_tick_heart_beat()


# -- vibration and fountain -----------------------------------------------------------------

func _tick_vibration(period: float, frequency: float, intensity: float) -> void:
	if _clock < _next_tick:
		return
	_next_tick = _clock + period
	var touching := _touching()
	for hand in 2:
		var on: Array = []
		var any := false
		for f in FINGERS:
			on.append(touching[hand][f] != null)
			any = any or on[f]
		if any:
			_send_vibration(hand, on, frequency, intensity)
		elif _any_applied(hand):
			# The hand left: stop what this zone started. (The Unity zone could miss this and
			# leave the glove vibrating.)
			_send_vibration(hand, [false, false, false, false, false, false], 0.0, 0.0)


func _send_vibration(hand: int, on: Array, frequency: float, intensity: float) -> void:
	var g := _glove(hand)
	if g == null:
		return
	g.bt_send(g.haptics.hexr_vibration_multi(HexRTypes.ALL_FINGERS, on,
			[frequency, frequency, frequency, frequency, frequency, frequency],
			[intensity, intensity, intensity, intensity, intensity, intensity]))
	for f in FINGERS:
		_applied[hand][f] = on[f]


# -- custom haptics -------------------------------------------------------------------------

func _on_area_entered(area: Area3D) -> void:
	if not (area is HapticFingerTrigger):
		return
	var tp := area as HapticFingerTrigger
	match type_of_haptics:
		Options.CUSTOM_HAPTICS:
			_pending_removal.erase(tp)
			_press_point(tp)
		Options.HAND_SQUEEZE_EFFECT:
			var hub := HexRManager.get_instance()
			var use := hub.finger_use(tp.hand_type) if hub else null
			if use == null:
				push_warning("[HexR] %s: Hand Squeeze needs a HexRTrackedHand for the %s hand." % [name, HexRTypes.hand_name(tp.hand_type)])
				return
			if use.thumb_use >= squeeze_tightness and use.index_use >= squeeze_tightness and use.middle_use >= squeeze_tightness \
					and use.ring_use >= squeeze_tightness and use.little_use >= squeeze_tightness:
				squeezed.emit(tp.hand_type)


func _on_area_exited(area: Area3D) -> void:
	if area is HapticFingerTrigger and type_of_haptics == Options.CUSTOM_HAPTICS and _pressed_points.has(area):
		_pending_removal[area] = _clock + 0.1


func _press_point(tp: HapticFingerTrigger) -> void:
	tp.trigger_fix_pressure(PressureTrackerMain.strength_to_intensity(haptic_pressure))
	_pressed_points[tp] = true
	_applied[tp.hand_type][tp.finger_type] = true


func _tick_custom_haptics() -> void:
	for tp: HapticFingerTrigger in _pending_removal.keys():
		if _clock < _pending_removal[tp]:
			continue
		_pending_removal.erase(tp)
		if is_instance_valid(tp) and not overlaps_area(tp):
			tp.remove_haptics()
			_pressed_points.erase(tp)
			_applied[tp.hand_type][tp.finger_type] = false
	# Re-press a touching finger if something else released it meanwhile.
	for tp: HapticFingerTrigger in _pressed_points.keys():
		if not is_instance_valid(tp):
			_pressed_points.erase(tp)
			continue
		var g := tp.glove()
		if g and g.ble_connected and overlaps_area(tp) and not _pending_removal.has(tp) \
				and g.haptics.get_channel_state(tp.finger_type).mode == Haptics.HapticMode.OFF:
			_press_point(tp)


# -- rain -----------------------------------------------------------------------------------

const RAIN_PATTERNS: Array = [
	[true, false, false, false, true, false], [false, true, true, true, false, false],
	[true, false, true, false, false, true], [true, true, false, false, false, false],
	[false, false, true, true, false, false], [false, false, false, false, false, true],
	[false, false, false, true, true, false], [false, true, false, false, true, false],
]


func _tick_rain() -> void:
	if not _ready_to_drop and _clock >= _drop_rearm_at:
		_ready_to_drop = true
	for hand in 2:
		if _drop_release_at[hand] >= 0.0 and _clock >= _drop_release_at[hand]:
			_drop_release_at[hand] = -1.0
			var c := _controller(hand)
			if c:
				c.remove_all_haptics()
			_applied[hand] = [false, false, false, false, false, false]
	if not _ready_to_drop:
		return
	var touching := _touching()
	for hand in 2:
		if touching[hand][Haptics.Finger.PALM] == null:
			continue
		_ready_to_drop = false
		_drop_rearm_at = _clock + 0.2
		_drop_release_at[hand] = _clock + 0.4
		var g := _glove(hand)
		if g:
			var on: Array = RAIN_PATTERNS[randi_range(0, RAIN_PATTERNS.size() - 1)]
			var s := haptic_strength_value
			g.bt_send(g.haptics.hexr_pressure_multi(HexRTypes.ALL_FINGERS, on, [s, s, s, s, s, s], [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]))
			for f in FINGERS:
				_applied[hand][f] = _applied[hand][f] or on[f]
		break


# -- heart beat -----------------------------------------------------------------------------

func _start_beat_in() -> void:
	_beat_in = true
	_beat_phase_end = _clock + (in_timer if heartbeat == HeartBeat.REGULAR else randf_range(0.2, 0.4))
	_next_tick = _clock


func _tick_heart_beat() -> void:
	if _beat_in:
		if _clock >= _next_tick:
			_next_tick = _clock + 0.1
			var touching := _touching()
			for hand in 2:
				var on: Array = []
				var any := false
				for f in FINGERS:
					var hit: bool = touching[hand][f] != null and (f != Haptics.Finger.PALM or include_palm)
					on.append(hit)
					any = any or hit
				var g := _glove(hand)
				if any and g:
					var p := heart_beat_pressure
					g.bt_send(g.haptics.hexr_pressure_multi(HexRTypes.ALL_FINGERS, on, [p, p, p, p, p, p], [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]))
					_beat_activated[hand] = true
					for f in FINGERS:
						_applied[hand][f] = _applied[hand][f] or on[f]
		if _clock >= _beat_phase_end:
			_beat_in = false
			for hand in 2:
				if _beat_activated[hand]:
					var c := _controller(hand)
					if c:
						c.remove_all_haptics()
					_beat_activated[hand] = false
					_applied[hand] = [false, false, false, false, false, false]
			_beat_phase_end = _clock + (out_timer if heartbeat == HeartBeat.REGULAR else randf_range(0.4, 0.7))
	elif _clock >= _beat_phase_end:
		_start_beat_in()


# -- helpers --------------------------------------------------------------------------------

func _exit_tree() -> void:
	# Release exactly what this zone turned on.
	for hand in 2:
		var channels: Array = []
		for f in FINGERS:
			if _applied[hand][f]:
				channels.append(f)
		_applied[hand] = [false, false, false, false, false, false]
		var g := _glove(hand)
		if g and not channels.is_empty():
			g.release_channels(channels)
	_pressed_points.clear()
	_pending_removal.clear()


func _any_applied(hand: int) -> bool:
	for f in FINGERS:
		if _applied[hand][f]:
			return true
	return false


func _glove(hand: int) -> HaptGloveHandler:
	var hub := HexRManager.get_instance()
	return hub.glove(hand) if hub else null


func _controller(hand: int) -> PressureTrackerMain:
	var hub := HexRManager.get_instance()
	return hub.controller(hand) if hub else null
