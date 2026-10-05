extends GdUnitTestSuite
## W16-NET measurement: SnapshotStats (server, per client) and ClientNetStats
## (client: jitter, loss, rates). Deterministic: fake clock in usec.

const TICK_US: int = 33333


func test_fragments_for_one_mtu_is_single_fragment() -> void:
	assert_int(SnapshotStats.fragments_for(SnapshotStats.ENET_FRAGMENT_PAYLOAD)).is_equal(1)
	assert_int(SnapshotStats.fragments_for(SnapshotStats.ENET_FRAGMENT_PAYLOAD + 1)).is_equal(2)


func test_window_summary_reports_avg_p95_max_and_resets() -> void:
	var s := SnapshotStats.new()
	for i in 20:
		var size := 100 if i < 19 else 2000
		s.on_send(Transport.CH_SNAPSHOT, size)
		s.on_snapshot(size, 1100)
	var w := s.take_window(1.0)
	assert_int(w.snaps).is_equal(20)
	assert_int(w.snap_max).is_equal(2000)
	assert_int(w.snap_p95).is_equal(100)
	assert_float(w.snap_avg).is_equal_approx(195.0, 0.01)
	assert_int(w.frag_snaps).is_equal(1)
	assert_int(w.over_budget).is_equal(1)
	assert_float(w.kbps[Transport.CH_SNAPSHOT]).is_equal_approx(3.9, 0.001)
	assert_int(s.take_window(1.0).snaps).is_equal(0)


func test_log_line_names_peer_id_only() -> void:
	var s := SnapshotStats.new()
	s.on_snapshot(500, 1100)
	var line := SnapshotStats.format_line(3, s.take_window(10.0), {"rtt_ms": 42, "rtt_var_ms": 5, "loss_pct": 1.5})
	assert_str(line).starts_with("[net] peer=3 ")
	assert_str(line).contains("rtt=42ms")
	assert_str(line).contains("loss=1.5%")


func test_server_session_stats_lines_are_rate_limited() -> void:
	var net := NetFixtures.net_config()
	net.stats_log_max_lines = 2
	var link := LoopbackLink.new()
	var session := ServerSession.new(link.create_endpoint(1), net)
	for peer in [2, 3, 4, 5]:
		session.accept(peer, peer * 10, 0)
	assert_int(session.stats_lines(0).size()).is_equal(0)
	assert_int(session.stats_lines(10).size()).is_equal(0)
	var lines := session.stats_lines(roundi(net.stats_log_interval_s * net.tick_rate_hz))
	assert_int(lines.size()).is_equal(3)
	assert_str(lines[2]).contains("2 more")


func test_steady_arrivals_have_zero_jitter_and_loss() -> void:
	var c := ClientNetStats.new(30, 30)
	for t in 30:
		c.on_snapshot(100 + t, 400, 5_000_000 + t * TICK_US)
	assert_float(c.jitter_p95_ms()).is_less(0.01)
	assert_float(c.loss_pct()).is_equal(0.0)
	assert_float(c.snapshot_avg_bytes()).is_equal(400.0)


func test_late_arrivals_raise_jitter_p95() -> void:
	var c := ClientNetStats.new(30, 20)
	for t in 20:
		var late := 40_000 if t % 4 == 0 else 0  # every 4th snapshot 40 ms late
		c.on_snapshot(t, 400, t * TICK_US + late)
	assert_float(c.jitter_p95_ms()).is_equal_approx(40.0, 0.5)


func test_tick_gaps_count_as_loss() -> void:
	var c := ClientNetStats.new(30, 20)
	for t in [0, 1, 2, 4, 5, 6, 7, 8, 9, 10]:
		c.on_snapshot(t, 400, t * TICK_US)
	assert_float(c.loss_pct()).is_equal_approx(100.0 / 11.0, 0.01)
	assert_int(c.snapshots_missed).is_equal(1)


func test_rates_cover_the_last_full_second() -> void:
	var c := ClientNetStats.new(30, 30)
	for t in 32:  # the 32nd sample closes the first 1 s bucket (31 samples)
		c.on_in(1000, t * TICK_US)
		c.on_out(100, t * TICK_US)
	assert_float(c.kbps_in()).is_equal_approx(30.0, 0.1)
	assert_float(c.kbps_out()).is_equal_approx(3.0, 0.01)
