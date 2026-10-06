extends GdUnitTestSuite
## P4: sound cues of the matchmaking flow (match found, go, your turn, last
## seconds, match found -> loading, victory / defeat, decline) and keyboard /
## controller handling (draft focus, Accept on the shown hero locks it, Esc
## leaves). Sounds are captured through MatchmakingFlow.sfx (no audio).

var fake: MatchmakingFakeClient
var cues: Array = []


func before_test() -> void:
	HudStrings.ensure_loaded()
	UiKit.force_reduce_motion = 1
	fake = MatchmakingFakeClient.new()
	cues = []


func after_test() -> void:
	UiKit.force_reduce_motion = -1
	Input.action_release(&"ui_accept")
	await get_tree().process_frame


func _flow() -> MatchmakingFlow:
	var f: MatchmakingFlow = auto_free(MatchmakingFlow.new())
	f.client = fake
	f.drive_client = false
	f.hold_on_assigned = true
	f.with_model = false
	f.sfx = func(c: StringName) -> void: cues.append(c)
	add_child(f)
	return f


func test_cues_follow_the_flow() -> void:
	var f := _flow()
	fake.join_queue(MmView.Q_NORMAL, [&"north", &"center"])
	fake.step(fake.found_after_s)
	assert_array(cues).is_equal([&"ready_check"])
	fake.reply_ready(true)
	fake.step(fake.think_s)
	assert_array(cues).contains([&"confirm"])
	var d := f.page as MmDraftScreen
	while not d.is_my_turn():
		fake.step(fake.think_s + 0.1)
	assert_int(cues.count(&"countdown_go")).is_equal(1)
	# The last 5 s of my turn tick once per second.
	d.left_s = 5.5
	for i in 6:
		d.left_s -= 1.0
		f._tick_cue()
	assert_int(cues.count(&"countdown_tick")).is_equal(5)
	fake.pick(d.selected)
	for i in 30:
		fake.step(fake.rules.pick_turn_s + 0.1)
		if not f.assigned.is_empty():
			break
	assert_array(cues).contains([&"match_found"])
	f.show_post({"won": true, "voided": false, "players": [], "stats": {}})
	assert_array(cues).contains([&"victory"])


func test_decline_sounds_an_error() -> void:
	var f := _flow()
	fake.join_queue(MmView.Q_NORMAL, [&"fill"])
	fake.step(fake.found_after_s)
	fake.reply_ready(false)
	fake.step(0.1)
	assert_array(cues).contains([&"error"])
	assert_object(f.ready_popup).is_null()


func test_draft_focus_and_accept_locks_the_shown_hero() -> void:
	var f := _flow()
	fake.join_queue(MmView.Q_NORMAL, [&"north", &"center"])
	fake.step(fake.found_after_s)
	fake.reply_ready(true)
	fake.step(fake.think_s)
	var d := f.page as MmDraftScreen
	await get_tree().process_frame
	assert_object(get_viewport().gui_get_focus_owner()).is_same(d._thumbs[d.selected])
	while not d.is_my_turn():
		fake.step(fake.think_s + 0.1)
	var other: StringName = &""
	for h: StringName in d._thumbs:
		if h != d.selected and d.can_lock(h):
			other = h
			break
	var picks_before := fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"pick").size()
	(d._thumbs[other] as Button).pressed.emit()  # a click: only selects
	assert_str(String(d.selected)).is_equal(String(other))
	assert_int(fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"pick").size()).is_equal(picks_before)
	Input.action_press(&"ui_accept")
	(d._thumbs[other] as Button).pressed.emit()  # Accept on the shown hero: lock in
	Input.action_release(&"ui_accept")
	assert_int(fake.sent.filter(func(m: Dictionary) -> bool: return m.op == &"pick").size()).is_equal(picks_before + 1)


func test_escape_leaves_the_play_screen_when_not_queued() -> void:
	var f := _flow()
	var backs := [0]
	f.play.back_requested.connect(func() -> void: backs[0] += 1)
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	f.play._unhandled_input(esc)
	assert_int(backs[0]).is_equal(1)
	fake.found_after_s = 999.0
	f.play.find_match()
	f.play._unhandled_input(esc)
	assert_int(backs[0]).is_equal(1)  # queued: Esc does not drop you out
