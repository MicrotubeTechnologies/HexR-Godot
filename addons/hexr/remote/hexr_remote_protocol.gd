class_name HexRRemoteProtocol
## HexR Remote protocol, version 1: the messages a phone (the HexR Companion's Headsets tab)
## and a headset exchange. The contract is docs/RemoteProtocol.md, shared with the Unity
## package; the reference lines in tests/unit/test_remote_protocol.gd are byte-identical to the
## Unity package's RemoteTests.cs and the Companion's tests. Change one, change all.
##
## Builders return Dictionaries whose keys are inserted in the order the wire uses, and
## [method to_line] keeps that order.

const VERSION := 1
const MAX_LINE_BYTES := 16 * 1024
const DEFAULT_DISCOVERY_PORT := 47800
const DEFAULT_CONTROL_PORT := 47801
const DEFAULT_VIDEO_PORT := 47802
const DEFAULT_AUDIO_PORT := 47803

const STATE_CONNECTED := "connected"
const STATE_CONNECTING := "connecting"
const STATE_DISCONNECTED := "disconnected"
const STATE_MISSING := "missing"

const STREAM_OFF := "off"
const STREAM_REQUESTING := "requesting"
const STREAM_LIVE := "live"
const STREAM_DENIED := "denied"
const STREAM_UNSUPPORTED := "unsupported"
const STREAM_ERROR := "error"

const MODE_NAMES: Array[String] = ["off", "pressure", "vibration", "pulse"]


## Parses one request line. Returns {"request": Dictionary} or {"error": String}. Missing
## fields read as "not given": empty strings, and index -1.
static func try_parse(line: String) -> Dictionary:
	if line.strip_edges().is_empty():
		return {"error": "Empty request."}
	var json := JSON.new()
	if json.parse(line) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "That request is not JSON."}
	var d: Dictionary = json.data
	var req := {
		"type": _str(d.get("type", "")),
		"action": _str(d.get("action", "")),
		"hand": _str(d.get("hand", "")),
		"index": _int(d.get("index", -1), -1),
		"id": _str(d.get("id", "")),
		"protocol": _int(d.get("protocol", 0), 0),
		"client": _str(d.get("client", "")),
	}
	if String(req["type"]).is_empty():
		return {"error": "The request has no type."}
	return {"request": req}


static func _str(v: Variant) -> String:
	return v if typeof(v) == TYPE_STRING else ("" if v == null else str(v))


## JSON numbers arrive as floats.
static func _int(v: Variant, fallback: int) -> int:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(v)
	return fallback


## [enum HexRTypes.Hand] for "left"/"right" (any case), or -1.
static func parse_hand(hand: String) -> int:
	match hand.to_lower():
		"left":
			return HexRTypes.Hand.LEFT
		"right":
			return HexRTypes.Hand.RIGHT
	return -1


static func hand_name(hand: int) -> String:
	return "left" if hand == HexRTypes.Hand.LEFT else "right"


## Round half to even, as the Unity package's Mathf.RoundToInt does.
static func round_half_even(x: float) -> int:
	var f := floorf(x)
	var diff := x - f
	if diff > 0.5:
		return int(f) + 1
	if diff < 0.5:
		return int(f)
	return int(f) if int(f) % 2 == 0 else int(f) + 1


## A raw pressure reading as gauge tenths of a kPa: above 10000 it is absolute pascals,
## otherwise already gauge kPa (the HexR Tester's rule).
static func to_deci_kpa(raw: float) -> int:
	var kpa := (raw - 100000.0) / 1000.0 if raw > 10000.0 else raw
	if is_nan(kpa) or is_inf(kpa):
		return 0
	return round_half_even(HexRF32.r(kpa * 10.0))


## One line on the wire: compact JSON, keys in insertion order.
static func to_line(message: Dictionary) -> String:
	return JSON.stringify(_clean(message), "", false)


## Godot's JSON writer escapes some control characters wrongly (\v) and others not at all;
## they never belong in these strings, so they become spaces.
static func _clean(v: Variant) -> Variant:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(v)
			for i in s.length():
				if s.unicode_at(i) < 0x20:
					s = s.substr(0, i) + " " + s.substr(i + 1)
			return s
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _clean(v[k])
			return out
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(_clean(x))
			return out
	return v


# -- messages -------------------------------------------------------------------------------

