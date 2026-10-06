extends GdUnitTestSuite
## P2 client: SocialModel turns FRIENDS / PARTY / NOTIFY results into what the
## screens show (DM threads + unread, party chat, invites, join requests,
## toasts) and sends the right ops; the adapter maps OP_PARTY for the play
## screen; the friends panel and play screen build with the new controls.

const ME := "0000000000000000000000000000000a"
const NYX := "0000000000000000000000000000000b"
const ORR := "0000000000000000000000000000000c"


func _model() -> Array:
	var sent: Array = []
	var m := SocialModel.new(func(op: int, f: Dictionary) -> void: sent.append([op, f]))
	m.me = ME
	var t := [100.0]
	m.clock = func() -> float: return t[0]
	return [m, sent, t]


static func _note(kind: int, from: String, name: String, text := "") -> Dictionary:
	return {"op": AccountCodec.OP_NOTIFY, "code": AccountCodec.OK, "kind": kind, "id": from, "name": name,
		"text": text, "mode": 255}


func _party(leader: String, ids: Array, ready: Array = []) -> Dictionary:
	var members: Array = []
	for id in ids:
		members.append({"id": id, "kind": AccountCodec.PARTY_LEADER if id == leader else AccountCodec.PARTY_MEMBER,
			"status": 1, "display_name": "N" + str(id).right(1), "emblem": 0, "accent": 0,
			"flags": AccountCodec.PF_READY if ready.has(id) else 0})
	return {"op": AccountCodec.OP_PARTY, "code": AccountCodec.OK, "party": "p1", "leader": leader, "members": members}


func test_dm_counts_unread_until_the_thread_is_open() -> void:
	var x := _model()
	var m: SocialModel = x[0]
	var toasts: Array = []
	m.toast.connect(func(text: String, _k: StringName) -> void: toasts.append(text))
	m.on_result(_note(AccountCodec.N_DM, NYX, "Nyx", "hi"))
	m.on_result(_note(AccountCodec.N_DM, NYX, "Nyx", "there?"))
	assert_int(int(m.unread[NYX])).is_equal(2)
	assert_int(m.total_unread()).is_equal(2)
	assert_int(toasts.size()).is_equal(2)
	m.open(NYX)
	assert_bool(m.unread.has(NYX)).is_false()
	m.on_result(_note(AccountCodec.N_DM, NYX, "Nyx", "ok"))
	assert_bool(m.unread.has(NYX)).is_false()  # read while open
	assert_int((m.threads[NYX] as Array).size()).is_equal(3)


func test_send_dm_shows_it_at_once_and_sends_the_op() -> void:
	var x := _model()
	var m: SocialModel = x[0]
	m.send_dm(NYX, "  gl  ")
	assert_array(x[1]).is_equal([[AccountCodec.OP_DM, {"id": NYX, "text": "gl"}]])
	assert_bool(bool(m.threads[NYX][0].mine)).is_true()
	m.send_dm(NYX, "   ")
	assert_int((x[1] as Array).size()).is_equal(1)


func test_party_chat_and_kick_clear() -> void:
	var x := _model()
	var m: SocialModel = x[0]
	m.on_result(_note(AccountCodec.N_PARTY_CHAT, NYX, "Nyx", "gl hf"))
	assert_int(m.party_chat.size()).is_equal(1)
	m.on_result(_note(AccountCodec.N_KICKED, NYX, "Nyx"))
	assert_int(m.party_chat.size()).is_equal(0)
	assert_bool((x[1] as Array).has([AccountCodec.OP_PARTY, {}])).is_true()  # refresh asked


func test_join_requests_expire_and_invite_clears_them() -> void:
	var x := _model()
	var m: SocialModel = x[0]
	m.on_result(_note(AccountCodec.N_JOIN_REQUEST, NYX, "Nyx"))
	m.on_result(_note(AccountCodec.N_JOIN_REQUEST, ORR, "Orrin"))
	assert_int(m.pending_join_requests().size()).is_equal(2)
	m.invite(NYX)
	assert_int(m.pending_join_requests().size()).is_equal(1)
	x[2][0] = 100.0 + SocialModel.JOIN_REQUEST_TTL_S + 1.0
	assert_int(m.pending_join_requests().size()).is_equal(0)


func test_party_queries_and_leadership() -> void:
	var x := _model()
	var m: SocialModel = x[0]
	assert_bool(m.is_leader()).is_true()  # no party: you lead yourself
	m.on_result(_party(NYX, [NYX, ME]))
	assert_bool(m.is_leader()).is_false()
	assert_bool(m.in_my_party(NYX)).is_true()
	assert_bool(m.in_my_party(ORR)).is_false()


