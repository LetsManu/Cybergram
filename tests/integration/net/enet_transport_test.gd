extends GdUnitTestSuite
## ENetTransport over real UDP on localhost: a ClientSession completes the
## Hello/Welcome handshake with a ServerSession (sent before the link was up,
## so it exercises the outbox), then a reliable event batch arrives intact.

const PORT := 47731
const MAX_POLLS := 200


func test_handshake_and_reliable_event_arrive_over_udp() -> void:
	var net := NetFixtures.net_config()
	var st := ENetTransport.listen(PORT, 4)
	assert_str(st.error_text).is_empty()
	var server := ServerSession.new(st, net)
	server.client_joined.connect(func(peer: int) -> void: server.accept(peer, 42, 1000))
	var ct := ENetTransport.connect_to("127.0.0.1", PORT)
	assert_str(ct.error_text).is_empty()
	var client := ClientSession.new(ct, net)
	var events: Array[GameEvent] = []
	client.event_received.connect(func(e: GameEvent, _t: int) -> void: events.append(e))
	client.connect_to_server()  # queued until the UDP link is up
	var sent_event := false
	for i in MAX_POLLS:
		server.poll()
		client.poll()
		if client.is_welcomed and not sent_event:
			var list: Array[GameEvent] = [GameEvent.shot(42, Vector3(1, 2, 3))]
			for peer in server.clients:
				server.send_events(peer, 1001, list)
			sent_event = true
		if not events.is_empty():
			break
		OS.delay_msec(5)
	assert_bool(client.is_welcomed).is_true()
	assert_int(client.own_net_id).is_equal(42)
	assert_int(server.clients.size()).is_equal(1)
	assert_int(events.size()).is_equal(1)
	assert_int(events[0].kind).is_equal(GameEvent.SHOT)
	assert_vector(events[0].position).is_equal(Vector3(1, 2, 3))
	ct.close()
	st.close()
