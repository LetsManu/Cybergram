extends GdUnitTestSuite
## W17B-UI: matchmaking screen state transitions against the offline
## MatchmakingFakeClient (no network, injected time): PLAY queue / lockout,
## ready-check timeout, draft turns and team-unique greying, 3v3 rerolls /
## bench / swaps, post-match rating display, honour / report, remake prompt
## and the flow's hand-over to the game client.

var fake: MatchmakingFakeClient


func before_test() -> void:
	HudStrings.ensure_loaded()
	UiKit.force_reduce_motion = 1
	fake = MatchmakingFakeClient.new()


func after_test() -> void:
	UiKit.force_reduce_motion = -1
	await get_tree().process_frame  # rebuilt rows are queue_free()d


func _flow() -> MatchmakingFlow:
	var f: MatchmakingFlow = auto_free(MatchmakingFlow.new())
	f.client = fake
	f.drive_client = false
	f.hold_on_assigned = true
	f.with_model = false
	add_child(f)
	return f


func _to_pick(q: StringName) -> void:
	fake.join_queue(q, [&"north", &"center"])
	fake.step(fake.found_after_s)
	fake.reply_ready(true)
	fake.step(fake.think_s)


func test_play_queue_cancel_and_elapsed_timer() -> void:
	var f := _flow()
	var p := f.play
	fake.found_after_s = 999.0
	p.set_lanes(&"south", &"flex")
	p.find_match()
	assert_str(String(fake.sent[-1].op)).is_equal("queue_join")
	assert_array(fake.sent[-1].lanes).is_equal([&"south", &"flex"])
	assert_int(p.state).is_equal(MmPlayScreen.State.QUEUED)
	p.tick(65.0)
	assert_str(p._elapsed.text).is_equal("1:05")
	p.cancel_queue()
	assert_int(p.state).is_equal(MmPlayScreen.State.IDLE)


func test_play_fill_disables_secondary_and_aram_sends_no_lanes() -> void:
	var p := _flow().play
	p.set_lanes(&"fill", &"north")
	assert_bool((p._secondary_chips[&"north"] as Button).disabled).is_true()
	p.select_queue(MmView.Q_ARAM)
	p.find_match()
	assert_array(fake.sent[-1].lanes).is_empty()


func test_play_lockout_banner_counts_down() -> void:
	var p := _flow().play
	fake.lock_out(10.0)
	assert_int(p.state).is_equal(MmPlayScreen.State.LOCKED)
	assert_bool(p._find.disabled).is_true()
	assert_bool(p._lock_banner.visible).is_true()
	p.find_match()
	assert_int(fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"queue_join").size()).is_equal(0)
	p.tick(10.5)
	assert_int(p.state).is_equal(MmPlayScreen.State.IDLE)
	assert_bool(p._find.disabled).is_false()


func test_custom_queue_opens_custom_lobby() -> void:
	var f := _flow()
	f.play.select_queue(MmView.Q_CUSTOM)
	f.play.find_match()
	assert_str(String(f.page_name)).is_equal("custom")
	var c := f.page as MmCustomLobby
	assert_bool(c.is_host()).is_true()
	c.invite("f1")
	assert_array(c.lobby.invited).contains(["f1"])
	c.start()
	assert_str(String(f.page_name)).is_equal("loading")


func test_custom_lobby_bot_slots_and_difficulty() -> void:
	var f := _flow()
	f.play.select_queue(MmView.Q_CUSTOM)
	f.play.find_match()
	var c := f.page as MmCustomLobby
	assert_int(c.bots_for(0)).is_equal(3)  # fill: 5 seats, 2 humans
	assert_str(c._bot_labels[0].text).is_equal(tr("HUD_MM_BOTS_FILL"))
	c.bump_bots(0, -1)
	assert_array(c.lobby.bot_slots).is_equal([2, -1])
	assert_int(c.bots_for(0)).is_equal(2)
	assert_str(c._bot_labels[0].text).is_equal("2")
	(c._diffs.get_node("Diff_hard") as Button).pressed.emit()
	assert_str(String(c.lobby.difficulty)).is_equal("hard")
	var bot_rows := c._teams[0].get_children().filter(func(n: Node) -> bool:
		return n is Label and (n as Label).text == tr("HUD_MM_BOT_SLOT") % tr("HUD_MM_BOT_HARD"))
	assert_int(bot_rows.size()).is_equal(2)
	c.bump_bots(0, 1)  # back up to the room: fill again
	assert_array(c.lobby.bot_slots).is_equal([-1, -1])
	await get_tree().process_frame


