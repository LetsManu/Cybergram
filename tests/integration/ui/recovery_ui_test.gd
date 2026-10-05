extends GdUnitTestSuite
## W21-N1 UI: the login screen's "Forgot password?" page, password fields
## that never cut a pasted password (relog bug), the profile's recovery row
## and the show-once dialog (headless; looks are in production/qa/evidence/w21-n1).

var _sent: Array = []


func before_test() -> void:
	UiKit.force_reduce_motion = 1
	_sent = []


func after_test() -> void:
	UiKit.force_reduce_motion = -1


func _login_screen() -> LoginScreen:
	var ls: LoginScreen = auto_free(LoginScreen.new())
	ls.submitted.connect(func(op: int, f: Dictionary) -> void: _sent.append([op, f]))
	add_child(ls)
	return ls


func test_register_password_field_does_not_cut_a_long_password() -> void:
	var ls := _login_screen()
	var long := "x".repeat(AuthConfig.rules().password_max + 10)
	ls.fill_register("alice", long, "Alice", true, true)
	assert_str(ls.register_password()).is_equal(long)  # up to v0.15 this came back cut to password_max
	assert_str(ls._register_error()).is_not_empty()     # refused with a message instead


func test_forgot_password_sends_recover() -> void:
	var ls := _login_screen()
	ls.open_recover()
	assert_int(ls.mode).is_equal(LoginScreen.Mode.RECOVER)
	ls.fill_recover("alice", "abcde-fghjk-mnpqr-stvwx", "new password 1")
	ls._submit_recover()
	assert_int(_sent.size()).is_equal(1)
	assert_int(_sent[0][0]).is_equal(AccountCodec.OP_RECOVER)
	assert_str(str(_sent[0][1].code)).is_equal("abcde-fghjk-mnpqr-stvwx")
	assert_int(int(_sent[0][1].ver)).is_equal(MsgType.PROTOCOL_VERSION)
	# Mismatched new passwords are caught before sending.
	ls.fill_recover("alice", "abcde", "new password 1")
	ls._f_pass2.text = "something else"
	ls._submit_recover()
	assert_int(_sent.size()).is_equal(1)
	assert_str(LoginScreen.result_text(AccountCodec.OP_RECOVER, AccountCodec.E_CREDENTIALS)).is_not_equal(
		LoginScreen.result_text(AccountCodec.OP_LOGIN, AccountCodec.E_CREDENTIALS))


func test_profile_asks_for_recovery_info_and_shows_none_yet() -> void:
	var ps: ProfileScreen = auto_free(ProfileScreen.new())
	ps.session = {"display_name": "Alice", "username": "alice", "guest": 0, "emblem": 0, "accent": 0}
	ps.requested.connect(func(op: int, f: Dictionary) -> void: _sent.append([op, f]))
	add_child(ps)
	await await_idle_frame()
	assert_bool(_sent.any(func(e: Array) -> bool: return e[0] == AccountCodec.OP_RECOVERY_INFO)).is_true()
	ps.on_result({"op": AccountCodec.OP_RECOVERY_INFO, "code": 0, "has_code": 0})
	assert_int(ps.recovery_state).is_equal(0)
	ps.request_recovery_code("my password")
	var last: Array = _sent[-1]
	assert_int(last[0]).is_equal(AccountCodec.OP_RECOVERY_CODE)
	assert_str(str(last[1].password)).is_equal("my password")


func test_dialog_needs_the_box_ticked_and_shows_a_code_once() -> void:
	var res := {"op": AccountCodec.OP_REGISTER, "code": 0, "recovery_code": "ABCDE-FGHJK-MNPQR-STVWX"}
	var d := RecoveryCodeDialog.show_if_issued(self, res)
	assert_object(d).is_not_null()
	assert_object(RecoveryCodeDialog.show_if_issued(self, res)).is_null()  # the same code is not stacked
	assert_object(RecoveryCodeDialog.show_if_issued(self, {"op": 2, "code": 0})).is_null()
	assert_object(RecoveryCodeDialog.show_if_issued(self, {"op": 1, "code": 3, "recovery_code": "X"})).is_null()
	await await_idle_frame()
	d.acknowledge()
	assert_bool(RecoveryCodeDialog.is_open()).is_true()  # not without the box
	d.confirm_written_down()
	d.acknowledge()
	assert_bool(RecoveryCodeDialog.is_open()).is_false()
	assert_str(d.code).is_empty()
