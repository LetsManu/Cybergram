class_name JoinTicket
extends RefCounted
## One-time match join ticket (W17), signed by the front and checked by the
## match process. Text form (all lower-case ASCII, '.'-separated):
##   cgt1.<kid>.<account>.<match_id>.<expires_unix>.<nonce>.<mac>
## - account: 32 hex (an AccountStore id); match_id: 8-32 of [a-z0-9];
## - nonce: 32 hex (128 random bits) that makes each ticket single-use;
## - mac: HMAC-SHA256 (hex) over everything before ".<mac>" with key <kid>.
## The ticket carries no secret. Reconnect asks the front for a fresh ticket to
## the same running match. Verification: JoinTicketVerifier.

const PREFIX := "cgt1"
const NONCE_BYTES := 16
const MAX_LENGTH := 256


## Signs a ticket for `account_id` into `match_id`, valid until
## `now_unix + ttl_s`, with the key `kid` of `ring` ("" = the active key).
## Returns "" when the key is unknown or an id is malformed.
static func sign(ring: TicketKeyRing, account_id: String, match_id: String, now_unix: float,
		ttl_s: float, kid: String = "") -> String:
	var k := kid if kid != "" else ring.active_kid
	if not ring.has_key(k):
		return ""
	var nonce := Crypto.new().generate_random_bytes(NONCE_BYTES).hex_encode()
	return sign_with(ring.key_for(k), k, account_id, match_id, int(ceil(now_unix + ttl_s)), nonce)


## Deterministic signing (tests): every field given.
static func sign_with(key: PackedByteArray, kid: String, account_id: String, match_id: String,
		expires_unix: int, nonce: String) -> String:
	if not valid_account(account_id) or not valid_match_id(match_id) or not TicketKeyRing.valid_kid(kid):
		return ""
	var body := "%s.%s.%s.%s.%d.%s" % [PREFIX, kid, account_id, match_id, expires_unix, nonce]
	return body + "." + mac_hex(key, body)


## HMAC-SHA256 of `body` (hex).
static func mac_hex(key: PackedByteArray, body: String) -> String:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, body.to_utf8_buffer()).hex_encode()


## The fields of `ticket` without checking the signature:
## {kid, account, match_id, expires, nonce, body, mac}, or {} when malformed.
static func parse(ticket: String) -> Dictionary:
	if ticket.length() > MAX_LENGTH:
		return {}
	var p := ticket.split(".")
	if p.size() != 7 or p[0] != PREFIX:
		return {}
	if not TicketKeyRing.valid_kid(p[1]) or not valid_account(p[2]) or not valid_match_id(p[3]):
		return {}
	if not p[4].is_valid_int() or p[4].begins_with("-") or p[4].begins_with("+"):
		return {}
	if p[5].length() != NONCE_BYTES * 2 or not _is_lower_hex(p[5]) or p[6].length() != 64 or not _is_lower_hex(p[6]):
		return {}
	return {"kid": p[1], "account": p[2], "match_id": p[3], "expires": p[4].to_int(), "nonce": p[5],
		"body": ".".join(p.slice(0, 6)), "mac": p[6]}


static func valid_account(a: String) -> bool:
	return a.length() == 32 and _is_lower_hex(a)


static func valid_match_id(m: String) -> bool:
	if m.length() < 8 or m.length() > 32:
		return false
	for i in m.length():
		var c := m.unicode_at(i)
		if not ((c >= 0x61 and c <= 0x7A) or (c >= 0x30 and c <= 0x39)):
			return false
	return true


## A fresh random match id (24 hex chars).
static func new_match_id() -> String:
	return Crypto.new().generate_random_bytes(12).hex_encode()


static func _is_lower_hex(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 0x30 and c <= 0x39) or (c >= 0x61 and c <= 0x66)):
			return false
	return true