func test_rate_limit_and_offline_dm_tell_the_player() -> void:
	var x := _model()
	var m: SocialModel = x[0]
	var toasts: Array = []
	m.toast.connect(func(text: String, k: StringName) -> void: toasts.append(k))
	m.on_result({"op": AccountCodec.OP_PARTY_CHAT, "code": AccountCodec.E_RATE})
	m.on_result({"op": AccountCodec.OP_DM, "code": AccountCodec.E_NOT_FOUND})
	assert_array(toasts).is_equal([&"warn", &"warn"])


func test_presence_text_names_the_mode() -> void:
	HudStrings.ensure_loaded()
	var q := SocialModel.presence_text(LobbyCodec.STATUS_IN_QUEUE, MatchmakingClient.queue_index(&"ranked_5v5"))
	assert_str(q).contains(TranslationServer.translate("HUD_FRIENDS_IN_QUEUE"))
	assert_str(q).contains("·")
	assert_str(SocialModel.presence_text(LobbyCodec.STATUS_AWAY, 255)).is_equal(TranslationServer.translate("HUD_FRIENDS_AWAY"))
	for k: String in FriendsPanel.STATUS_KEYS:
		assert_str(TranslationServer.translate(k)).is_not_equal(k)


func test_adapter_maps_the_party_for_the_play_screen() -> void:
	var p := MmClientAdapter.party_of(_party(NYX, [NYX, ME], [ME]), ME)
	assert_str(str(p.leader)).is_equal(NYX)
	assert_int((p.members as Array).size()).is_equal(2)
	var mine: Dictionary = (p.members as Array).filter(func(e: Dictionary) -> bool: return e.me)[0]
	assert_bool(bool(mine.ready)).is_true()
	assert_bool(bool(mine.leader)).is_false()
	var solo := MmClientAdapter.party_of({}, ME)
	assert_bool(bool(solo.members[0].leader)).is_true()


func test_friends_panel_lists_invites_requests_and_new_states() -> void:
	HudStrings.ensure_loaded()
	var x := _model()
	var m: SocialModel = x[0]
	var fp: FriendsPanel = auto_free(FriendsPanel.new())
	add_child(fp)
	fp.social = m
	fp.set_session(true, func(_op: int, _f: Dictionary) -> void: pass)
	var inv := _party(ORR, [ORR])
	inv.members = [{"id": ORR, "kind": AccountCodec.PARTY_INVITE_IN, "status": 1, "display_name": "Orrin",
		"emblem": 0, "accent": 0, "flags": 0}]
	m.on_result(inv)
	m.on_result(_note(AccountCodec.N_JOIN_REQUEST, NYX, "Nyx"))
	fp.apply_friends([
		{"id": NYX, "status": LobbyCodec.STATUS_IN_QUEUE, "mode": 1, "relation": 0, "username": "nyx",
			"display_name": "Nyx", "emblem": 0, "accent": 0},
		{"id": ORR, "status": LobbyCodec.STATUS_AWAY, "mode": 255, "relation": 0, "username": "orrin",
			"display_name": "Orrin", "emblem": 0, "accent": 0}])
	var texts := _all_text(fp)
	assert_str(texts).contains(TranslationServer.translate("HUD_SOCIAL_GROUP_INVITES"))
	assert_str(texts).contains(TranslationServer.translate("HUD_SOCIAL_GROUP_JOIN"))
	assert_str(texts).contains(TranslationServer.translate("HUD_FRIENDS_GROUP_QUEUE"))
	assert_str(texts).contains(TranslationServer.translate("HUD_FRIENDS_GROUP_AWAY"))
	await get_tree().process_frame  # rebuild() queue_frees the old rows


func test_play_screen_shows_party_controls_and_chat_with_the_fake() -> void:
	var fake := MatchmakingFakeClient.new()
	var ps: MmPlayScreen = auto_free(MmPlayScreen.new())
	ps.client = fake
	add_child(ps)
	fake.party_changed.connect(ps.set_party)
	fake.set_party(["Nyx", "Orrin"])
	await get_tree().process_frame
	var texts := _all_text(ps)
	assert_str(texts).contains(TranslationServer.translate("HUD_SOCIAL_KICK"))
	assert_str(texts).contains(TranslationServer.translate("HUD_SOCIAL_READY"))
	assert_bool(ps._chat.visible).is_true()
	fake.party_say("on my way")
	assert_int(fake.party_chat_lines().size()).is_equal(1)


static func _all_text(n: Node) -> String:
	var out := PackedStringArray()
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		out.append(_all_text(c))
	return "\n".join(out)