func test_loading_screen_shows_every_players_progress() -> void:
	var f := _flow()
	fake.join_queue(MmView.Q_NORMAL, [&"north", &"center"])
	fake.step(fake.found_after_s)
	fake.reply_ready(true)
	for i in 60:
		fake.step(fake.rules.pick_turn_s + 0.1)
		if f.page_name == &"loading":
			break
	assert_str(String(f.page_name)).is_equal("loading")
	var ld := f.page as MmLoadingScreen
	assert_int(ld._bars.size()).is_equal(ld.seats.size())
	for i in ld.seats.size():
		if bool(ld.seats[i].get("bot", false)):
			assert_int(ld.load_of(i)).is_equal(100)
	fake.report_load(50)
	var me := f._my_seat_index()
	assert_int(ld.load_of(me)).is_equal(50)
	assert_str((ld._pcts[me] as Label).text).is_equal("50%")
	fake.step(fake.load_s * 2.0)  # every fake player finished
	for i in ld.seats.size():
		if i != me:
			assert_int(ld.load_of(i)).is_equal(100)
	# The flow reports its own preload in 10 % steps.
	await get_tree().process_frame
	await get_tree().process_frame
	var loads := fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"load")
	assert_bool(loads.size() >= 2).is_true()
	assert_int(int(loads[-1].pct) % 10).is_equal(0)


func test_draft_shows_abilities_and_team_chat() -> void:
	var f := _flow()
	_to_pick(MmView.Q_NORMAL)
	var d := f.page as MmDraftScreen
	assert_object(d.chat).is_not_null()
	d.preview(d.selected)
	var def := HeroShowcase.hero_def(str(MmView.hero_entry(d.selected).stem))
	assert_int(d._skills.get_child_count()).is_equal(def.skills.size())
	assert_str(_all_text(d._skills)).contains(def.skills[0].display_name)
	var other: StringName = &""
	for h: StringName in d._thumbs:
		if h != d.selected:
			other = h
			break
	d.preview(other)
	var def2 := HeroShowcase.hero_def(str(MmView.hero_entry(other).stem))
	assert_str(_all_text(d._skills)).contains(def2.skills[0].display_name)
	d.chat.send.call("top or mid?")
	assert_array(fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"select_chat")).is_not_empty()
	fake.teammate_says("Nyx", "mid")
	await get_tree().process_frame
	assert_str(d.chat._log.get_parsed_text()).contains("Nyx")
	assert_str(d.chat._log.get_parsed_text()).contains("top or mid?")


static func _all_text(n: Node) -> String:
	var out := PackedStringArray()
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append(_all_text(c))
	return "\n".join(out)


func test_ready_check_timeout_and_result() -> void:
	var f := _flow()
	fake.join_queue(MmView.Q_NORMAL, [&"fill"])
	fake.step(fake.found_after_s)
	var rc := f.ready_popup
	assert_object(rc).is_not_null()
	assert_float(rc.left_s).is_equal_approx(fake.rules.ready_check_s, 0.01)
	rc.tick(fake.rules.ready_check_s)
	assert_int(rc.state).is_equal(MmReadyCheck.State.MISSED)
	rc.accept()  # too late: nothing sent
	assert_int(fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"ready").size()).is_equal(0)
	fake.step(fake.rules.ready_check_s)  # the server times the player out
	assert_object(f.ready_popup).is_null()
	assert_int(f.play.state).is_equal(MmPlayScreen.State.LOCKED)


func test_ready_accept_goes_to_draft() -> void:
	var f := _flow()
	_to_pick(MmView.Q_NORMAL)
	assert_object(f.ready_popup).is_null()
	assert_str(String(f.page_name)).is_equal("draft")


func test_ready_decline_sends_false() -> void:
	var f := _flow()
	fake.join_queue(MmView.Q_NORMAL, [&"fill"])
	fake.step(fake.found_after_s)
	f.ready_popup.decline()
	assert_bool(fake.sent[-1].accept).is_false()
	assert_int(f.play.state).is_equal(MmPlayScreen.State.LOCKED)


