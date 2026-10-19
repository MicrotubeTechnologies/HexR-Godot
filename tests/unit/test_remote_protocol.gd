extends HexRTest
## HexR Remote's side of the phone conversation: reading requests, running them against the
## gloves, and the lines sent back. Ports of the Unity package's RemoteTests.cs; the reference
## lines are the contract with the phone and are byte-identical to that file and to the HexR
## Companion's tests. Change one, change all.

const F := HexRTypes.Finger
const H := HexRTypes.Hand

const CONNECT_LEFT := "{\"type\":\"glove\",\"action\":\"connect\",\"hand\":\"left\"}"
const DISCONNECT_RIGHT := "{\"type\":\"glove\",\"action\":\"disconnect\",\"hand\":\"right\"}"
const RELEASE := "{\"type\":\"release\"}"
const SCENE := "{\"type\":\"scene\",\"index\":2}"
const COMMAND := "{\"type\":\"command\",\"id\":\"reset\"}"
const STREAM_START := "{\"type\":\"stream\",\"action\":\"start\"}"
const HELLO := "{\"type\":\"hello\",\"protocol\":1,\"client\":\"HexR Tester\"}"

const REFERENCE_STATUS := "{\"type\":\"status\",\"protocol\":1,\"id\":\"q3-1\",\"name\":\"Quest 3\",\"model\":\"Oculus Quest 3\"," \
	+ "\"platform\":\"quest\",\"app\":\"HexR Demo\",\"appVersion\":\"1.2\",\"hexrVersion\":\"0.10.0\"," \
	+ "\"paused\":false,\"headsetBatteryPct\":71," \
	+ "\"scene\":{\"index\":1,\"name\":\"Hospital Tutorial\"}," \
	+ "\"scenes\":[{\"index\":0,\"name\":\"Basic Tutorial\"},{\"index\":1,\"name\":\"Hospital Tutorial\"}]," \
	+ "\"gloves\":[{\"hand\":\"left\",\"state\":\"connected\",\"message\":\"Connected\",\"batteryPct\":83,\"pressureDeciKPa\":[10,0,0,0,0,0,452]}," \
	+ "{\"hand\":\"right\",\"state\":\"disconnected\",\"message\":\"\",\"batteryPct\":-1,\"pressureDeciKPa\":[]}]," \
	+ "\"stream\":{\"state\":\"live\",\"port\":47802,\"width\":1024,\"height\":1024,\"viewers\":1,\"message\":\"\"," \
	+ "\"audio\":{\"state\":\"live\",\"port\":47803,\"sampleRate\":48000,\"channels\":2,\"message\":\"\"}}," \
	+ "\"commands\":[{\"id\":\"reset\",\"label\":\"Reset demo\"}]," \
	+ "\"allowGloveControl\":true,\"allowVideo\":true,\"exposeScenes\":true,\"controllers\":2," \
	+ "\"haptics\":true,\"clockUs\":1791966541289123}"

const REFERENCE_HAPTICS := "{\"type\":\"haptics\",\"t\":1791966541289123,\"hand\":\"right\",\"channels\":[" \
	+ "{\"finger\":1,\"mode\":\"pressure\",\"intensityPct\":80,\"frequencyDeciHz\":0,\"tap\":false}]}"


class FakeStream:
	var starts := 0
	var stops := 0

	func start() -> void:
		starts += 1

	func stop() -> void:
		stops += 1

	func read() -> Dictionary:
		return HexRRemoteProtocol.stream_status()


var hub: HexRManager
var sim: HexRSimulatedTransport
var lg: HexRSimulatedGlove
var stream: FakeStream
var commands: HexRRemoteCommands
var loaded: Array[int] = []
var now := 1000


func before_each() -> void:
	sim = HexRSimulatedTransport.new()
	lg = sim.add_glove(HexRSimulatedGlove.new("AA:LEFT", HexRTypes.NAME_LEFT))
	hub = HexRManager.new()
	hub.drive_from_process = false
	hub.setup(sim, HexRDeviceStore.new(""))
	add_child(hub)
	hub.make_current()
	stream = FakeStream.new()
	loaded.clear()
	commands = HexRRemoteCommands.new(func() -> HexRManager: return hub, stream, func() -> int: return 3,
			func(i: int) -> void: loaded.append(i))


func after_each() -> void:
	HexRRemote.unregister_command("reset")
	HexRRemote.unregister_command("gone")


func run(line: String) -> String:
	var parsed := HexRRemoteProtocol.try_parse(line)
	assert_false(parsed.has("error"), "parses: " + line)
	return commands.handle(parsed["request"])


func connect_left() -> void:
	hub.connect_hand(H.LEFT)
	for i in 50:
		now += 20
		hub.tick(now)


