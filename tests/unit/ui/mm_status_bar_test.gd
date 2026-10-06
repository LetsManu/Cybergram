extends GdUnitTestSuite
## P1: the status bar's view-model (connection, phase, queue timer with
## estimate, lockout, hints when a wait runs long), the client event log
## behind the diagnostics panel, and the bar inside the matchmaking flow.
## Visual look: docs/manual-checklist.md (needs a human).

const P := PhaseMachine.Player


func _cfg() -> ConnectionWatchConfig:
	var c := ConnectionWatchConfig.new()
	c.connect_timeout_s = 10.0
	c.phase_timeout_s = 10.0
	c.long_wait_factor = 2.0
	c.loading_hint_s = 45.0
	return c


func test_queue_timer_counts_up_from_the_server_value_with_estimate() -> void:
	var m := MmStatusModel.new(_cfg())
	m.set_connection(MmStatusModel.Conn.ONLINE, 0.0, 42)
	m.set_phase({"phase": P.QUEUED, "waited": 70, "estimate": 120, "locked": 0}, 100.0)
	var v := m.view(105.0)
	assert_str(v.connection).is_equal("HUD_MMS_CONN_ONLINE")
	assert_str(v.ping).is_equal("42 ms")
	assert_str(v.phase).is_equal("HUD_MMS_PH_QUEUED")
	assert_str(v.timer).is_equal("1:15  ~2:00")
	assert_str(v.hint).is_empty()
	assert_str(v.tone).is_equal("busy")


func test_long_wait_explains_itself() -> void:
	var m := MmStatusModel.new(_cfg())
	m.set_connection(MmStatusModel.Conn.ONLINE, 0.0)
	m.set_phase({"phase": P.QUEUED, "waited": 236, "estimate": 120}, 0.0)  # 236 + 5 > 2 x 120
	assert_str(m.view(5.0).hint).is_equal("HUD_MMS_HINT_LONG_WAIT")


func test_loading_hint_after_the_limit() -> void:
	var m := MmStatusModel.new(_cfg())
	m.set_connection(MmStatusModel.Conn.ONLINE, 0.0)
	m.set_phase({"phase": P.LOADING}, 0.0)
	assert_str(m.view(44.0).hint).is_empty()
	var v := m.view(46.0)
	assert_str(v.hint).is_equal("HUD_MMS_HINT_LOADING_SLOW")
	assert_str(v.timer).is_equal("0:46")
	assert_str(v.tone).is_equal("warn")


func test_lockout_counts_down_and_explains() -> void:
	var m := MmStatusModel.new(_cfg())
	m.set_connection(MmStatusModel.Conn.ONLINE, 0.0)
	m.set_phase({"phase": P.IDLE, "locked": 90}, 0.0)
	var v := m.view(30.0)
	assert_str(v.lockout).is_equal("1:00")
	assert_str(v.hint).is_equal("HUD_MMS_HINT_LOCKED")
	assert_str(m.view(91.0).lockout).is_empty()


func test_no_endless_connecting_or_missing_state() -> void:
	var m := MmStatusModel.new(_cfg())
	m.set_connection(MmStatusModel.Conn.CONNECTING, 0.0)
	assert_str(m.view(5.0).hint).is_empty()
	assert_str(m.view(11.0).hint).is_equal("HUD_MMS_HINT_NO_SERVER")
	m.set_connection(MmStatusModel.Conn.ONLINE, 20.0)
	assert_str(m.view(25.0).hint).is_empty()
	assert_str(m.view(31.0).hint).is_equal("HUD_MMS_HINT_NO_STATE")
	m.set_connection(MmStatusModel.Conn.LOST, 40.0)
	assert_str(m.view(40.0).hint).is_equal("HUD_MMS_HINT_RECONNECTING")
	assert_str(m.view(40.0).tone).is_equal("error")


func test_every_phase_has_a_string() -> void:
	HudStrings.ensure_loaded()
	assert_int(MmStatusModel.PHASE_KEYS.size()).is_equal(P.size())
	for k: String in MmStatusModel.PHASE_KEYS:
		assert_str(TranslationServer.translate(k)).is_not_equal(k)


func test_clock_format() -> void:
	assert_str(MmStatusModel.clock(0)).is_equal("0:00")
	assert_str(MmStatusModel.clock(59.9)).is_equal("0:59")
	assert_str(MmStatusModel.clock(3725)).is_equal("1:02:05")
	assert_str(MmStatusModel.clock(-4)).is_equal("0:00")


func test_event_log_keeps_the_last_entries_and_formats_them() -> void:
	var log := ClientEventLog.new()
	var t := [10.0]
	log.clock = func() -> float: return t[0]
	for i in ClientEventLog.MAX + 5:
		t[0] += 1.0
		log.add("phase", "step %d" % i, {"seq": i})
	assert_int(log.entries.size()).is_equal(ClientEventLog.MAX)
	var text := log.to_text("head")
	assert_str(text).starts_with("head\n+   0.00s phase    step 5 {seq=5}")
	assert_str(text).contains("step %d" % (ClientEventLog.MAX + 4))


func test_adapter_logs_phases_and_never_the_ticket() -> void:
	var mm := MatchmakingClient.new(null)
	var a := MmClientAdapter.new(mm)
	var got: Array = []
	a.phase_changed.connect(func(d: Dictionary) -> void: got.append(d))
	mm.handle(MatchmakingCodec.encode_event(MatchmakingCodec.EV_PHASE, MatchmakingCodec.OK, {"epoch": 1, "seq": 1,
		"phase": P.QUEUED, "prev": P.IDLE, "snap": 1, "queue": 0, "party_size": 1, "leader": 1, "waited": 0,
		"estimate": 60, "locked": 0, "match": "", "party": ""}))
	mm.handle(MatchmakingCodec.encode_event(MatchmakingCodec.EV_MATCH_ASSIGNED, MatchmakingCodec.OK, {
		"host": "h", "port": 7801, "ticket": "cgt1.secret", "match": "m", "team": 0, "hero": 1, "map": "front"}))
	assert_int(got.size()).is_equal(1)
	var text := a.diagnostics_text()
	assert_str(text).contains("Idle -> Queued")
	assert_str(text).contains("port=7801")
	assert_str(text).not_contains("cgt1.secret")


func test_bar_lives_in_the_flow_with_the_fake_client() -> void:
	var flow: MatchmakingFlow = auto_free(MatchmakingFlow.new())
	flow.client = MatchmakingFakeClient.new()
	flow.with_model = false
	add_child(flow)
	await get_tree().process_frame
	assert_object(flow.status_bar).is_not_null()
	assert_bool(flow.status_bar.is_inside_tree()).is_true()
	flow.status_bar.toggle_diagnostics()
	await get_tree().process_frame
	assert_bool(flow.status_bar._diag.visible).is_true()
