class_name HexRRemoteHaptics
extends RefCounted
## The haptics lines HexR Remote sends: what each glove channel was told to do, whenever it
## changes (port of the Unity package's RemoteHaptics). Polled once a frame after every script
## has run, so a command from any script is included. A channel switched on and off within one
## frame is sent as a tap.

const FINGERS := 6

var _clock: Callable  # () -> int microseconds
var _last: Array = [[], []]  # [hand][finger] -> Haptics.ChannelState
var _count: Array = [PackedInt32Array([0, 0, 0, 0, 0, 0]), PackedInt32Array([0, 0, 0, 0, 0, 0])]
var _watched: Array = [null, null]


func _init(clock: Callable) -> void:
	_clock = clock
	for h in 2:
		for f in FINGERS:
			_last[h].append(Haptics.ChannelState.new())


## Appends a line for each hand whose channels changed since the last poll.
func poll(hub: HexRManager, lines: Array) -> void:
	var now := -1
	for h in 2:
		var g: HaptGloveHandler = hub.glove(h) if hub else null
		var haptics: Haptics = g.haptics if g else null
		var changed := []
		if g != _watched[h]:
			# A different glove (or none): whatever was on is off as far as a viewer knows.
			for f in FINGERS:
				if _last[h][f].is_on():
					changed.append(_channel(f, Haptics.ChannelState.new(), false))
				_last[h][f] = Haptics.ChannelState.new()
				_count[h][f] = haptics.get_activation_count(f) if haptics else 0
			_watched[h] = g
		if haptics:
			for f in FINGERS:
				var state := haptics.get_channel_state(f)
				var n := haptics.get_activation_count(f)
				if n != _count[h][f]:
					if state.is_on():
						changed.append(_channel(f, state, false))
					else:
						changed.append(_channel(f, haptics.get_last_active_state(f), true))
				elif not state.equals(_last[h][f]):
					changed.append(_channel(f, state, false))
				_last[h][f] = state
				_count[h][f] = n
		if not changed.is_empty():
			if now < 0:
				now = _clock.call()
			lines.append(_line(h, now, changed))


## One line per hand with all six channels, sent to a phone right after the welcome.
func snapshot() -> PackedStringArray:
	var now: int = _clock.call()
	var out := PackedStringArray()
	for h in 2:
		var channels := []
		for f in FINGERS:
			channels.append(_channel(f, _last[h][f], false))
		out.append(_line(h, now, channels))
	return out


static func _line(hand: int, t: int, channels: Array) -> String:
	return HexRRemoteProtocol.to_line(HexRRemoteProtocol.haptics_message(t, HexRRemoteProtocol.hand_name(hand), channels))


static func _channel(finger: int, state: Haptics.ChannelState, tap: bool) -> Dictionary:
	if not state.is_on():
		return HexRRemoteProtocol.haptic_channel(finger)
	var intensity := state.intensity
	if intensity > 1.0:
		# A deprecated command recorded kPa rather than 0.1..1.
		intensity = 0.1 + 0.9 * inverse_lerp(15.0, 50.0, intensity)
	return HexRRemoteProtocol.haptic_channel(finger, HexRRemoteProtocol.MODE_NAMES[state.mode],
			clampi(HexRRemoteProtocol.round_half_even(HexRF32.r(intensity * 100.0)), 0, 100),
			maxi(0, HexRRemoteProtocol.round_half_even(HexRF32.r(state.frequency * 10.0))), tap)
