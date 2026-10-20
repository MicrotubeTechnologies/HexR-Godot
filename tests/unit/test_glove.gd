extends HexRTest
## The connect campaign, releases and write rules, against the simulated firmware glove.
## Ports of the Unity package's ConnectionTests, DisconnectStatusTests and ReleaseTests.

const H := HaptGloveHandler.HandType
const F := Haptics.Finger

var hub: HexRManager
var sim: HexRSimulatedTransport
var lg: HexRSimulatedGlove
var now := 1000
var events: Array[String] = []


func before_each() -> void:
	sim = HexRSimulatedTransport.new()
	lg = sim.add_glove(HexRSimulatedGlove.new("AA:LEFT", HexRTypes.NAME_LEFT))
	hub = HexRManager.new()
	hub.drive_from_process = false
	hub.setup(sim, HexRDeviceStore.new(""))
	add_child(hub)
	for sig in ["glove_connected", "glove_disconnected", "glove_connect_failed", "connect_attempt_ended"]:
		hub.connect(sig, func(hand: int) -> void: events.append("%s:%s" % [sig, HexRTypes.hand_name(hand)]))
	hub.tick(now)


func after_each() -> void:
	hub.drive_from_process = false


func advance(ms: int, step: int = 10) -> void:
	var end := now + ms
	while now < end:
		now += step
		hub.tick(now)


func test_scan_connect_and_subscribe_once() -> void:
	hub.connect_hand(H.LEFT)
	assert_true(hub.is_hand_connecting(H.LEFT), "connecting")
	advance(1000)
	assert_true(hub.is_hand_connected(H.LEFT), "connected")
	assert_false(hub.is_hand_connecting(H.LEFT), "no longer connecting")
	assert_eq(lg.subscriptions_this_connection, 1, "subscribed exactly once")
	assert_eq(hub.left_hand.get_remembered_device_id(), "AA:LEFT", "remembers the glove")
	assert_true(events.has("glove_connected:Left"), "event")


func test_connect_hand_is_idempotent() -> void:
	hub.connect_hand(H.LEFT)
	hub.connect_hand(H.LEFT)
	advance(1000)
	hub.connect_hand(H.LEFT)
	advance(500)
	assert_eq(lg.connections, 1, "one connection")


func test_pump_starts_two_seconds_after_connect() -> void:
	hub.connect_hand(H.LEFT)
	advance(500)
	assert_true(hub.is_hand_connected(H.LEFT), "connected")
	advance(1500)
	assert_eq(lg.frames_with_op(Haptics.FunIndex.FI_STABLE_PRESSURE_CTRL).size(), 0, "not yet")
	advance(400)
	var pumps := lg.frames_with_op(Haptics.FunIndex.FI_STABLE_PRESSURE_CTRL)
	assert_eq(pumps.size(), 1, "pump sent once")
	assert_bytes(pumps[0], "06 02 01 01 01 50", "pump start bytes")


func test_second_connect_starts_pump_again() -> void:
	# The Unity package never reset its pump flag, so the second connect sent "stop".
	hub.connect_hand(H.LEFT)
	advance(3000)
	hub.disconnect_hand(H.LEFT)
	advance(100)
	hub.connect_hand(H.LEFT)
	advance(3000)
	var pumps := lg.frames_with_op(Haptics.FunIndex.FI_STABLE_PRESSURE_CTRL)
	assert_eq(pumps.size(), 2, "two pump commands")
	assert_bytes(pumps[1], "06 02 01 01 01 50", "second is start, not stop")


func test_disconnect_releases_first() -> void:
	hub.connect_hand(H.LEFT)
	advance(500)
	hub.left_hand.bt_send(hub.left_hand.haptics.hexr_pressure(F.INDEX, true, 0.8, 1.0))
	advance(200)
	assert_true(lg.any_channel_on(), "index pressing")
	var before := lg.received_frames.size()
	hub.disconnect_hand(H.LEFT)
	assert_false(hub.is_hand_connected(H.LEFT), "disconnected")
	assert_false(hub.is_hand_connecting(H.LEFT), "not reconnecting after a requested disconnect")
	assert_eq(lg.received_frames.size() - before, 12, "release-all arrived before the link closed")
	assert_false(lg.any_channel_on(), "nothing left pressing")
	assert_true(events.has("glove_disconnected:Left"), "event")