# -- reading requests -------------------------------------------------------------------------

func test_parse_reads_every_reference_request() -> void:
	var c: Dictionary = HexRRemoteProtocol.try_parse(CONNECT_LEFT)["request"]
	assert_eq([c["type"], c["action"], c["hand"]], ["glove", "connect", "left"], "connect")
	var d: Dictionary = HexRRemoteProtocol.try_parse(DISCONNECT_RIGHT)["request"]
	assert_eq([d["action"], d["hand"]], ["disconnect", "right"], "disconnect")
	assert_eq(HexRRemoteProtocol.try_parse(SCENE)["request"]["index"], 2, "scene index is an int")
	assert_eq(HexRRemoteProtocol.try_parse(COMMAND)["request"]["id"], "reset", "command")
	var h: Dictionary = HexRRemoteProtocol.try_parse(HELLO)["request"]
	assert_eq([h["protocol"], h["client"]], [1, "HexR Tester"], "hello")


func test_missing_index_reads_as_not_given() -> void:
	assert_eq(HexRRemoteProtocol.try_parse(RELEASE)["request"]["index"], -1, "not scene 0")


func test_rejects_what_is_not_a_request() -> void:
	assert_eq(HexRRemoteProtocol.try_parse("hello there")["error"], "That request is not JSON.", "not JSON")
	assert_eq(HexRRemoteProtocol.try_parse("{\"hand\":\"left\"}")["error"], "The request has no type.", "no type")
	assert_eq(HexRRemoteProtocol.try_parse("  ")["error"], "Empty request.", "empty")
	assert_eq(HexRRemoteProtocol.try_parse("[1,2]")["error"], "That request is not JSON.", "not an object")


# -- gloves -----------------------------------------------------------------------------------

func test_connect_left_starts_connecting() -> void:
	assert_eq(run(CONNECT_LEFT), "", "accepted")
	assert_true(hub.is_hand_connecting(H.LEFT), "left connecting")
	assert_false(hub.is_hand_connecting(H.RIGHT), "right untouched")


func test_connect_refused_when_glove_control_is_off() -> void:
	commands.allow_glove_control = false
	assert_false(run(CONNECT_LEFT).is_empty(), "refused")
	assert_false(hub.is_hand_connecting(H.LEFT), "nothing started")


func test_connect_for_a_hand_that_is_neither() -> void:
	assert_false(run("{\"type\":\"glove\",\"action\":\"connect\",\"hand\":\"middle\"}").is_empty(), "refused")


func test_disconnect_while_connecting_says_so() -> void:
	run("{\"type\":\"glove\",\"action\":\"connect\",\"hand\":\"right\"}")
	assert_true(run(DISCONNECT_RIGHT).contains("still connecting"), "says still connecting")


func test_disconnect_a_glove_that_is_not_connected_is_harmless() -> void:
	assert_eq(run(DISCONNECT_RIGHT), "", "no error")


func test_disconnect_connected_glove() -> void:
	connect_left()
	assert_eq(run("{\"type\":\"glove\",\"action\":\"disconnect\",\"hand\":\"left\"}"), "", "accepted")
	assert_false(hub.is_hand_connected(H.LEFT), "disconnected")


func test_release_switches_every_channel_off() -> void:
	connect_left()
	hub.left.bt_send(hub.left.haptics.hexr_pressure(F.INDEX, true, 0.5, 1.0))
	assert_eq(run(RELEASE), "", "accepted")
	assert_eq(hub.left.haptics.get_channel_state(F.INDEX).mode, HexRTypes.HapticMode.OFF, "index off")


func test_release_rejects_an_unknown_hand() -> void:
	assert_false(run("{\"type\":\"release\",\"hand\":\"foot\"}").is_empty(), "refused")


# -- scenes, commands, stream -----------------------------------------------------------------

func test_scene_refused_unless_exposed() -> void:
	assert_false(run(SCENE).is_empty(), "refused")
	assert_eq(loaded.size(), 0, "nothing loaded")


func test_scene_loads_existing_and_refuses_others() -> void:
	commands.expose_scenes = true
	assert_eq(run(SCENE), "", "scene 2 loads")
	assert_eq(loaded, [2] as Array[int], "loaded 2")
	assert_false(run("{\"type\":\"scene\",\"index\":3}").is_empty(), "no scene 3")
	assert_false(run("{\"type\":\"scene\"}").is_empty(), "no index")
	assert_eq(loaded.size(), 1, "nothing else loaded")