static func announce(id: String, device_name: String, model: String, platform: String, app: String,
		app_id: String, hexr_version: String, control: int, video: int, started_at: int) -> Dictionary:
	return {"hexr": VERSION, "type": "announce", "id": id, "name": device_name, "model": model,
		"platform": platform, "app": app, "appId": app_id, "hexrVersion": hexr_version,
		"control": control, "video": video, "startedAt": started_at}


static func welcome(id: String, control: int, video: int) -> Dictionary:
	return {"type": "hello", "protocol": VERSION, "id": id, "control": control, "video": video}


static func error_line(request_type: String, message: String) -> String:
	return to_line({"type": "error", "request": request_type, "message": message})


static func scene_info(index: int, scene_name: String) -> Dictionary:
	return {"index": index, "name": scene_name}


static func command_info(id: String, label: String) -> Dictionary:
	return {"id": id, "label": label}


static func glove_status(hand: String, state: String = STATE_MISSING, message: String = "",
		battery_pct: int = -1, pressure_deci_kpa: Array = []) -> Dictionary:
	return {"hand": hand, "state": state, "message": message, "batteryPct": battery_pct,
		"pressureDeciKPa": pressure_deci_kpa}


static func audio_status(state: String = STREAM_OFF, port: int = 0, sample_rate: int = 0,
		channels: int = 0, message: String = "") -> Dictionary:
	return {"state": state, "port": port, "sampleRate": sample_rate, "channels": channels, "message": message}


static func stream_status(state: String = STREAM_OFF, port: int = 0, width: int = 0, height: int = 0,
		viewers: int = 0, message: String = "", audio: Dictionary = {}) -> Dictionary:
	return {"state": state, "port": port, "width": width, "height": height, "viewers": viewers,
		"message": message, "audio": audio if not audio.is_empty() else audio_status()}


## The status line's fields, in wire order. Every argument is required so none is left out.
static func status(id: String, device_name: String, model: String, platform: String, app: String,
		app_version: String, hexr_version: String, paused: bool, headset_battery_pct: int,
		scene: Dictionary, scenes: Array, gloves: Array, stream: Dictionary, commands: Array,
		allow_glove_control: bool, allow_video: bool, expose_scenes: bool, controllers: int,
		clock_us: int) -> Dictionary:
	return {"type": "status", "protocol": VERSION, "id": id, "name": device_name, "model": model,
		"platform": platform, "app": app, "appVersion": app_version, "hexrVersion": hexr_version,
		"paused": paused, "headsetBatteryPct": headset_battery_pct, "scene": scene, "scenes": scenes,
		"gloves": gloves, "stream": stream, "commands": commands,
		"allowGloveControl": allow_glove_control, "allowVideo": allow_video,
		"exposeScenes": expose_scenes, "controllers": controllers, "haptics": true, "clockUs": clock_us}


static func haptic_channel(finger: int, mode: String = "off", intensity_pct: int = 0,
		frequency_deci_hz: int = 0, tap: bool = false) -> Dictionary:
	return {"finger": finger, "mode": mode, "intensityPct": intensity_pct,
		"frequencyDeciHz": frequency_deci_hz, "tap": tap}


static func haptics_message(t: int, hand: String, channels: Array) -> Dictionary:
	return {"type": "haptics", "t": t, "hand": hand, "channels": channels}


## "2_hospital_tutorial.tscn" reads as "2 Hospital Tutorial"; "LivingHeart" as "Living Heart",
## "FindTheLump" as "Find the Lump" (the Unity package's HexRSceneNames rule, plus snake_case).
static func scene_display_name(path: String) -> String:
	var name := path.get_file().get_basename().replace("_", " ")
	if name.contains(" "):
		var words := name.split(" ", false)
		for i in words.size():
			words[i] = words[i].capitalize() if words[i].to_lower() == words[i] else words[i]
		return " ".join(words)
	var spaced := ""
	for i in name.length():
		var c := name[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower() and name[i - 1] == name[i - 1].to_lower() \
				and name[i - 1] != name[i - 1].to_upper():
			spaced += " "
		spaced += c
	var words2 := spaced.split(" ")
	for i in range(1, words2.size()):
		if words2[i] in ["The", "A", "Of", "And"]:
			words2[i] = words2[i].to_lower()
	return " ".join(words2)