func test_writes_are_batched_and_fit_mtu() -> void:
	lg.mtu = 64
	hub.connect_hand(H.LEFT)
	advance(500)
	var before := lg.received_frames.size()
	for f in 6:
		hub.left_hand.bt_send(hub.left_hand.haptics.hexr_pressure(f, true, 0.5, 1.0))
	assert_eq(lg.received_frames.size(), before, "nothing written in the same frame")
	advance(120)
	assert_eq(lg.received_frames.size() - before, 6, "all six arrive")
	assert_eq(lg.dropped_long_writes, 0, "no write over MTU - 3")


func test_failed_attempts_back_off_then_give_up() -> void:
	lg.advertising = false
	hub.connect_hand(H.LEFT)
	advance(8500, 50)  # one 8 s scan
	assert_eq(events.count("glove_connect_failed:Left"), 1, "first scan failed")
	assert_true(hub.is_hand_connecting(H.LEFT), "retrying")
	# Each attempt is an 8 s scan plus the backoff; the first failure after 60 s ends it.
	advance(75000, 50)
	assert_false(hub.is_hand_connecting(H.LEFT), "gave up after 60 s")
	assert_true(events.has("connect_attempt_ended:Left"), "campaign ended")
	assert_true(hub.left_hand.status_text.contains("not found"), "status says so")


func test_cancel_during_retry() -> void:
	lg.advertising = false
	hub.connect_hand(H.LEFT)
	advance(8300)
	assert_true(hub.is_hand_connecting(H.LEFT), "waiting to retry")
	hub.toggle_hand(H.LEFT)
	assert_false(hub.is_hand_connecting(H.LEFT), "cancelled")
	assert_true(events.has("connect_attempt_ended:Left"), "campaign ended")
	lg.advertising = true
	advance(20000)
	assert_false(hub.is_hand_connected(H.LEFT), "no retry after cancel")


func test_retry_connects_when_glove_appears() -> void:
	lg.fail_next_connects = 2
	hub.connect_hand(H.LEFT)
	advance(10000)
	assert_true(hub.is_hand_connected(H.LEFT), "connected after two failures")
	assert_eq(lg.subscriptions_this_connection, 1, "subscribed once on the good link")


func test_drop_reopens_campaign_and_reconnects_directly() -> void:
	hub.connect_hand(H.LEFT)
	advance(500)
	assert_true(hub.is_hand_connected(H.LEFT), "connected")
	var seen: Array[bool] = []  # lambdas capture locals by value, so collect into an array
	hub.glove_disconnected.connect(func(_h: int) -> void: seen.append(hub.is_hand_connecting(H.LEFT)))
	lg.drop_at_ms = now + 50
	advance(100)
	assert_false(hub.is_hand_connected(H.LEFT), "dropped")
	assert_eq(seen, [true] as Array[bool], "listeners see is_connecting() during the event")
	assert_true(hub.left_hand.status_text.contains("reconnecting"), "status")
	advance(2000)
	assert_true(hub.is_hand_connected(H.LEFT), "reconnected")
	assert_eq(lg.connections, 2, "second connection")
	assert_eq(lg.subscriptions_this_connection, 1, "subscribed once again")


func test_remembered_glove_skips_scan_and_falls_back() -> void:
	hub.left_hand.remember_device("AA:LEFT")
	hub.connect_hand(H.LEFT)
	assert_false(sim.is_scanning(), "no scan for a remembered glove")
	advance(500)
	assert_true(hub.is_hand_connected(H.LEFT), "direct connect")
	hub.disconnect_hand(H.LEFT)
	# The remembered glove is gone; a second glove for the same hand must not be taken.
	hub.left_hand.remember_device("AA:GONE")
	var other := sim.add_glove(HexRSimulatedGlove.new("BB:LEFT", HexRTypes.NAME_LEFT))
	hub.connect_hand(H.LEFT)
	advance(1000)
	assert_true(sim.is_scanning() or hub.is_hand_connecting(H.LEFT), "fell back to a scan")
	assert_false(other.connected, "did not take another left glove")
	hub.left_hand.forget_device()
	hub.disconnect_hand(H.LEFT)
	hub.connect_hand(H.LEFT)
	advance(1000)
	assert_true(hub.is_hand_connected(H.LEFT), "connects by name once forgotten")