func test_draft_turns_greying_and_auto_pick() -> void:
	var f := _flow()
	_to_pick(MmView.Q_RANKED)
	var d := f.page as MmDraftScreen
	assert_bool(d.is_my_turn()).is_false()  # the enemy picks first
	assert_bool(d._lock.disabled).is_true()
	fake.step(fake.think_s + 0.1)  # enemy locks in
	var enemy := MmView.seat(d.state.seats, "p6")
	assert_str(String(enemy.hero)).is_not_empty()
	assert_bool(d.is_my_turn()).is_true()
	# Team-unique: once my teammate holds a hero it is greyed and cannot be locked.
	var mate := MmView.seat(d.state.seats, "p2")
	assert_bool(bool(mate.picking)).is_true()
	d.preview(&"hero_hex")
	d.lock_in()
	assert_str(String(fake.sent[-1].hero)).is_equal("hero_hex")
	fake.step(fake.think_s + 0.1)
	var held := StringName(MmView.seat(d.state.seats, "p2").hero)
	assert_bool(d.is_greyed(held)).is_true()
	assert_bool(d.is_greyed(&"hero_hex")).is_true()
	assert_bool(d._thumbs[held].get_meta(&"unavailable")).is_true()
	assert_bool(d.can_lock(held)).is_false()
	# Enemy may still hold the same hero: it is not greyed for us.
	assert_bool(d.is_greyed(StringName(enemy.hero)) and not MmView.team_taken(d.state.seats, 0).has(StringName(enemy.hero))).is_false()


func test_draft_timeout_auto_picks() -> void:
	var f := _flow()
	fake.think_s = 999.0
	_to_pick(MmView.Q_NORMAL)
	fake.step(fake.rules.pick_turn_s + 0.1)  # enemy times out
	fake.step(fake.rules.pick_turn_s + 0.1)  # we time out
	var d := f.page as MmDraftScreen
	var me := MmView.seat(d.state.seats, "me")
	assert_bool(bool(me.auto)).is_true()
	assert_str(String(me.hero)).is_not_empty()
	assert_str(String((d._cols[0].get_child(0).find_child("Status", true, false) as Label).text)).is_equal(tr("HUD_MM_SEAT_AUTO").to_upper())


func test_draft_leave_is_a_dodge() -> void:
	var f := _flow()
	_to_pick(MmView.Q_RANKED)
	var d := f.page as MmDraftScreen
	d.leave()
	var m := d.get_node("UiModal") as UiModal
	m.close(true)
	assert_int(fake.sent.filter(func(x: Dictionary) -> bool: return x.op == &"dodge").size()).is_equal(1)
	assert_int(f.play.state).is_equal(MmPlayScreen.State.LOCKED)


func test_aram_reroll_bench_and_swap() -> void:
	var f := _flow()
	_to_pick(MmView.Q_ARAM)
	var a := f.page as MmAllRandomScreen
	var first := a.my_hero()
	assert_int(int(a.state.rerolls_left)).is_equal(fake.rules.rerolls_per_player)
	a.reroll()
	assert_array(a.state.bench).contains([first])
	assert_int(int(a.state.rerolls_left)).is_equal(fake.rules.rerolls_per_player - 1)
	assert_bool(a._reroll.disabled).is_true()
	var second := a.my_hero()
	a.take(first)  # back from the bench
	assert_str(String(a.my_hero())).is_equal(String(first))
	assert_array(a.state.bench).contains([second])
	# A teammate asks to swap; accepting trades the heroes.
	fake.step(fake.think_s + 0.1)
	assert_int((a.state.swap_requests as Array).size()).is_equal(1)
	var from := str(a.state.swap_requests[0].from)
	var theirs := StringName(MmView.seat(a.state.seats, from).hero)
	a.answer(from, true)
	assert_str(String(a.my_hero())).is_equal(String(theirs))
	assert_array(a.state.swap_requests).is_empty()


func test_post_match_rating_display() -> void:
	var f := _flow()
	fake.queue = MmView.Q_RANKED
	fake.finish_match(true)
	var p := f.page as MmPostMatchScreen
	assert_bool(p._rating_box.visible).is_true()
	assert_str(p._delta.text).is_equal("+18")
	fake.queue = MmView.Q_NORMAL
	fake.finish_match(false)
	p = f.page as MmPostMatchScreen
	assert_bool(p._rating_box.visible).is_false()
	fake.queue = MmView.Q_RANKED
	fake.finish_match(false, true)
	p = f.page as MmPostMatchScreen
	assert_str(p._title.text).is_equal(tr("HUD_MM_POST_REMAKE").to_upper())
	assert_str(p._delta.text).is_equal(tr("HUD_MM_POST_VOID_NO_CHANGE"))


func test_honour_once_and_report_categories_only() -> void:
	var f := _flow()
	fake.queue = MmView.Q_NORMAL
	fake.finish_match(true)
	var p := f.page as MmPostMatchScreen
	p.honour("p2")
	p.honour("p2")
	assert_int(fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"honour").size()).is_equal(1)
	p.report("p7", &"free text")
	assert_int(fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"report").size()).is_equal(0)
	p.report("p7", &"griefing")
	assert_str(String(fake.sent[-1].category)).is_equal("griefing")
	# No honour / report buttons on your own row.
	assert_object(p.find_child("Player_me", true, false).find_child("Honour", true, false)).is_null()


