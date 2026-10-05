extends GdUnitTestSuite
## W17-SUP join tickets: HMAC-SHA256 signing, single use, expiry, match and
## account binding, tampering, key rotation, and that keys are never printed.

const ACC_A := "0123456789abcdef0123456789abcdef"
const ACC_B := "fedcba9876543210fedcba9876543210"
const MATCH := "aaaabbbbccccdddd00001111"
const OTHER_MATCH := "9999888877776666aaaa0000"
const NOW := 1_800_000_000.0
const TTL := 10.0
const KEY_HEX := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
const KEY2_HEX := "ff0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1eff"
const R := JoinTicketVerifier.Result


func _ring() -> TicketKeyRing:
	return TicketKeyRing.parse_spec("k1:" + KEY_HEX)


func _verifier(ring: TicketKeyRing = null) -> JoinTicketVerifier:
	return JoinTicketVerifier.new(ring if ring != null else _ring(), MATCH, 60.0)


func test_sign_verify_ok_and_account_from_ticket() -> void:
	var t := JoinTicket.sign(_ring(), ACC_A, MATCH, NOW, TTL)
	assert_str(t).starts_with("cgt1.k1.")
	var r := _verifier().verify(t, NOW + 1.0)
	assert_int(r.result).is_equal(R.OK)
	assert_str(r.account).is_equal(ACC_A)


func test_known_vector() -> void:
	var t := JoinTicket.sign_with(KEY_HEX.hex_decode(), "k1", ACC_A, MATCH, 1800000010, "00".repeat(16))
	var body := "cgt1.k1.%s.%s.1800000010.%s" % [ACC_A, MATCH, "00".repeat(16)]
	var mac := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, KEY_HEX.hex_decode(), body.to_utf8_buffer())
	assert_str(t).is_equal(body + "." + mac.hex_encode())


func test_replay_rejected() -> void:
	var v := _verifier()
	var t := JoinTicket.sign(_ring(), ACC_A, MATCH, NOW, TTL)
	assert_int(v.verify(t, NOW).result).is_equal(R.OK)
	assert_int(v.verify(t, NOW + 0.5).result).is_equal(R.REPLAYED)


func test_two_tickets_same_account_both_valid() -> void:
	var v := _verifier()
	assert_int(v.verify(JoinTicket.sign(_ring(), ACC_A, MATCH, NOW, TTL), NOW).result).is_equal(R.OK)
	# Reconnect: a fresh ticket to the same match.
	assert_int(v.verify(JoinTicket.sign(_ring(), ACC_A, MATCH, NOW + 5.0, TTL), NOW + 6.0).result).is_equal(R.OK)


func test_expiry_and_boundary() -> void:
	var t := JoinTicket.sign_with(KEY_HEX.hex_decode(), "k1", ACC_A, MATCH, int(NOW + TTL), "11".repeat(16))
	assert_int(_verifier().verify(t, NOW + TTL).result).is_equal(R.OK)  # boundary: still valid
	assert_int(_verifier().verify(t, NOW + TTL + 0.01).result).is_equal(R.EXPIRED)


func test_too_long_validity_rejected() -> void:
	var t := JoinTicket.sign(_ring(), ACC_A, MATCH, NOW, 3600.0)
	assert_int(_verifier().verify(t, NOW).result).is_equal(R.TOO_LONG)


func test_wrong_match_rejected() -> void:
	var t := JoinTicket.sign(_ring(), ACC_A, OTHER_MATCH, NOW, TTL)
	assert_int(_verifier().verify(t, NOW).result).is_equal(R.WRONG_MATCH)


func test_wrong_account_rejected_and_burns() -> void:
	var v := _verifier()
	var t := JoinTicket.sign(_ring(), ACC_A, MATCH, NOW, TTL)
	assert_int(v.verify(t, NOW, ACC_B).result).is_equal(R.WRONG_ACCOUNT)
	assert_int(v.verify(t, NOW, ACC_A).result).is_equal(R.REPLAYED)


