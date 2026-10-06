extends GdUnitTestSuite
## MatchmakingCodec (protocol v17): every request and event round-trips, and
## malformed / truncated / trailing / oversized packets decode to {}. Also the
## v17 Hello join ticket and the Welcome mood seed.

const ID_A := "0123456789abcdef0123456789abcdef"
const ID_B := "fedcba9876543210fedcba9876543210"


## Sample fields for every request op.
func _req_samples() -> Dictionary:
	return {
		MatchmakingCodec.OP_QUEUE_JOIN: {"queue": 2, "lane1": 0, "lane2": 255},
		MatchmakingCodec.OP_QUEUE_LEAVE: {},
		MatchmakingCodec.OP_READY_REPLY: {"accept": 1},
		MatchmakingCodec.OP_PICK: {"hero": 4},
		MatchmakingCodec.OP_ARAM_REROLL: {},
		MatchmakingCodec.OP_ARAM_BENCH: {"hero": 3},
		MatchmakingCodec.OP_ARAM_SWAP_REQUEST: {"seat": 2},
		MatchmakingCodec.OP_ARAM_SWAP_ACCEPT: {"seat": 1},
		MatchmakingCodec.OP_REMAKE_VOTE: {"yes": 1},
		MatchmakingCodec.OP_REPORT: {"match": "abcdef0123456789abcdef01", "target": ID_B, "category": 3},
		MatchmakingCodec.OP_HONOUR: {"match": "abcdef0123456789abcdef01", "target": ID_A},
		MatchmakingCodec.OP_RANKED_INFO: {},
		MatchmakingCodec.OP_CUSTOM_CREATE: {"map": 1, "mode": 2, "bots": 1, "team_size": 3},
		MatchmakingCodec.OP_CUSTOM_INVITE: {"id": ID_B},
		MatchmakingCodec.OP_CUSTOM_JOIN: {"host": ID_A},
		MatchmakingCodec.OP_CUSTOM_LEAVE: {},
		MatchmakingCodec.OP_CUSTOM_TEAM: {"team": 1},
		MatchmakingCodec.OP_CUSTOM_PICK: {"hero": 7},
		MatchmakingCodec.OP_CUSTOM_START: {},
		MatchmakingCodec.OP_REJOIN: {},
		MatchmakingCodec.OP_STATE_SYNC: {},
		MatchmakingCodec.OP_HOVER: {"hero": 6},
		MatchmakingCodec.OP_CUSTOM_BOTS: {"bots_a": 2, "bots_b": MatchmakingCodec.BOTS_FILL, "difficulty": 2},
	}


func _evt_samples() -> Dictionary:
	var seats := [{"id": ID_A, "team": 0, "lane": 1, "hero": 3, "flags": 12, "name": "Ann"},
		{"id": MatchmakingCodec.ID_ZERO, "team": 1, "lane": 255, "hero": 0, "flags": 1, "name": ""}]
	var members := [{"id": ID_A, "team": 0, "hero": 2, "flags": 4, "kills": 7, "deaths": 1, "assists": 300,
		"name": "Zoë"}]
	return {
		MatchmakingCodec.EV_QUEUE_STATUS: {"state": 1, "queue": 0, "waited": 61, "estimate": 75, "players": 9, "locked": 0},
		MatchmakingCodec.EV_MATCH_FOUND: {"match": "abcdef0123456789abcdef01", "queue": 1, "seconds": 10, "humans": 10,
			"accepted": 3, "you_accepted": 1},
		MatchmakingCodec.EV_READY_RESULT: {"outcome": 3, "locked": 120},
		MatchmakingCodec.EV_PICK_STATE: {"mode": 0, "turn": 2, "turn_team": 1, "seconds": 27, "you": 0, "seats": seats,
			"rerolls": 1, "bench": [3, 5], "swap_from": [2], "stage": 2, "bans": [4, 7], "trade_s": 13},
		MatchmakingCodec.EV_MATCH_ASSIGNED: {"host": "play.example.org", "port": 7801,
			"ticket": "cgt1.k1.%s.abcdef0123456789abcdef01.1999999999.%s.%s" % [ID_A, ID_B, ID_A + ID_B],
			"match": "abcdef0123456789abcdef01", "team": 1, "hero": 4, "map": "slice"},
		MatchmakingCodec.EV_RANKED_INFO: {"tracks": [{"track": 1, "rating": 1734, "games_left": 0, "band": 4,
			"division": 1}]},
		MatchmakingCodec.EV_LOCKOUT: {"seconds": 600, "ranked": 1, "reason": 1},
		MatchmakingCodec.EV_REMAKE_STATE: {"state": 1, "yes": 2, "needed": 4, "seconds": 28, "team": 0},
		MatchmakingCodec.EV_MATCH_RESULT: {"match": "abcdef0123456789abcdef01", "queue": 0, "won": 1, "voided": 0,
			"duration": 1720, "rated": 1, "delta": -153, "players": members},
		MatchmakingCodec.EV_CUSTOM_STATE: {"host": ID_A, "phase": 0, "map": 1, "mode": 2, "bots": 1, "team_size": 5,
			"bots_a": 1, "bots_b": 255, "difficulty": 0, "members": members},
		MatchmakingCodec.EV_ACK: {"req": 4},
		MatchmakingCodec.EV_PHASE: {"epoch": 1_800_000_000, "seq": 70_000, "phase": 3, "prev": 2, "snap": 1,
			"queue": 0, "party_size": 2, "leader": 1, "waited": 61, "estimate": 75, "locked": 0,
			"match": "abcdef0123456789abcdef01", "party": ID_B},
	}


