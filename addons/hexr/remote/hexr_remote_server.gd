class_name HexRRemoteServer
extends RefCounted
## HexR Remote's network side (port of the Unity package's RemoteServer and RemoteDiscovery):
## the TCP control port phones connect to, and the UDP announcement they find it by.
##
## One thread does all the socket work, so a slow phone never holds up a frame, and so the
## status keeps going out once a second while the app is paused (its main loop stops then).
## The main thread hands it lines and takes requests through the methods below.
##
## The thread answers hello and ping itself, and refuses everything else while paused, as the
## Unity package does: run later, a scene change or a capture prompt would land in front of
## whoever puts the headset on next.

const PORT_ATTEMPTS := 10
const IDLE_TIMEOUT_MS := 15000
const HEARTBEAT_MS := 1000
const WRITE_TIMEOUT_MS := 5000
const ANNOUNCE_INTERVAL_MS := 2000
const PAUSE_PROBE_MS := 250
const LOOP_SLEEP_MS := 5
const PAUSED_MESSAGE := "The headset is asleep or not being worn. Try again once it is in use."

## The control port actually in use.
var port := 0
var discovery_port := HexRRemoteProtocol.DEFAULT_DISCOVERY_PORT
## Where the announcement goes. Tests point it at 127.0.0.1.
var announce_address := "255.255.255.255"
## Polled from the network thread: true while the app is paused. On Android this asks the
## HexRBle plugin, which knows even when no script is running.
var pause_probe: Callable

var _tcp := TCPServer.new()
var _udp := PacketPeerUDP.new()
var _thread: Thread
var _mutex := Mutex.new()
var _running := false
var _clients: Array = []  # owned by the thread

# Shared with the main thread, under _mutex.
var _inbox: Array = []
var _events: PackedStringArray = []
var _replies: Array = []
var _welcome := ""
var _status := ""
var _status_dict: Dictionary = {}
var _snapshot := PackedStringArray()
var _announce := PackedByteArray()
var _announce_now := false
var _paused := false
var _client_count := 0
var _next_id := 1


## Opens the control port (the preferred one, the next nine, then any free one) and starts the
## network thread. Returns false if no port could be opened.
func start(preferred_port: int, p_discovery_port: int) -> bool:
	for i in PORT_ATTEMPTS + 1:
		var p := 0 if i == PORT_ATTEMPTS else preferred_port + i
		if _tcp.listen(p, "*") == OK:
			break
	if not _tcp.is_listening():
		return false
	port = _tcp.get_local_port()
	discovery_port = p_discovery_port
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address(announce_address, discovery_port)
	_running = true
	_thread = Thread.new()
	_thread.start(_loop)
	return true


func stop() -> void:
	if not _running:
		return
	_running = false
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	for c in _clients:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	_tcp.stop()
	_udp.close()


func is_running() -> bool:
	return _running


# -- main thread API ------------------------------------------------------------------------

func set_welcome(line: String) -> void:
	_mutex.lock()
	_welcome = line
	_mutex.unlock()


## The newest status. Phones get it as soon as it changes, and again every second regardless.
func publish_status(message: Dictionary) -> void:
	var line := HexRRemoteProtocol.to_line(message)
	_mutex.lock()
	_status = line
	_status_dict = message.duplicate(true)
	_mutex.unlock()


## A line for every phone, in order (haptics).
func publish_event(line: String) -> void:
	_mutex.lock()
	_events.append(line)
	_mutex.unlock()


func reply(client_id: int, line: String) -> void:
	_mutex.lock()
	_replies.append([client_id, line])
	_mutex.unlock()


## What a phone gets right after the welcome: one haptics line per hand.
func set_snapshot(lines: PackedStringArray) -> void:
	_mutex.lock()
	_snapshot = lines
	_mutex.unlock()


func set_announce(message: Dictionary) -> void:
	var bytes := HexRRemoteProtocol.to_line(message).to_utf8_buffer()
	_mutex.lock()
	_announce = bytes
	_announce_now = true
	_mutex.unlock()


func set_paused(paused: bool) -> void:
	_mutex.lock()
	_paused = paused
	_mutex.unlock()


func client_count() -> int:
	_mutex.lock()
	var n := _client_count
	_mutex.unlock()
	return n


## Requests waiting for the main thread: [{"client", "request", "received_ms"}], oldest first.
## At most [param limit] are taken; the rest wait for the next call.
func take_requests(limit: int = 16) -> Array:
	_mutex.lock()
	var taken := _inbox.slice(0, limit)
	_inbox = _inbox.slice(limit)
	_mutex.unlock()
	return taken


# -- the network thread ---------------------------------------------------------------------

