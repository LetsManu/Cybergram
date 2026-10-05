class_name JoinTicketVerifier
extends RefCounted
## Checks JoinTickets inside one match process (W17). A ticket passes when its
## key id is known, the HMAC matches (constant-time compare), it names this
## match (and the expected account, when one is given), it has not expired, it
## does not reach further ahead than `max_ttl_s`, and its nonce was never seen.
## The nonce is burned by the first attempt with a valid signature whatever the
## outcome (like LaunchTokenStore). Memory only; time injected (unix seconds).

enum Result { OK, MALFORMED, UNKNOWN_KEY, BAD_SIGNATURE, WRONG_MATCH, WRONG_ACCOUNT, EXPIRED, TOO_LONG, REPLAYED }

var ring: TicketKeyRing
var match_id: String = ""
## Longest validity accepted (front clock skew included).
var max_ttl_s: float = 60.0
## Nonces kept at most (oldest dropped; each lives only until its expiry).
var max_nonces: int = 4096
var _used: Dictionary = {}  # nonce -> expires_unix


func _init(ring_: TicketKeyRing, match_id_: String, max_ttl_s_: float = 60.0) -> void:
	ring = ring_
	match_id = match_id_
	max_ttl_s = max_ttl_s_


## {result: Result, account: String}. `expected_account` "" accepts the
## ticket's own account (the ticket is the binding).
func verify(ticket: String, now_unix: float, expected_account: String = "") -> Dictionary:
	var t := JoinTicket.parse(ticket)
	if t.is_empty():
		return _r(Result.MALFORMED)
	if not ring.has_key(t.kid):
		return _r(Result.UNKNOWN_KEY)
	var want := JoinTicket.mac_hex(ring.key_for(t.kid), t.body).to_utf8_buffer()
	if not Pbkdf2.constant_time_equals(want, str(t.mac).to_utf8_buffer()):
		return _r(Result.BAD_SIGNATURE)
	purge(now_unix)
	if _used.has(t.nonce):
		return _r(Result.REPLAYED)
	while _used.size() >= max_nonces:
		_used.erase(_used.keys()[0])
	_used[t.nonce] = int(t.expires)
	if t.match_id != match_id:
		return _r(Result.WRONG_MATCH)
	if expected_account != "" and t.account != expected_account:
		return _r(Result.WRONG_ACCOUNT)
	if now_unix > float(t.expires):
		return _r(Result.EXPIRED)
	if float(t.expires) - now_unix > max_ttl_s:
		return _r(Result.TOO_LONG)
	return {"result": Result.OK, "account": t.account}


## Forgets nonces whose ticket has expired (they fail on expiry anyway).
func purge(now_unix: float) -> void:
	for n in _used.keys():
		if now_unix > float(_used[n]):
			_used.erase(n)


func nonce_count() -> int:
	return _used.size()


static func _r(res: Result) -> Dictionary:
	return {"result": res, "account": ""}