func test_command_runs_what_the_app_registered_and_lists_it() -> void:
	var runs: Array[int] = []
	HexRRemote.register_command("reset", "Reset demo", func() -> void: runs.append(1))
	assert_eq(run(COMMAND), "", "ran")
	assert_eq(runs.size(), 1, "once")
	assert_eq(HexRRemote.command_list(), [{"id": "reset", "label": "Reset demo"}], "listed")


func test_unregistered_command_is_refused() -> void:
	assert_true(run(COMMAND).contains("no command"), "refused by name")


func test_command_of_a_freed_object() -> void:
	var n := Node.new()
	HexRRemote.register_command("gone", "Gone", n.queue_free)
	n.free()
	assert_true(run("{\"type\":\"command\",\"id\":\"gone\"}").contains("no longer in the scene"), "explains")


func test_stream_starts_and_stops_only_when_sharing() -> void:
	assert_eq(run(STREAM_START), "", "start")
	assert_eq(run("{\"type\":\"stream\",\"action\":\"stop\"}"), "", "stop")
	assert_eq([stream.starts, stream.stops], [1, 1], "called")
	commands.allow_video = false
	assert_false(run(STREAM_START).is_empty(), "refused when not sharing")
	assert_eq(stream.starts, 1, "not started")


func test_unknown_request_refused_by_name() -> void:
	assert_true(run("{\"type\":\"teleport\"}").contains("teleport"), "names it")


# -- status -----------------------------------------------------------------------------------

func test_glove_status_reports_state_battery_and_gauge_pressure() -> void:
	connect_left()
	var p := PackedByteArray()
	for v in [101000.0, 100000.0, 100000.0, 100000.0, 100000.0, 100000.0, 145200.0]:
		p.append_array(HexRTlv.f32(v))
	hub.left.decoder.feed(HexRFrameDecoder.build_inbound(HexRTypes.InOp.PRESSURE, p))
	hub.left.decoder.feed(HexRFrameDecoder.build_inbound(HexRTypes.InOp.BATTERY, HexRTlv.f32(0.83)))
	var gloves := HexRRemoteCommands.glove_status(hub)
	assert_eq([gloves[0]["hand"], gloves[0]["state"], gloves[0]["batteryPct"]], ["left", "connected", 83], "left")
	assert_eq(gloves[0]["pressureDeciKPa"], [10, 0, 0, 0, 0, 0, 452], "gauge deci-kPa")
	assert_eq([gloves[1]["hand"], gloves[1]["state"], gloves[1]["batteryPct"]], ["right", "disconnected", -1], "right")
	assert_eq(gloves[1]["pressureDeciKPa"], [], "no pressure while disconnected")


func test_glove_status_with_no_rig_lists_both_hands_missing() -> void:
	var gloves := HexRRemoteCommands.glove_status(null)
	assert_eq(gloves.size(), 2, "both hands")
	assert_eq([gloves[0]["state"], gloves[1]["state"]], ["missing", "missing"], "missing")


func test_to_deci_kpa() -> void:
	assert_eq(HexRRemoteProtocol.to_deci_kpa(145200.0), 452, "absolute pascals")
	assert_eq(HexRRemoteProtocol.to_deci_kpa(45.2), 452, "gauge kPa")
	assert_eq(HexRRemoteProtocol.to_deci_kpa(NAN), 0, "NaN")
	assert_eq(HexRRemoteProtocol.round_half_even(2.5), 2, "half to even down")
	assert_eq(HexRRemoteProtocol.round_half_even(3.5), 4, "half to even up")
	assert_eq(HexRRemoteProtocol.round_half_even(-2.5), -2, "negative half")


func test_status_matches_the_reference_line() -> void:
	var line := HexRRemoteProtocol.to_line(HexRRemoteProtocol.status("q3-1", "Quest 3", "Oculus Quest 3", "quest",
			"HexR Demo", "1.2", "0.10.0", false, 71, HexRRemoteProtocol.scene_info(1, "Hospital Tutorial"),
			[HexRRemoteProtocol.scene_info(0, "Basic Tutorial"), HexRRemoteProtocol.scene_info(1, "Hospital Tutorial")],
			[HexRRemoteProtocol.glove_status("left", "connected", "Connected", 83, [10, 0, 0, 0, 0, 0, 452]),
			HexRRemoteProtocol.glove_status("right", "disconnected")],
			HexRRemoteProtocol.stream_status("live", 47802, 1024, 1024, 1, "",
					HexRRemoteProtocol.audio_status("live", 47803, 48000, 2)),
			[HexRRemoteProtocol.command_info("reset", "Reset demo")], true, true, true, 2, 1791966541289123))
	assert_eq(line, REFERENCE_STATUS, "status line")


