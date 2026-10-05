extends GdUnitTestSuite
## W21-U2: the online connection watchdog, the queue-join timeout and the
## error card.

var _lines: Array[String] = []
var _reasons: Array[String] = []


func _watch(connect_s: float = 10.0, login_s: float = 10.0) -> ConnectionWatch:
	var cfg := ConnectionWatchConfig.new()
	cfg.connect_timeout_s = connect_s
	cfg.login_timeout_s = login_s
	var w := ConnectionWatch.new(cfg)
	_lines.clear()
	_reasons.clear()
	w.log_sink = func(l: String) -> void: _lines.append(l)
	w.failed.connect(func(k: String) -> void: _reasons.append(k))
	return w


func test_no_link_times_out_with_a_message() -> void:
	var w := _watch()
	w.begin("host:7777", true)
	w.tick(9.0)
	assert_array(_reasons).is_empty()
	w.tick(1.5)
	assert_array(_reasons).is_equal(["HUD_NET_ERR_TIMEOUT"])
	assert_int(w.phase).is_equal(ConnectionWatch.Phase.FAILED)


func test_link_up_but_no_login_answer_times_out() -> void:
	var w := _watch()
	w.begin("host:7777", true)
	w.tick(3.0)
	w.on_link_up()
	w.tick(9.0)
	assert_array(_reasons).is_empty()
	w.tick(2.0)
	assert_array(_reasons).is_equal(["HUD_NET_ERR_LOGIN_TIMEOUT"])


func test_login_ok_stops_the_timers() -> void:
	var w := _watch()
	w.begin("host:7777", false)
	w.on_link_up()
	w.on_login_ok()
	w.tick(100.0)
	assert_array(_reasons).is_empty()
	assert_int(w.phase).is_equal(ConnectionWatch.Phase.READY)


func test_older_server_version_error_is_surfaced() -> void:
	var w := _watch()
	w.begin("host:7777", true)
	w.on_link_up()
	w.on_account_error(AccountCodec.OP_GUEST, AccountCodec.E_VERSION)
	assert_array(_reasons).is_equal(["HUD_NET_ERR_VERSION"])


func test_protocol_reject_is_surfaced_once() -> void:
	var w := _watch()
	w.begin("host:7777", true)
	w.on_reject(MsgType.REJECT_PROTOCOL_MISMATCH)
	w.on_reject(MsgType.REJECT_PROTOCOL_MISMATCH)
	assert_array(_reasons).is_equal(["HUD_NET_ERR_VERSION"])


func test_other_account_errors_do_not_fail_the_link() -> void:
	var w := _watch()
	w.begin("host:7777", true)
	w.on_link_up()
	w.on_account_error(AccountCodec.OP_LOGIN, 3)
	assert_array(_reasons).is_empty()


func test_transport_errors_are_classified() -> void:
	assert_int(ConnectionWatch.classify_error("cannot find server x (DNS lookup failed)", true, false)).is_equal(ConnectionWatch.Reason.DNS)
	assert_int(ConnectionWatch.classify_error("disconnected from server", true, false)).is_equal(ConnectionWatch.Reason.DTLS)
	assert_int(ConnectionWatch.classify_error("disconnected from server", true, true)).is_equal(ConnectionWatch.Reason.DISCONNECTED)
	assert_int(ConnectionWatch.classify_error("disconnected from server", false, false)).is_equal(ConnectionWatch.Reason.TIMEOUT_CONNECT)


func test_log_lines_hold_no_secrets() -> void:
	var w := _watch()
	w.begin("host:7777", true)
	w.on_link_up()
	w.on_account_error(AccountCodec.OP_LOGIN, 3)
	w.on_login_ok()
	for l in _lines:
		assert_str(l).starts_with("[net] ")
		assert_str(l.to_lower()).not_contains("token")
		assert_str(l.to_lower()).not_contains("password")


func test_every_reason_has_a_translation_row() -> void:
	HudStrings.ensure_loaded()
	for r in ConnectionWatch.Reason.values():
		var key := ConnectionWatch.reason_key(r)
		assert_str(key).starts_with("HUD_NET_ERR_")
		assert_str(tr(key)).is_not_equal(key)  # fails until the lead appends the hud.csv rows


func test_unanswered_queue_join_times_out_and_resets_the_view() -> void:
	var mm := MatchmakingClient.new(null)
	var a := MmClientAdapter.new(mm)
	var failed: Array[String] = []
	var states: Array[StringName] = []
	a.failed.connect(func(k: String) -> void: failed.append(k))
	a.queue_changed.connect(func(s: Dictionary) -> void: states.append(s.state))
	a.join_queue(&"normal_5v5", [])
	a.tick(1.0)
	assert_array(failed).is_empty()
	a.tick(ConnectionWatchConfig.load_default().queue_ack_timeout_s)
	assert_array(failed).is_equal(["HUD_NET_ERR_QUEUE_TIMEOUT"])
	assert_array(states).is_equal([&"idle"])
	a.tick(100.0)
	assert_int(failed.size()).is_equal(1)


func test_queue_status_cancels_the_join_timeout() -> void:
	var mm := MatchmakingClient.new(null)
	var a := MmClientAdapter.new(mm)
	var failed: Array[String] = []
	a.failed.connect(func(k: String) -> void: failed.append(k))
	a.join_queue(&"normal_5v5", [])
	mm.queue_detail.emit({"state": MatchmakingCodec.QS_QUEUED, "queue": 0, "waited": 0, "estimate": 30, "players": 1, "locked": 0, "code": 0})
	a.tick(100.0)
	assert_array(failed).is_empty()


func test_error_card_shows_message_and_emits_retry_and_back() -> void:
	var p := ConnectionErrorPanel.new()
	add_child(p)
	await get_tree().process_frame
	var hits: Array[String] = []
	p.retry_requested.connect(func() -> void: hits.append("retry"))
	p.back_requested.connect(func() -> void: hits.append("back"))
	p.show_error("No answer.")
	assert_str(p.message()).is_equal("No answer.")
	for b in p.find_children("*", "Button", true, false):
		(b as Button).pressed.emit()
	assert_array(hits).contains_exactly_in_any_order(["retry", "back"])
	p.queue_free()