func test_every_request_round_trips() -> void:
	var samples := _req_samples()
	assert_int(samples.size()).is_equal(MatchmakingCodec.REQ_SCHEMA.size())
	for op: int in samples:
		var d := MatchmakingCodec.decode_request(MatchmakingCodec.encode_request(op, samples[op]))
		assert_int(d.get("op", -1)).override_failure_message("op %d" % op).is_equal(op)
		for k in samples[op]:
			assert_that(d[k]).override_failure_message("op %d field %s" % [op, k]).is_equal(samples[op][k])


func test_every_event_round_trips() -> void:
	var samples := _evt_samples()
	assert_int(samples.size()).is_equal(MatchmakingCodec.EVT_SCHEMA.size())
	for op: int in samples:
		var d := MatchmakingCodec.decode_event(MatchmakingCodec.encode_event(op, MatchmakingCodec.OK, samples[op]))
		assert_int(d.get("op", -1)).override_failure_message("event %d" % op).is_equal(op)
		assert_int(d.code).is_equal(MatchmakingCodec.OK)
		for k in samples[op]:
			assert_that(d[k]).override_failure_message("event %d field %s" % [op, k]).is_equal(samples[op][k])


func test_error_events_carry_no_fields_except_status_kinds() -> void:
	var b := MatchmakingCodec.encode_event(MatchmakingCodec.EV_MATCH_ASSIGNED, MatchmakingCodec.E_BUSY, {"port": 1})
	assert_int(b.size()).is_equal(3)
	var d := MatchmakingCodec.decode_event(b)
	assert_int(d.code).is_equal(MatchmakingCodec.E_BUSY)
	var s := MatchmakingCodec.decode_event(MatchmakingCodec.encode_event(MatchmakingCodec.EV_QUEUE_STATUS,
		MatchmakingCodec.E_LOCKED, {"state": MatchmakingCodec.QS_LOCKED, "locked": 30}))
	assert_int(s.locked).is_equal(30)
	assert_int(s.code).is_equal(MatchmakingCodec.E_LOCKED)


func test_truncated_and_trailing_packets_are_rejected() -> void:
	var reqs := _req_samples()
	for op: int in reqs:
		var b := MatchmakingCodec.encode_request(op, reqs[op])
		var longer := b.duplicate()
		longer.append(0)
		assert_dict(MatchmakingCodec.decode_request(longer)).override_failure_message("trailing op %d" % op).is_empty()
		if b.size() > 2:
			assert_dict(MatchmakingCodec.decode_request(b.slice(0, b.size() - 1))).is_empty()
	var evts := _evt_samples()
	for op: int in evts:
		var b := MatchmakingCodec.encode_event(op, MatchmakingCodec.OK, evts[op])
		var longer := b.duplicate()
		longer.append(0)
		assert_dict(MatchmakingCodec.decode_event(longer)).override_failure_message("trailing ev %d" % op).is_empty()
		assert_dict(MatchmakingCodec.decode_event(b.slice(0, b.size() - 1))).is_empty()


func test_unknown_ops_wrong_type_and_bad_code_are_rejected() -> void:
	assert_dict(MatchmakingCodec.decode_request(PackedByteArray([MsgType.MM_REQ, 99]))).is_empty()
	assert_dict(MatchmakingCodec.decode_request(PackedByteArray([MsgType.MM_REQ]))).is_empty()
	assert_dict(MatchmakingCodec.decode_request(PackedByteArray([MsgType.ACCOUNT_REQ, 2]))).is_empty()
	assert_dict(MatchmakingCodec.decode_event(PackedByteArray([MsgType.MM_EVENT, 99, 0]))).is_empty()
	assert_dict(MatchmakingCodec.decode_event(PackedByteArray([MsgType.MM_EVENT, MatchmakingCodec.EV_ACK,
		MatchmakingCodec.CODE_COUNT, 1]))).is_empty()
	var big := PackedByteArray([MsgType.MM_REQ, MatchmakingCodec.OP_QUEUE_LEAVE])
	big.resize(LobbyCodec.MAX_C2S_BYTES + 1)
	assert_dict(MatchmakingCodec.decode_request(big)).is_empty()