func _loop() -> void:
	var next_announce := 0
	var next_probe := 0
	while _running:
		var now := Time.get_ticks_msec()
		while _tcp.is_connection_available():
			var peer := _tcp.take_connection()
			if peer == null:
				break
			peer.set_no_delay(true)
			_clients.append({"id": _next_id, "peer": peer, "in": PackedByteArray(), "out": PackedByteArray(),
				"last_read": now, "last_send": 0, "sent_status": "", "stall_since": -1})
			_next_id += 1

		if pause_probe.is_valid() and now >= next_probe:
			next_probe = now + PAUSE_PROBE_MS
			_apply_probe(bool(pause_probe.call()))

		_mutex.lock()
		var events := _events
		_events = PackedStringArray()
		var replies := _replies
		_replies = []
		var status := _status
		var welcome := _welcome
		var snapshot := _snapshot
		var paused := _paused
		var announce := _announce
		var announce_now := _announce_now
		_announce_now = false
		_mutex.unlock()

		for c in _clients.duplicate():
			if not _service(c, now, events, replies, status, welcome, snapshot, paused):
				_close(c)

		if not announce.is_empty() and (announce_now or now >= next_announce):
			next_announce = now + ANNOUNCE_INTERVAL_MS
			_udp.put_packet(announce)

		_mutex.lock()
		_client_count = _clients.size()
		_mutex.unlock()
		OS.delay_msec(LOOP_SLEEP_MS)


## The probe saw the app pause or resume. While paused nothing on the main thread runs, so the
## status that keeps going out has to say so here.
func _apply_probe(paused: bool) -> void:
	_mutex.lock()
	if paused != _paused:
		_paused = paused
		if not _status_dict.is_empty():
			_status_dict["paused"] = paused
			_status = HexRRemoteProtocol.to_line(_status_dict)
	_mutex.unlock()


## Reads, answers and writes for one phone. Returns false to drop it.
func _service(c: Dictionary, now: int, events: PackedStringArray, replies: Array, status: String,
		welcome: String, snapshot: PackedStringArray, paused: bool) -> bool:
	var peer: StreamPeerTCP = c["peer"]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false

	var available := peer.get_available_bytes()
	if available > 0:
		var got := peer.get_partial_data(available)
		if got[0] != OK:
			return false
		# Packed arrays are values: change a copy and store it back.
		var inbuf: PackedByteArray = c["in"]
		inbuf.append_array(got[1])
		c["in"] = inbuf
		c["last_read"] = now
		while true:
			var buf: PackedByteArray = c["in"]
			var nl := buf.find(10)
			if nl < 0:
				if buf.size() > HexRRemoteProtocol.MAX_LINE_BYTES:
					return false
				break
			if nl > HexRRemoteProtocol.MAX_LINE_BYTES:
				return false
			var text := buf.slice(0, nl).get_string_from_utf8().trim_suffix("\r")
			c["in"] = buf.slice(nl + 1)
			if not text.is_empty():
				_on_line(c, text, now, welcome, snapshot, paused)
	elif now - int(c["last_read"]) > IDLE_TIMEOUT_MS:
		return false

	for line in events:
		_queue(c, line, now)
	for r in replies:
		if r[0] == c["id"]:
			_queue(c, r[1], now)
	if not status.is_empty() and (status != c["sent_status"] or now - int(c["last_send"]) >= HEARTBEAT_MS):
		_queue(c, status, now)
		c["sent_status"] = status

	var out: PackedByteArray = c["out"]
	if not out.is_empty():
		var sent := peer.put_partial_data(out)
		if sent[0] != OK:
			return false
		if sent[1] > 0:
			c["out"] = out.slice(sent[1])
			c["stall_since"] = -1
		elif int(c["stall_since"]) < 0:
			c["stall_since"] = now
		elif now - int(c["stall_since"]) > WRITE_TIMEOUT_MS:
			return false
	return true


func _on_line(c: Dictionary, text: String, now: int, welcome: String, snapshot: PackedStringArray, paused: bool) -> void:
	var parsed := HexRRemoteProtocol.try_parse(text)
	if parsed.has("error"):
		_queue(c, HexRRemoteProtocol.error_line("", parsed["error"]), now)
		return
	var req: Dictionary = parsed["request"]
	match req["type"]:
		"ping":
			return
		"hello":
			_queue(c, welcome, now)
			for line in snapshot:
				_queue(c, line, now)
			return
	if paused:
		_queue(c, HexRRemoteProtocol.error_line(req["type"], PAUSED_MESSAGE), now)
		return
	_mutex.lock()
	_inbox.append({"client": c["id"], "request": req, "received_ms": now})
	_mutex.unlock()


func _queue(c: Dictionary, line: String, now: int) -> void:
	if line.is_empty():
		return
	var out: PackedByteArray = c["out"]
	out.append_array((line + "\n").to_utf8_buffer())
	c["out"] = out
	c["last_send"] = now


func _close(c: Dictionary) -> void:
	(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_clients.erase(c)