func test_watchdog_restarts_a_silent_attempt() -> void:
	lg.connect_delay_ms = 25000  # the platform never answers within 20 s
	hub.connect_hand(H.LEFT)
	advance(20500, 50)
	assert_true(hub.left_hand.status_text.begins_with("Connection attempt timed out"),
			"watchdog fired: " + hub.left_hand.status_text)
	assert_true(hub.is_hand_connecting(H.LEFT), "retry scheduled")
	lg.connect_delay_ms = 100
	advance(5000, 50)
	assert_true(hub.is_hand_connected(H.LEFT), "connected after the watchdog retry")


func test_pause_frame_is_release_all() -> void:
	hub.connect_hand(H.LEFT)
	advance(500)
	assert_eq(sim.get_pause_release_frame("AA:LEFT").size(), 216, "release registered for pause")
	hub.left_hand.release_when_paused = false
	assert_eq(sim.get_pause_release_frame("AA:LEFT").size(), 0, "cleared when disabled")
	hub.left_hand.release_when_paused = true
	hub.disconnect_hand(H.LEFT)
	assert_eq(sim.get_pause_release_frame("AA:LEFT").size(), 0, "cleared on disconnect")


func test_pause_notification_releases() -> void:
	hub.connect_hand(H.LEFT)
	advance(500)
	hub.left_hand.bt_send(hub.left_hand.haptics.hexr_vibration(F.PALM, true, 18.0, 0.8))
	advance(200)
	assert_true(lg.any_channel_on(), "palm vibrating")
	hub.left_hand.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_false(lg.any_channel_on(), "released on pause")


func test_commands_dropped_while_disconnected() -> void:
	assert_false(hub.left_hand.bt_send(PackedByteArray([1, 2, 3])), "refused")
	assert_false(hub.left_hand.coalescer.has_pending(), "not queued for later")


func test_telemetry_and_battery() -> void:
	var states: Array[int] = []
	hub.battery_state_changed.connect(func(_h: int, s: int) -> void: states.append(s))
	lg.battery = 0.5
	hub.connect_hand(H.LEFT)
	advance(1500)
	assert_almost(hub.left_hand.get_battery_level(), 0.5, 1e-6, "battery read")
	assert_eq(states, [HaptGloveHandler.BatteryState.MEDIUM] as Array[int], "battery state")
	assert_eq(hub.left_hand.get_finger_position(), lg.finger_position, "positions")
	assert_almost(hub.left_hand.get_air_pressure_kpa()[6], 80.0, 1e-4, "source pressure")
	lg.battery = 0.1
	advance(1500)
	assert_eq(states.back(), HaptGloveHandler.BatteryState.LOW, "low battery")


func test_two_hands_share_one_scan() -> void:
	var rg := sim.add_glove(HexRSimulatedGlove.new("AA:RIGHT", HexRTypes.NAME_RIGHT))
	hub.connect_hand(H.LEFT)
	hub.connect_hand(H.RIGHT)
	advance(1000)
	assert_true(hub.is_hand_connected(H.LEFT) and hub.is_hand_connected(H.RIGHT), "both connected")
	assert_true(rg.connected and lg.connected, "both simulated gloves linked")
	assert_false(sim.is_scanning(), "scan stopped once both were found")


func test_simulated_link_cut_to_mtu_23() -> void:
	lg.mtu = 23
	hub.connect_hand(H.LEFT)
	advance(500)
	hub.left_hand.release_all_channels()
	advance(200)
	assert_eq(lg.dropped_long_writes, 0, "release cut into single-frame writes")
	assert_eq(lg.frames_with_op(Haptics.FunIndex.FI_SET_PRESSURE).size(), 6, "all pressure exits arrived")