func test_haptics_matches_the_reference_line() -> void:
	var line := HexRRemoteProtocol.to_line(HexRRemoteProtocol.haptics_message(1791966541289123, "right",
			[HexRRemoteProtocol.haptic_channel(1, "pressure", 80)]))
	assert_eq(line, REFERENCE_HAPTICS, "haptics line")


func test_protocol_version_matches_unity_package_level() -> void:
	assert_eq(HexRRemote.HEXR_VERSION, "0.10.5", "the Unity package level phones gate on")


func test_strings_are_cleaned_of_control_characters() -> void:
	var line := HexRRemoteProtocol.error_line("x", "a\u000bb\u0001c")
	assert_eq(line, "{\"type\":\"error\",\"request\":\"x\",\"message\":\"a b c\"}", "no control characters")


func test_scene_display_names() -> void:
	assert_eq(HexRRemoteProtocol.scene_display_name("res://scenes/2_hospital_tutorial.tscn"), "2 Hospital Tutorial", "snake case")
	assert_eq(HexRRemoteProtocol.scene_display_name("res://LivingHeart.tscn"), "Living Heart", "camel case")
	assert_eq(HexRRemoteProtocol.scene_display_name("res://FindTheLump.tscn"), "Find the Lump", "small words")
	assert_eq(HexRRemoteProtocol.scene_display_name("res://Basic Tutorial.tscn"), "Basic Tutorial", "spaces kept")


# -- haptics feed -----------------------------------------------------------------------------

func _parse(line: String) -> Dictionary:
	return JSON.parse_string(line)


func test_haptics_feed_press_then_release() -> void:
	var t: Array[int] = [1000]
	var feed := HexRRemoteHaptics.new(func() -> int: return t[0])
	var lines := []
	feed.poll(hub, lines)
	assert_eq(lines.size(), 0, "nothing on yet")
	hub.right.haptics.hexr_pressure(F.INDEX, true, 0.8, 1.0)
	t[0] = 2000
	feed.poll(hub, lines)
	assert_eq(lines.size(), 1, "one line")
	var on := _parse(lines[0])
	assert_eq([int(on["t"]), on["hand"], on["channels"].size()], [2000, "right", 1], "stamped, right, one channel")
	var ch: Dictionary = on["channels"][0]
	assert_eq([int(ch["finger"]), ch["mode"], int(ch["intensityPct"]), ch["tap"]], [1, "pressure", 80, false], "press")
	lines.clear()
	feed.poll(hub, lines)
	assert_eq(lines.size(), 0, "held: nothing new")
	hub.right.haptics.hexr_pressure(F.INDEX, false, 0.8, 1.0)
	feed.poll(hub, lines)
	var off: Dictionary = _parse(lines[0])["channels"][0]
	assert_eq([int(off["finger"]), off["mode"]], [1, "off"], "release")


func test_haptics_feed_on_and_off_in_one_frame_is_a_tap() -> void:
	var feed := HexRRemoteHaptics.new(func() -> int: return 1)
	var lines := []
	feed.poll(hub, lines)
	hub.left.haptics.hexr_vibration(F.PALM, true, 6.0, 0.5)
	hub.left.haptics.hexr_vibration(F.PALM, false, 6.0, 0.5)
	feed.poll(hub, lines)
	var tap: Dictionary = _parse(lines[0])["channels"][0]
	assert_eq([int(tap["finger"]), tap["mode"], int(tap["intensityPct"]), int(tap["frequencyDeciHz"]), tap["tap"]],
			[5, "vibration", 50, 60, true], "tap")


func test_haptics_feed_snapshot_has_every_channel() -> void:
	var feed := HexRRemoteHaptics.new(func() -> int: return 1)
	hub.left.haptics.hexr_pressure(F.THUMB, true, 1.0, 1.0)
	feed.poll(hub, [])
	var snapshot := feed.snapshot()
	assert_eq(snapshot.size(), 2, "both hands")
	var left := _parse(snapshot[0])
	assert_eq([left["hand"], left["channels"].size()], ["left", 6], "six channels")
	assert_eq([left["channels"][0]["mode"], int(left["channels"][0]["intensityPct"])], ["pressure", 100], "thumb on")
	assert_eq(left["channels"][1]["mode"], "off", "index off")


func test_haptics_feed_rig_going_away_turns_channels_off() -> void:
	var feed := HexRRemoteHaptics.new(func() -> int: return 1)
	var lines := []
	hub.right.haptics.hexr_pressure(F.RING, true, 0.5, 1.0)
	feed.poll(hub, lines)
	lines.clear()
	feed.poll(null, lines)
	var gone := _parse(lines[0])
	assert_eq([gone["hand"], int(gone["channels"][0]["finger"]), gone["channels"][0]["mode"]], ["right", 3, "off"], "off")
