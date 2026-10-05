extends GdUnitTestSuite
## W15 "sign in once": LaunchTokenStore (single use, 60 s, bound to the
## account, hash only) and the LaunchHandoff environment parser.

const ACC_A := "0123456789abcdef0123456789abcdef"
const ACC_B := "fedcba9876543210fedcba9876543210"
const TTL := 60.0


func test_token_is_256_bit_hex() -> void:
	var st := LaunchTokenStore.new(TTL)
	var tok := st.issue(ACC_A, 0.0)
	assert_int(tok.length()).is_equal(64)
	assert_bool(tok.is_valid_hex_number()).is_true()
	assert_str(st.issue(ACC_B, 0.0)).is_not_equal(tok)


func test_redeem_ok_once_then_reuse_rejected() -> void:
	var st := LaunchTokenStore.new(TTL)
	var tok := st.issue(ACC_A, 10.0)
	assert_int(st.redeem(tok, ACC_A, 20.0)).is_equal(LaunchTokenStore.Result.OK)
	assert_int(st.redeem(tok, ACC_A, 21.0)).is_equal(LaunchTokenStore.Result.UNKNOWN)


func test_expiry() -> void:
	var st := LaunchTokenStore.new(TTL)
	var tok := st.issue(ACC_A, 0.0)
	assert_int(st.redeem(tok, ACC_A, TTL + 0.01)).is_equal(LaunchTokenStore.Result.EXPIRED)
	var tok2 := st.issue(ACC_A, 100.0)
	assert_int(st.redeem(tok2, ACC_A, 100.0 + TTL)).is_equal(LaunchTokenStore.Result.OK)  # boundary: still valid


func test_wrong_account_rejected_and_burns_the_token() -> void:
	var st := LaunchTokenStore.new(TTL)
	var tok := st.issue(ACC_A, 0.0)
	assert_int(st.redeem(tok, ACC_B, 1.0)).is_equal(LaunchTokenStore.Result.WRONG_ACCOUNT)
	assert_int(st.redeem(tok, ACC_A, 2.0)).is_equal(LaunchTokenStore.Result.UNKNOWN)


func test_only_the_hash_is_stored() -> void:
	var st := LaunchTokenStore.new(TTL)
	var tok := st.issue(ACC_A, 0.0)
	assert_bool(st.holds_plain(tok)).is_false()
	assert_int(st.count()).is_equal(1)


func test_new_token_revokes_the_old_one_and_purge_drops_expired() -> void:
	var st := LaunchTokenStore.new(TTL)
	var t1 := st.issue(ACC_A, 0.0)
	var t2 := st.issue(ACC_A, 1.0)
	assert_int(st.redeem(t1, ACC_A, 2.0)).is_equal(LaunchTokenStore.Result.UNKNOWN)
	assert_int(st.redeem(t2, ACC_A, 2.0)).is_equal(LaunchTokenStore.Result.OK)
	st.issue(ACC_B, 0.0)
	st.purge(TTL + 1.0)
	assert_int(st.count()).is_equal(0)


func test_store_cap_drops_oldest() -> void:
	var st := LaunchTokenStore.new(TTL, 16)
	var first := st.issue("%032x" % 1, 0.0)
	for i in range(2, 20):
		st.issue("%032x" % i, 0.0)
	assert_int(st.count()).is_equal(16)
	assert_int(st.redeem(first, "%032x" % 1, 1.0)).is_equal(LaunchTokenStore.Result.UNKNOWN)


func test_handoff_parse() -> void:
	var tok := "ab".repeat(32)
	var ok := LaunchHandoff.parse({LaunchHandoff.ENV_TOKEN: tok, LaunchHandoff.ENV_SERVER: "cyber.example:7777",
		LaunchHandoff.ENV_ACCOUNT: ACC_A})
	assert_dict(ok).is_equal({"token": tok, "server": "cyber.example:7777", "account": ACC_A})
	assert_dict(LaunchHandoff.parse({})).is_empty()
	assert_dict(LaunchHandoff.parse({LaunchHandoff.ENV_TOKEN: "zz".repeat(32), LaunchHandoff.ENV_SERVER: "h:1",
		LaunchHandoff.ENV_ACCOUNT: ACC_A})).is_empty()
	assert_dict(LaunchHandoff.parse({LaunchHandoff.ENV_TOKEN: tok, LaunchHandoff.ENV_SERVER: "nohost",
		LaunchHandoff.ENV_ACCOUNT: ACC_A})).is_empty()
	assert_dict(LaunchHandoff.parse({LaunchHandoff.ENV_TOKEN: tok.left(62), LaunchHandoff.ENV_SERVER: "h:1",
		LaunchHandoff.ENV_ACCOUNT: ACC_A})).is_empty()


func test_handoff_take_unsets_the_environment() -> void:
	var h := {"token": "cd".repeat(32), "server": "127.0.0.1:7777", "account": ACC_B}
	assert_bool(LaunchHandoff.put_into_os(h)).is_true()
	assert_dict(LaunchHandoff.take_from_os()).is_equal(h)
	for k in LaunchHandoff.SECRET_KEYS:
		assert_bool(OS.has_environment(k)).is_false()
	assert_bool(LaunchHandoff.put_into_os({})).is_false()
