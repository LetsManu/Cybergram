class_name LaunchTokenStore
extends RefCounted
## Single-use launch tokens (W15): the launcher, already signed in, asks for
## one at Play and hands it to the game, which trades it for its own session
## (AccountCodec.OP_REDEEM). Rules:
## - 32 random bytes from the CSPRNG (256 bit), returned once as hex;
## - only the SHA-256 of the token is kept (a memory dump shows no usable token);
## - bound to one account, valid `ttl_s` seconds, consumed by the first
##   redeem attempt whatever its outcome (a wrong account burns it too);
## - one outstanding token per account (a new one revokes the old one).
## Memory only. Time is injected (`now` in seconds) so tests are deterministic.

enum Result { OK, UNKNOWN, EXPIRED, WRONG_ACCOUNT }

const TOKEN_BYTES := 32

var ttl_s: float = 60.0
var max_tokens: int = 4096
var _by_hash: Dictionary = {}  # sha256 hex -> {account: String, expires: float}
var _crypto := Crypto.new()


func _init(ttl_s_: float = 60.0, max_tokens_: int = 4096) -> void:
	ttl_s = ttl_s_
	max_tokens = max_tokens_


## Issues a token for `account_id` at time `now`; returns the raw token (hex).
func issue(account_id: String, now: float) -> String:
	revoke_account(account_id)
	purge(now)
	while _by_hash.size() >= max_tokens:
		_by_hash.erase(_by_hash.keys()[0])  # oldest first (insertion order)
	var raw := _crypto.generate_random_bytes(TOKEN_BYTES).hex_encode()
	_by_hash[hash_of(raw)] = {"account": account_id, "expires": now + ttl_s}
	return raw


## Redeems `raw` for `account_id`. The token is gone afterwards in every case.
func redeem(raw: String, account_id: String, now: float) -> Result:
	var h := hash_of(raw)
	var rec: Dictionary = _by_hash.get(h, {})
	if rec.is_empty():
		return Result.UNKNOWN
	_by_hash.erase(h)
	if now > float(rec.expires):
		return Result.EXPIRED
	if str(rec.account) != account_id:
		return Result.WRONG_ACCOUNT
	return Result.OK


## Drops every token of `account_id` (logout, password change, delete).
func revoke_account(account_id: String) -> void:
	for h in _by_hash.keys():
		if _by_hash[h].account == account_id:
			_by_hash.erase(h)


## Drops expired tokens.
func purge(now: float) -> void:
	for h in _by_hash.keys():
		if now > float(_by_hash[h].expires):
			_by_hash.erase(h)


## Tokens currently held (tests, diagnostics).
func count() -> int:
	return _by_hash.size()


## True when the store holds `raw` in clear anywhere (it never should).
func holds_plain(raw: String) -> bool:
	return _by_hash.has(raw) or str(_by_hash.values()).contains(raw)


## The stored form of a token: SHA-256 hex of its lower-case hex text.
static func hash_of(raw: String) -> String:
	return raw.to_lower().sha256_text()
