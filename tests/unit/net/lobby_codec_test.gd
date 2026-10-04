extends GdUnitTestSuite
## LobbyCodec v11: every message round-trips, and malformed / oversized /
## truncated / trailing-byte packets decode to {} (the server's violation path).






func test_join_v12_round_trip_and_party() -> void:
	var j := LobbyCodec.decode_join(LobbyCodec.encode_join(MsgType.PROTOCOL_VERSION, 2, ProfileFixtures.id(9)))
	assert_int(j.protocol_version).is_equal(MsgType.PROTOCOL_VERSION)
	assert_int(j.hero_index).is_equal(2)
	assert_str(j.party_id).is_equal(ProfileFixtures.id(9))
	assert_str(LobbyCodec.decode_join(LobbyCodec.encode_join(MsgType.PROTOCOL_VERSION, 1)).party_id).is_equal("")


func test_join_other_layouts_decode_as_legacy() -> void:
	var b := LobbyCodec.encode_join(MsgType.PROTOCOL_VERSION, 2)
	var longer := b.duplicate()
	longer.append(0)
	assert_bool(LobbyCodec.decode_join(longer).get("legacy", false)).is_true()
	assert_dict(LobbyCodec.decode_join(PackedByteArray([MsgType.LOBBY_JOIN, 1]))).is_empty()


func test_join_legacy_v10_form_decodes_version_only() -> void:
	var b := PackedByteArray([MsgType.LOBBY_JOIN, 10, 0, 1, 0])
	var j := LobbyCodec.decode_join(b)
	assert_bool(j.get("legacy", false)).is_true()
	assert_int(j.protocol_version).is_equal(10)






func test_invalid_utf8_string_rejected() -> void:
	var w := LobbyCodec.Writer.new(MsgType.LOBBY_CHAT_SEND)
	w.u8(2)
	w.u8(0xC3)
	w.u8(0x28)  # broken 2-byte sequence
	assert_dict(LobbyCodec.decode_chat_send(w.b)).is_empty()
	var nul := PackedByteArray([MsgType.LOBBY_CHAT_SEND, 3, 65, 0, 66])
	assert_dict(LobbyCodec.decode_chat_send(nul)).is_empty()


func test_state_round_trip_with_names_and_flags() -> void:
	var slots := [
		{"team": 0, "hero_index": 1, "ready": true, "connected": true, "emblem": 4, "accent": 2,
			"id": ProfileFixtures.id(1), "name": "Ann"},
		{"team": 1, "hero_index": 2, "ready": false, "connected": false, "emblem": 11, "accent": 9,
			"id": ProfileFixtures.id(2), "name": "Bo Bee"},
	]
	var s := LobbyCodec.decode_state(LobbyCodec.encode_state(LobbyCodec.PHASE_LOCKED, 2, 1, slots, 3))
	assert_int(s.phase).is_equal(LobbyCodec.PHASE_LOCKED)
	assert_int(s.countdown).is_equal(2)
	assert_int(s.you).is_equal(1)
	assert_int(s.team_size).is_equal(3)
	assert_int(s.slots.size()).is_equal(2)
	assert_str(s.slots[1].name).is_equal("Bo Bee")
	assert_bool(s.slots[0].ready).is_true()
	assert_bool(s.slots[1].connected).is_false()
	assert_int(s.slots[1].emblem).is_equal(11)
	assert_str(s.slots[0].id).is_equal(ProfileFixtures.id(1))


func test_state_bad_team_or_count_rejected() -> void:
	var slots := [{"team": 0, "hero_index": 1, "ready": false, "id": ProfileFixtures.id(1), "name": "Ann"}]
	var b := LobbyCodec.encode_state(0, 0, 0, slots)
	b.encode_u8(6, 7)  # team byte of slot 0
	assert_dict(LobbyCodec.decode_state(b)).is_empty()
	var c := LobbyCodec.encode_state(0, 0, 0, slots)
	c.encode_u8(5, 3)  # n = 3, but one slot follows
	assert_dict(LobbyCodec.decode_state(c)).is_empty()


func test_pick_team_start_round_trip_and_ranges() -> void:
	var p := LobbyCodec.decode_pick(LobbyCodec.encode_pick(5, true))
	assert_int(p.hero_index).is_equal(5)
	assert_bool(p.ready).is_true()
	assert_dict(LobbyCodec.decode_pick(PackedByteArray([MsgType.LOBBY_PICK, 1, 0, 2]))).is_empty()
	assert_int(LobbyCodec.decode_team(LobbyCodec.encode_team(1)).team).is_equal(1)
	assert_dict(LobbyCodec.decode_team(PackedByteArray([MsgType.LOBBY_TEAM, 2]))).is_empty()
	var st := LobbyCodec.decode_start(LobbyCodec.encode_start(4321, 1, 2))
	assert_int(st.token).is_equal(4321)
	assert_int(st.team).is_equal(1)


func test_chat_round_trip_and_oversize_rejected() -> void:
	var c := LobbyCodec.decode_chat(LobbyCodec.encode_chat(LobbyCodec.CHAT_PLAYER, 0, 1, 3, "Ann", "gl hf ✨",
		ProfileFixtures.id(1)))
	assert_str(c.text).is_equal("gl hf ✨")
	assert_str(c.name).is_equal("Ann")
	assert_str(c.id).is_equal(ProfileFixtures.id(1))
	assert_str(LobbyCodec.decode_chat_send(LobbyCodec.encode_chat_send("hello")).text).is_equal("hello")
	var big := LobbyCodec.Writer.new(MsgType.LOBBY_CHAT_SEND)
	big.u8(250)
	for i in 250:
		big.u8(65)
	assert_dict(LobbyCodec.decode_chat_send(big.b)).is_empty()


func test_encode_truncates_long_text_on_char_boundary() -> void:
	var t := "é".repeat(200)  # 400 bytes
	var d := LobbyCodec.decode_chat_send(LobbyCodec.encode_chat_send(t))
	assert_int(d.text.to_utf8_buffer().size()).is_less_equal(LobbyCodec.CHAT_MAX_BYTES)
	assert_str(d.text).is_equal("é".repeat(120))






func test_player_names_round_trip_and_malformed() -> void:
	var b := LobbyCodec.encode_player_names({7: {"name": "Ann", "accent": 2}, 3: {"name": "Bo", "accent": 0}})
	var d: Variant = LobbyCodec.decode_player_names(b)
	assert_object(d).is_not_null()
	assert_str(d[7].name).is_equal("Ann")
	assert_str(d[3].name).is_equal("Bo")
	assert_object(LobbyCodec.decode_player_names(b.slice(0, b.size() - 1))).is_null()


func test_wrong_type_byte_rejected_everywhere() -> void:
	var b := LobbyCodec.encode_pick(1, false)
	assert_dict(LobbyCodec.decode_join(b)).is_empty()
	assert_dict(LobbyCodec.decode_state(b)).is_empty()
	assert_dict(LobbyCodec.decode_chat(b)).is_empty()