func test_flow_assigned_hands_over_with_ticket() -> void:
	var f := _flow()
	f.hold_on_assigned = false
	var got: Array = []
	f.start_requested.connect(func(a: PackedStringArray) -> void: got.append(a))
	fake.custom_open()
	fake.custom_start()
	assert_str(String(f.page_name)).is_equal("loading")
	f._process(MatchmakingFlow.HANDOFF_S + 0.1)
	assert_int(got.size()).is_equal(1)
	var args: PackedStringArray = got[0]
	assert_str(args[0]).is_equal("--connect")
	assert_str(args[2]).is_equal("--ticket")
	assert_str(args[3]).starts_with("fake-ticket-")


func test_flow_connection_lost_offers_reconnect() -> void:
	var f := _flow()
	fake.custom_open()
	fake.custom_start()
	fake.drop_connection()
	var l := f.page as MmLoadingScreen
	assert_int(l.state).is_equal(MmLoadingScreen.State.DISCONNECTED)
	assert_bool(l._reconnect.visible).is_true()
	l.reconnect_requested.emit()
	assert_str(String(fake.sent[-1].op)).is_equal("reconnect")


func test_remake_prompt_eligibility_and_single_vote() -> void:
	var w: RemakePrompt = auto_free(RemakePrompt.new())
	var votes: Array = []
	w.voter = func(yes: bool) -> void: votes.append(yes)
	assert_bool(w.shows()).is_false()
	w.apply({"eligible": false, "open": false, "yes": 0, "needed": 4, "deadline_s": 0.0, "outcome": &""})
	assert_bool(w.shows()).is_false()
	w.vote(true)
	assert_array(votes).is_empty()
	w.apply({"eligible": true, "open": true, "yes": 1, "needed": 4, "deadline_s": 30.0, "outcome": &""})
	assert_bool(w.shows()).is_true()
	w.vote(true)
	w.vote(false)
	assert_array(votes).is_equal([true])
	w.apply({"eligible": true, "open": false, "yes": 4, "needed": 4, "deadline_s": 0.0, "outcome": &"passed"})
	assert_bool(w.shows()).is_true()
	w._process(RemakePrompt.OUTCOME_S + 0.1)
	assert_bool(w.shows()).is_false()


func test_profile_panel_calibration() -> void:
	fake.my_ranked = {"calibrating": true, "games_left": 7, "rating": -1, "medal": {}}
	var p: MmProfilePanel = auto_free(MmProfilePanel.new())
	p.client = fake
	add_child(p)
	assert_str(p._ranked_line.text).is_equal("Calibrating 3/10")
	assert_bool(p._pips.visible).is_true()
	assert_bool(p._progress.visible).is_false()


class FakeSession extends Node:
	var joined: Array = []
	func join_matchmade(host: String, port: int, ticket: String, hero_index: int, map_name: String) -> void:
		joined.append([host, port, ticket, hero_index, map_name])


func test_flow_joins_in_place_through_session() -> void:
	var f := _flow()
	f.hold_on_assigned = false
	var s: FakeSession = auto_free(FakeSession.new())
	f.session = s
	_to_pick(MmView.Q_ARAM)
	fake.step(fake.rules.all_random_s + 0.1)
	assert_str(String(f.page_name)).is_equal("loading")
	f._process(MatchmakingFlow.HANDOFF_S + 0.1)
	# v20: the hand-over waits until the map and hero are loaded in the background.
	for i in 3000:
		if not s.joined.is_empty():
			break
		await get_tree().process_frame
	assert_bool(f._preload.is_done()).is_true()
	assert_int(s.joined.size()).is_equal(1)
	assert_str(s.joined[0][2]).starts_with("fake-ticket-")
	assert_int(s.joined[0][3]).is_greater(0)
	assert_str(s.joined[0][4]).is_equal("slice")


func test_match_args_carry_map() -> void:
	var a := MatchmakingFlow.match_args({"host": "h", "port": 7801, "ticket": "t", "map": &"slice"}, &"hero_hex")
	assert_array(Array(a)).is_equal(["--connect", "h:7801", "--ticket", "t", "--hero", "hex", "--map", "slice"])
	assert_str(String(MmClientAdapter.map_of("", MmView.Q_ARAM))).is_equal("slice")
	assert_str(String(MmClientAdapter.map_of("shardline_front", MmView.Q_ARAM))).is_equal("shardline_front")
