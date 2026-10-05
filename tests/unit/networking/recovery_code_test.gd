extends GdUnitTestSuite
## W21-N1: recovery code format and parsing, the protocol 19 AccountCodec
## layouts, and AccountAdmin request validation (no files, no network).


func _rules() -> AuthRulesDef:
	return AuthRulesDef.new()


func test_generate_has_four_groups_and_at_least_90_bits() -> void:
	var r := _rules()
	var code := RecoveryCode.generate(r)
	assert_int(code.split("-").size()).is_equal(r.recovery_groups)
	assert_int(RecoveryCode.bits(r)).is_greater_equal(90)
	assert_str(RecoveryCode.normalize(code, r)).is_equal(code.replace("-", ""))
	assert_str(RecoveryCode.generate(r)).is_not_equal(code)


func test_normalize_is_forgiving_and_strict_on_length() -> void:
	var r := _rules()
	assert_str(RecoveryCode.normalize("abcde fghjk-mnpqr  stvwx", r)).is_equal("ABCDEFGHJKMNPQRSTVWX")
	assert_str(RecoveryCode.normalize("oilOI-00000-00000-00000", r)).is_equal("01101" + "0".repeat(15))
	assert_str(RecoveryCode.normalize("ABCDE-FGHJK-MNPQR", r)).is_empty()
	assert_str(RecoveryCode.normalize("ABCDE-FGHJK-MNPQR-STVWU", r)).is_empty()  # U is not Crockford
	assert_str(RecoveryCode.format("ABCDEFGHJKMNPQRSTVWX", r)).is_equal("ABCDE-FGHJK-MNPQR-STVWX")


func test_codec_round_trips_the_v19_ops() -> void:
	assert_int(MsgType.PROTOCOL_VERSION).is_equal(19)
	var req := AccountCodec.decode_request(AccountCodec.encode_request(AccountCodec.OP_RECOVER,
		{"ver": 19, "username": "alice", "code": "ABCDE-FGHJK-MNPQR-STVWX", "new_password": "new password"}))
	assert_str(str(req.code)).is_equal("ABCDE-FGHJK-MNPQR-STVWX")
	assert_str(str(req.new_password)).is_equal("new password")
	var info := AccountCodec.decode_result(AccountCodec.encode_result(AccountCodec.OP_RECOVERY_INFO, 0, {"has_code": 1}))
	assert_int(info.has_code).is_equal(1)
	var regen := AccountCodec.decode_result(AccountCodec.encode_result(AccountCodec.OP_RECOVERY_CODE, 0,
		{"recovery_code": "ABCDE-FGHJK-MNPQR-STVWX"}))
	assert_str(str(regen.recovery_code)).is_equal("ABCDE-FGHJK-MNPQR-STVWX")
	var reg := AccountCodec.decode_result(AccountCodec.encode_result(AccountCodec.OP_REGISTER, 0,
		{"token": "ab".repeat(32), "id": "cd".repeat(16), "username": "alice", "display_name": "Alice",
		"recovery_code": "ABCDE-FGHJK-MNPQR-STVWX"}))
	assert_str(str(reg.recovery_code)).is_equal("ABCDE-FGHJK-MNPQR-STVWX")
	# A failed RECOVER carries no fields at all (no account oracle in the size).
	var bad := AccountCodec.encode_result(AccountCodec.OP_RECOVER, AccountCodec.E_CREDENTIALS)
	assert_int(bad.size()).is_equal(3)
	assert_int(bad.size()).is_equal(AccountCodec.encode_result(AccountCodec.OP_LOGIN, AccountCodec.E_CREDENTIALS).size())


func test_admin_request_validation() -> void:
	var good := {"v": 1, "op": "reset_password", "username": "alice",
		"recovery": {"hash": "a".repeat(64), "salt": "0f".repeat(16), "iterations": 60000}}
	assert_bool(AccountAdmin.is_valid_reset(good)).is_true()
	var no_hash := good.duplicate(true)
	no_hash.recovery.hash = "zz"
	assert_bool(AccountAdmin.is_valid_reset(no_hash)).is_false()
	var weak := good.duplicate(true)
	weak.recovery.iterations = 1
	assert_bool(AccountAdmin.is_valid_reset(weak)).is_false()
	var other_op := good.duplicate(true)
	other_op.op = "delete"
	assert_bool(AccountAdmin.is_valid_reset(other_op)).is_false()


func test_export_never_carries_the_code_hash() -> void:
	var a := AccountStore.new_account("ab".repeat(16), "alice", {"algo": "pbkdf2-hmac-sha256", "hash": "11".repeat(32),
		"salt": "22".repeat(16), "iterations": 1000, "recovery": {"algo": "pbkdf2-hmac-sha256", "hash": "33".repeat(32),
		"salt": "44".repeat(16), "iterations": 1000, "created_at": 5}},
		{"display_name": "Alice", "emblem": 0, "accent": 0, "favourite_hero": ""}, 1)
	var json := AccountService.export_json(a)
	for secret in ["11".repeat(32), "22".repeat(16), "33".repeat(32), "44".repeat(16)]:
		assert_bool(json.contains(secret)).is_false()
	assert_bool(JSON.parse_string(json).password.recovery_code_set).is_true()
