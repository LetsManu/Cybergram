extends GdUnitTestSuite
## LoopbackTransport + NetSimConditioner: latency, loss, reliability.

const TICK: float = 1.0 / 30.0


func _pair(p: NetSimProfile) -> Array:
	var link := LoopbackLink.new(p)
	return [link, link.create_endpoint(1), link.create_endpoint(2)]


func _drain(t: LoopbackTransport) -> Array:
	t.poll()
	var out := []
	var pkt := t.pop_packet()
	while pkt != null:
		out.append(pkt)
		pkt = t.pop_packet()
	return out


func test_zero_latency_delivers_on_next_poll() -> void:
	var p: Array = _pair(NetFixtures.profile(0, 0, 0.0))
	p[2].send(1, Transport.CH_INPUT, PackedByteArray([42]))
	var got := _drain(p[1])
	assert_int(got.size()).is_equal(1)
	assert_int(got[0].from_peer).is_equal(2)
	assert_int(got[0].data[0]).is_equal(42)


func test_latency_holds_packet_until_due() -> void:
	var p: Array = _pair(NetFixtures.profile(100, 0, 0.0))
	var link: LoopbackLink = p[0]
	p[2].send(1, Transport.CH_SNAPSHOT, PackedByteArray([1]))
	link.advance(0.099)
	assert_int(_drain(p[1]).size()).is_equal(0)
	link.advance(0.001)
	assert_int(_drain(p[1]).size()).is_equal(1)


func test_loss_rate_matches_profile_on_unreliable_channel() -> void:
	var p: Array = _pair(NetFixtures.profile(0, 0, 0.02))
	var sent := 10000
	for i in sent:
		p[2].send(1, Transport.CH_INPUT, PackedByteArray([i & 0xFF]))
	var received := _drain(p[1]).size()
	var loss := 1.0 - float(received) / sent
	assert_float(loss).is_between(0.015, 0.025)


func test_reliable_channel_never_drops_and_keeps_order_under_jitter() -> void:
	var p: Array = _pair(NetFixtures.profile(50, 40, 0.5))
	var link: LoopbackLink = p[0]
	for i in 200:
		p[2].send(1, Transport.CH_EVENTS, PackedByteArray([i]))
		link.advance(TICK / 4.0)
	link.advance(1.0)
	var got := _drain(p[1])
	assert_int(got.size()).is_equal(200)
	for i in 200:
		assert_int(got[i].data[0]).is_equal(i)


func test_same_seed_gives_same_delivery() -> void:
	var counts := []
	for run in 2:
		var p: Array = _pair(NetFixtures.profile(30, 20, 0.1, 99))
		var link: LoopbackLink = p[0]
		var arrived := PackedInt32Array()
		for i in 300:
			p[2].send(1, Transport.CH_INPUT, PackedByteArray([i & 0xFF]))
			link.advance(TICK)
			arrived.append(_drain(p[1]).size())
		counts.append(arrived)
	assert_array(counts[0]).is_equal(counts[1])


func test_bytes_sent_are_counted_per_channel() -> void:
	var p: Array = _pair(NetFixtures.profile(0, 0, 0.0))
	p[2].send(1, Transport.CH_INPUT, PackedByteArray([1, 2, 3]))
	assert_int(p[2].bytes_sent[Transport.CH_INPUT]).is_equal(3)