func test_tampered_fields_rejected() -> void:
	var t := JoinTicket.sign(_ring(), ACC_A, MATCH, NOW, TTL)
	var v := _verifier()
	assert_int(v.verify(t.replace(ACC_A, ACC_B), NOW).result).is_equal(R.BAD_SIGNATURE)
	var p := t.split(".")
	p[4] = str(p[4].to_int() + 100)
	assert_int(v.verify(".".join(p), NOW).result).is_equal(R.BAD_SIGNATURE)
	var mac: String = p[6]
	p = t.split(".")
	p[6] = ("0" if mac[0] != "0" else "1") + mac.substr(1)
	assert_int(v.verify(".".join(p), NOW).result).is_equal(R.BAD_SIGNATURE)
	# A tampered attempt does not burn the real ticket.
	assert_int(v.verify(t, NOW).result).is_equal(R.OK)


func test_malformed_rejected() -> void:
	var v := _verifier()
	for bad in ["", "cgt1", "x.k1.a.b.1.n.m", "cgt1.K1." + ACC_A + "." + MATCH + ".1." + "00".repeat(16) + "." + "0".repeat(64),
			"cgt1.k1." + ACC_A + "." + MATCH + ".-1." + "00".repeat(16) + "." + "0".repeat(64), "a".repeat(400)]:
		assert_int(v.verify(bad, NOW).result).is_equal(R.MALFORMED)


func test_key_rotation() -> void:
	var front := TicketKeyRing.parse_spec("k2:%s\nk1:%s" % [KEY2_HEX, KEY_HEX])
	assert_str(front.active_kid).is_equal("k2")
	# A process started under k1 still verifies tickets signed with k1.
	var old_proc := _verifier(TicketKeyRing.parse_spec("k1:" + KEY_HEX))
	assert_int(old_proc.verify(JoinTicket.sign(front, ACC_A, MATCH, NOW, TTL, "k1"), NOW).result).is_equal(R.OK)
	# ... but not k2 tickets it never got the key for.
	assert_int(old_proc.verify(JoinTicket.sign(front, ACC_B, MATCH, NOW, TTL), NOW).result).is_equal(R.UNKNOWN_KEY)
	# Same kid, different key bytes: the signature fails.
	var forged := TicketKeyRing.parse_spec("k1:" + KEY2_HEX)
	assert_int(old_proc.verify(JoinTicket.sign(forged, ACC_A, MATCH, NOW, TTL), NOW).result).is_equal(R.BAD_SIGNATURE)
	# Retiring the old key: the active one cannot be removed.
	assert_bool(front.remove_key("k2")).is_false()
	assert_bool(front.remove_key("k1")).is_true()
	assert_str(JoinTicket.sign(front, ACC_A, MATCH, NOW, TTL, "k1")).is_empty()


func test_nonce_cache_purges_expired() -> void:
	var v := _verifier()
	v.verify(JoinTicket.sign(_ring(), ACC_A, MATCH, NOW, TTL), NOW)
	assert_int(v.nonce_count()).is_equal(1)
	v.purge(NOW + TTL + 1.0)
	assert_int(v.nonce_count()).is_equal(0)


func test_key_ring_parse_rejects_bad_specs() -> void:
	assert_str(TicketKeyRing.parse_spec("k1:abcd").active_kid).is_empty()  # too short
	assert_str(TicketKeyRing.parse_spec("k1:" + KEY_HEX + ",bad kid:" + KEY_HEX).active_kid).is_empty()
	assert_str(TicketKeyRing.parse_spec("k1:" + KEY_HEX.left(63)).active_kid).is_empty()
	assert_str(TicketKeyRing.parse_spec("# comment\n\nk1:" + KEY_HEX).active_kid).is_equal("k1")


func test_key_ring_from_env_and_fallback() -> void:
	var r := TicketKeyRing.from_env({TicketKeyRing.ENV_KEYS: "a1:" + KEY_HEX})
	assert_str(r.active_kid).is_equal("a1")
	assert_bool(r.ephemeral).is_false()
	var e := TicketKeyRing.from_env({TicketKeyRing.ENV_KEYS: ""})
	assert_bool(e.ephemeral).is_true()
	assert_int(e.key_for(e.active_kid).size()).is_equal(TicketKeyRing.MIN_KEY_BYTES)


func test_keys_never_printed() -> void:
	var r := TicketKeyRing.parse_spec("k1:" + KEY_HEX)
	assert_str(str(r)).not_contains(KEY_HEX)
	assert_str(str(r)).contains("k1")