func test_oversized_lists_and_bad_utf8_are_rejected() -> void:
	# A seat list claiming 200 seats.
	var b := PackedByteArray([MsgType.MM_EVENT, MatchmakingCodec.EV_RANKED_INFO, 0, 200])
	assert_dict(MatchmakingCodec.decode_event(b)).is_empty()
	var w := LobbyCodec.Writer.new(MsgType.MM_REQ)
	w.u8(MatchmakingCodec.OP_HONOUR)
	w.u8(2)
	w.u8(0xC3)
	w.u8(0x28)
	w.id(ID_A)
	assert_dict(MatchmakingCodec.decode_request(w.b)).is_empty()


func test_lists_are_capped_when_encoding() -> void:
	var many: Array = []
	for i in 40:
		many.append(i + 1)
	var d := MatchmakingCodec.decode_event(MatchmakingCodec.encode_event(MatchmakingCodec.EV_PICK_STATE,
		MatchmakingCodec.OK, {"bench": many, "seats": []}))
	assert_int((d.bench as Array).size()).is_equal(MatchmakingCodec.MAX_LIST)


func test_lanes_map_both_ways() -> void:
	for lane: StringName in MatchmakingCodec.LANES:
		assert_str(String(MatchmakingCodec.lane_of(MatchmakingCodec.lane_byte(lane)))).is_equal(String(lane))
	assert_int(MatchmakingCodec.lane_byte(&"fill")).is_equal(MatchmakingCodec.LANE_FILL)
	assert_str(String(MatchmakingCodec.lane_of(200))).is_equal("fill")


func test_hello_carries_join_ticket() -> void:
	var t := "cgt1.k1.%s.abcdef0123456789abcdef01.1999999999.%s.%s" % [ID_A, ID_B, ID_A + ID_B]
	var h := ControlCodec.decode_hello(ControlCodec.encode_hello(MsgType.PROTOCOL_VERSION, 3, 0, t))
	assert_str(h.ticket).is_equal(t)
	assert_int(h.hero_index).is_equal(3)
	assert_str(ControlCodec.decode_hello(ControlCodec.encode_hello(MsgType.PROTOCOL_VERSION, 1, 5)).ticket).is_equal("")


func test_hello_with_malformed_ticket_is_rejected() -> void:
	var b := ControlCodec.encode_hello(MsgType.PROTOCOL_VERSION, 1, 0, "abc")
	assert_dict(ControlCodec.decode_hello(b.slice(0, b.size() - 1))).is_empty()  # length mismatch
	var bad := b.duplicate()
	bad[8] = 0x0A  # control character
	assert_dict(ControlCodec.decode_hello(bad)).is_empty()
	var zero := ControlCodec.encode_hello(MsgType.PROTOCOL_VERSION, 1, 0)
	zero.append(0)
	assert_dict(ControlCodec.decode_hello(zero)).is_empty()


func test_welcome_carries_mood_seed() -> void:
	var w := ControlCodec.decode_welcome(ControlCodec.encode_welcome(4, 900, 30, 0xDEADBEEF))
	assert_int(w.mood_seed).is_equal(0xDEADBEEF)
	assert_int(w.own_net_id).is_equal(4)
	var old := PackedByteArray([MsgType.WELCOME, 4, 0, 1, 0, 0, 0, 30, 0])
	assert_dict(ControlCodec.decode_welcome(old)).is_empty()


func test_client_turns_events_into_signals() -> void:
	var mm := MatchmakingClient.new(null, "front.example.org")
	mm.clock = func() -> float: return 100.0
	var got := {}
	mm.match_assigned.connect(func(h: String, p: int, t: String) -> void: got["assigned"] = [h, p, t])
	mm.ready_check.connect(func(d: float) -> void: got["ready"] = d)
	mm.rating_update.connect(func(i: Dictionary) -> void: got["rating"] = i)
	mm.request_failed.connect(func(op: int, code: int) -> void: got["fail"] = [op, code])
	mm.handle(MatchmakingCodec.encode_event(MatchmakingCodec.EV_MATCH_ASSIGNED, MatchmakingCodec.OK,
		{"host": "", "port": 7801, "ticket": "cgt1.x", "match": "abcdef0123456789abcdef01"}))
	mm.handle(MatchmakingCodec.encode_event(MatchmakingCodec.EV_MATCH_FOUND, MatchmakingCodec.OK, {"seconds": 10}))
	mm.handle(MatchmakingCodec.encode_event(MatchmakingCodec.EV_RANKED_INFO, MatchmakingCodec.OK,
		{"tracks": [{"track": 1, "rating": MatchmakingCodec.RATING_HIDDEN, "games_left": 4}]}))
	mm.handle(MatchmakingCodec.encode_event(MatchmakingCodec.EV_ACK, MatchmakingCodec.E_TAKEN,
		{"req": MatchmakingCodec.OP_PICK}))
	assert_array(got.assigned).is_equal(["front.example.org", 7801, "cgt1.x"])
	assert_float(got.ready).is_equal(110.0)
	assert_int(got.rating.tracks[0].rating).is_equal(-1)
	assert_array(got.fail).is_equal([MatchmakingCodec.OP_PICK, MatchmakingCodec.E_TAKEN])
	assert_bool(mm.handle(PackedByteArray([MsgType.SNAPSHOT]))).is_false()
