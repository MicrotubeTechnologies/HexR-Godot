extends HexRTest
## HexR Remote over real sockets on this machine: discovery, the welcome, status, requests,
## refusals while paused, the line-length cut-off and port fallback.

const H := HaptGloveHandler.HandType
const BASE_PORT := 48801
const DISCOVERY := 48800

var hub: HexRManager
var sim: HexRSimulatedTransport
var remote: HexRRemote
var _blocker: TCPServer


func before_each() -> void:
	sim = HexRSimulatedTransport.new()
	sim.add_glove(HexRSimulatedGlove.new("AA:LEFT", HexRTypes.NAME_LEFT))
	hub = HexRManager.new()
	hub.setup(sim, HexRDeviceStore.new(""))
	add_child(hub)
	hub.make_current()


func after_each() -> void:
	if is_instance_valid(remote):
		remote.queue_free()
	if _blocker:
		_blocker.stop()
	await wait_frames(2)


func start_remote(port: int = BASE_PORT) -> void:
	remote = HexRRemote.new()
	remote.announce_address = "127.0.0.1"
	remote.discovery_port = DISCOVERY
	remote.control_port = port
	remote.status_per_second = 10.0
	add_child(remote)
	await wait_frames(2)
	assert_true(remote.is_running(), "remote started")


class Phone:
	var peer := StreamPeerTCP.new()
	var buf := PackedByteArray()
	var lines: Array[Dictionary] = []

	func open(port: int) -> void:
		peer.connect_to_host("127.0.0.1", port)

	func send(line: String) -> void:
		peer.put_data((line + "\n").to_utf8_buffer())

	func pump() -> void:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			buf.append_array(peer.get_partial_data(n)[1])
		while true:
			var nl := buf.find(10)
			if nl < 0:
				break
			var d: Variant = JSON.parse_string(buf.slice(0, nl).get_string_from_utf8())
			buf = buf.slice(nl + 1)
			if d is Dictionary:
				lines.append(d)

	func connected() -> bool:
		peer.poll()
		return peer.get_status() == StreamPeerTCP.STATUS_CONNECTED


## Connects the phone, polling until the socket is up (StreamPeerTCP only advances when polled).
func open_phone(phone: Phone) -> void:
	phone.open(remote.get_control_port())
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end and not phone.connected():
		await get_tree().process_frame
	assert_true(phone.connected(), "phone connected")


func wait_for(phone: Phone, predicate: Callable, ms: int = 3000) -> Dictionary:
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		phone.pump()
		for i in phone.lines.size():
			if predicate.call(phone.lines[i]):
				var found := phone.lines[i]
				phone.lines = phone.lines.slice(i + 1)
				return found
		await get_tree().process_frame
	return {}


func test_announces_on_udp() -> void:
	var udp := PacketPeerUDP.new()
	assert_eq(udp.bind(DISCOVERY, "127.0.0.1"), OK, "listening for announcements")
	await start_remote()
	var got := {}
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end and got.is_empty():
		if udp.get_available_packet_count() > 0:
			got = JSON.parse_string(udp.get_packet().get_string_from_utf8())
		await get_tree().process_frame
	udp.close()
	assert_false(got.is_empty(), "heard an announcement")
	assert_eq(got.keys(), ["hexr", "type", "id", "name", "model", "platform", "app", "appId", "hexrVersion",
			"control", "video", "startedAt"], "announce field order")
	assert_eq([int(got["hexr"]), got["type"], int(got["control"]), got["hexrVersion"]],
			[1, "announce", remote.get_control_port(), "0.10.5"], "announce values")


func test_hello_gets_welcome_then_haptics_then_status() -> void:
	await start_remote()
	var phone := Phone.new()
	await open_phone(phone)
	phone.send("{\"type\":\"hello\",\"protocol\":1,\"client\":\"HexR Companion\"}")
	var welcome := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "hello")
	assert_eq(welcome.keys(), ["type", "protocol", "id", "control", "video"], "welcome fields")
	assert_eq(int(welcome["control"]), remote.get_control_port(), "welcome control port")
	var left := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "haptics" and d.get("hand") == "left")
	assert_eq(left.get("channels", []).size(), 6, "left snapshot has six channels")
	var right := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "haptics" and d.get("hand") == "right")
	assert_eq(right.get("channels", []).size(), 6, "right snapshot has six channels")
	var status := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "status")
	assert_eq(status.keys(), ["type", "protocol", "id", "name", "model", "platform", "app", "appVersion",
			"hexrVersion", "paused", "headsetBatteryPct", "scene", "scenes", "gloves", "stream", "commands",
			"allowGloveControl", "allowVideo", "exposeScenes", "controllers", "haptics", "clockUs"], "status field order")
	assert_eq(status["stream"]["state"], "unsupported", "no view sharing off the headset")
	# The first status may predate this phone; a later one counts it.
	var counted := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "status" and int(d["controllers"]) == 1)
	assert_false(counted.is_empty(), "status counts one phone")


