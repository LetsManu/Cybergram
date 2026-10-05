extends GdUnitTestSuite
## W20-WEB: the "show me on the public leaderboard" toggle in the ranks
## panel (off by default, guests cannot opt in, a failed change keeps the
## last known state) and the adapter's ACCOUNT_RESULT conversion.

var fake: MatchmakingFakeClient


func before_test() -> void:
	HudStrings.ensure_loaded()
	UiKit.force_reduce_motion = 1
	fake = MatchmakingFakeClient.new()


func after_test() -> void:
	UiKit.force_reduce_motion = -1
	await get_tree().process_frame


func _panel() -> MmProfilePanel:
	var p: MmProfilePanel = auto_free(MmProfilePanel.new())
	p.client = fake
	add_child(p)
	return p


func test_toggle_starts_off_and_opts_in_and_out() -> void:
	var p := _panel()
	assert_bool(p._lb_toggle.button_pressed).is_false()
	assert_bool(p._lb_toggle.disabled).is_false()
	assert_str(p._lb_hint.text).contains("Off by default")
	p._lb_toggle.button_pressed = true  # the player flips it
	assert_bool(fake.leaderboard_public).is_true()
	assert_bool(p._lb_toggle.button_pressed).is_true()
	assert_bool(p._lb_toggle.disabled).is_false()
	p._lb_toggle.button_pressed = false
	assert_bool(fake.leaderboard_public).is_false()
	var ops: Array = fake.sent.map(func(s: Dictionary) -> StringName: return s.op)
	assert_array(ops).contains([&"leaderboard", &"leaderboard_set"])


func test_guest_sees_a_disabled_toggle() -> void:
	fake.leaderboard_available = false
	var p := _panel()
	assert_bool(p._lb_toggle.disabled).is_true()
	assert_bool(p._lb_toggle.button_pressed).is_false()
	assert_str(p._lb_hint.text).is_equal("The public leaderboard needs an account.")


func test_failed_change_keeps_last_state() -> void:
	var p := _panel()
	p.set_leaderboard_state({"public": true, "available": true})
	p.set_leaderboard_state({"public": false, "available": true, "error": true})
	assert_bool(p._lb_toggle.button_pressed).is_true()
	assert_str(p._lb_hint.text).is_equal("Could not change the setting. Try again.")


func test_adapter_converts_account_results() -> void:
	var op := AccountCodec.OP_LEADERBOARD
	assert_dict(MmClientAdapter.leaderboard_of({"op": op, "code": AccountCodec.OK, "public": 1})) \
		.is_equal({"public": true, "available": true})
	assert_dict(MmClientAdapter.leaderboard_of({"op": op, "code": AccountCodec.E_GUEST})) \
		.is_equal({"public": false, "available": false, "error": false})
	assert_bool(MmClientAdapter.leaderboard_of({"op": op, "code": AccountCodec.E_STORE}).error).is_true()
	assert_dict(MmClientAdapter.leaderboard_of({"op": AccountCodec.OP_FRIENDS, "code": 0})).is_empty()