func test_glove_connect_from_a_phone() -> void:
	await start_remote()
	var phone := Phone.new()
	await open_phone(phone)
	phone.send("{\"type\":\"glove\",\"action\":\"connect\",\"hand\":\"left\"}")
	var connected := await wait_for(phone, func(d: Dictionary) -> bool:
		return d.get("type") == "status" and d["gloves"][0]["state"] == "connected", 5000)
	assert_false(connected.is_empty(), "status reports the left glove connected")
	assert_true(hub.is_hand_connected(H.LEFT), "really connected")
	hub.left_hand.bt_send(hub.left_hand.haptics.hexr_pressure(Haptics.Finger.INDEX, true, 0.8, 1.0))
	var press := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "haptics" and d["hand"] == "left")
	assert_eq([int(press["channels"][0]["finger"]), press["channels"][0]["mode"], int(press["channels"][0]["intensityPct"])],
			[1, "pressure", 80], "the phone saw the press")


func test_errors_come_back_to_the_asking_phone() -> void:
	await start_remote()
	var phone := Phone.new()
	await open_phone(phone)
	phone.send("{\"type\":\"command\",\"id\":\"nope\"}")
	var err := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "error")
	assert_eq([err.get("request"), err.get("message")], ["command", "This app has no command \"nope\"."], "error line")
	phone.send("not json")
	err = await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "error")
	assert_eq([err.get("request"), err.get("message")], ["", "That request is not JSON."], "parse error")


func test_paused_refuses_requests_but_answers_hello() -> void:
	await start_remote()
	var phone := Phone.new()
	await open_phone(phone)
	remote._set_paused(true)
	var status := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "status" and d.get("paused") == true)
	assert_false(status.is_empty(), "status says paused")
	phone.send("{\"type\":\"release\"}")
	var err := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "error")
	assert_eq(err.get("message"), HexRRemoteServer.PAUSED_MESSAGE, "refused while paused")
	phone.send("{\"type\":\"hello\",\"protocol\":1}")
	var welcome := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "hello")
	assert_false(welcome.is_empty(), "hello still answered")
	remote._set_paused(false)


func test_overlong_line_closes_the_connection() -> void:
	await start_remote()
	var phone := Phone.new()
	await open_phone(phone)
	var junk := PackedByteArray()
	junk.resize(HexRRemoteProtocol.MAX_LINE_BYTES + 100)
	junk.fill(0x41)
	phone.peer.put_data(junk)
	var end := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < end and phone.connected():
		phone.pump()
		await get_tree().process_frame
	assert_false(phone.connected(), "dropped after 16 KiB without a newline")


func test_port_fallback() -> void:
	_blocker = TCPServer.new()
	assert_eq(_blocker.listen(BASE_PORT + 20, "*"), OK, "blocking the preferred port")
	await start_remote(BASE_PORT + 20)
	# The next free one: on a CI runner an outgoing connection can hold the very next port.
	var p := remote.get_control_port()
	assert_true(p > BASE_PORT + 20 and p <= BASE_PORT + 29, "moved to one of the next nine ports (got %d)" % p)


func test_registered_command_runs_from_a_phone() -> void:
	await start_remote()
	var runs: Array[int] = []
	HexRRemote.register_command("reset", "Reset demo", func() -> void: runs.append(1))
	var phone := Phone.new()
	await open_phone(phone)
	var status := await wait_for(phone, func(d: Dictionary) -> bool: return d.get("type") == "status" and not d["commands"].is_empty())
	assert_eq(status["commands"], [{"id": "reset", "label": "Reset demo"}], "listed in the status")
	phone.send("{\"type\":\"command\",\"id\":\"reset\"}")
	var end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < end and runs.is_empty():
		await get_tree().process_frame
	assert_eq(runs.size(), 1, "ran once")
	HexRRemote.unregister_command("reset")
