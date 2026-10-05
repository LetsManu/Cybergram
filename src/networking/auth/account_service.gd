class_name AccountService
extends RefCounted
## Server-side accounts (design/ux/lobby-and-social.md §6, PRIVACY.md):
## register / login / resume / guest sessions, profile, password change,
## export, delete (with cascade), friend requests, blocks and friend presence.
## One instance per server process (shared()), used by the lobby and the
## match server alike (handle() for ACCOUNT_REQ, on_disconnect(), step()).
##
## Rules: accounts need a DTLS link (`secure`), otherwise login / register are
## refused with E_NOT_SECURE (guests still work); passwords are PBKDF2-hashed
## off the sim thread (PasswordHasher); failed logins are rate-limited per
## (account, source address) and per source address (W11-Q1 SEC-002: a
## reconnect does not reset the limit, and a stranger cannot lock a player out
## of their own account); session tokens (32 random bytes) live in
## memory only and are dropped SESSION_GRACE after the connection is gone;
## inactive accounts are deleted after AuthRulesDef.retention_days (sweep at
## start and daily). Logs carry the 4-char id tag only, never usernames,
## display names, passwords or chat.
##
## Example (GameSession):
##   AccountService.configure_shared(FileAccountStore.new(dir), AuthConfig.rules(), enet.is_secure)
##   lobby = LobbyServer.new(enet, 3)   # uses AccountService.shared()

const SWEEP_EVERY_S := 86400.0
## Expired rate-limit entries (with IP addresses) are dropped this often.
const PURGE_EVERY_S := 60.0
## Per-connection account request budget (token bucket).
const REQ_BURST := 12.0
const REQ_PER_S := 3.0
## Hash used to keep the timing of "no such user" like a real check.
const DUMMY_SALT := "c7b1e0a4d2f3958b6a1c0e9d8f7a6b5c"

static var _shared: AccountService

var store: AccountStore
var rules: AuthRulesDef
## The transport is DTLS (accounts allowed). Tests may set it on loopback.
var secure: bool = false
## Guests may play (AuthConfig.allow_guests; always on without DTLS).
var allow_guests: bool = true
var hasher := PasswordHasher.new()
var registry: PresenceRegistry
var rl_account: LoginRateLimiter
var rl_peer: LoginRateLimiter
## peer -> identity {id, name, emblem, accent, guest, username, token, favourite_hero}
var peers: Dictionary = {}
## token -> {identity: Dictionary, peer: int (-1 = detached), detached_at: float}
var sessions: Dictionary = {}
var _jobs_by_peer: Dictionary = {}  # peer -> true while a hash job runs
var _req_budget: Dictionary = {}    # peer -> [tokens, last_s]
var _now: float = 0.0
var _since_sweep: float = 0.0
var _since_purge: float = 0.0
var _crypto := Crypto.new()
## W15 tuning (launch tokens, crash reports, parties).
var online: OnlineRulesDef
## W15: single-use launcher -> game sign-in tokens (hashes only).
var launch_tokens: LaunchTokenStore


## Process-wide service (guest-only until configure_shared()).
static func shared() -> AccountService:
	if _shared == null:
		_shared = AccountService.new(null, AuthRulesDef.new(), false)
	return _shared


## Sets up the process-wide service once (later calls only update `secure`).
static func configure_shared(store_: AccountStore, rules_: AuthRulesDef, secure_: bool,
		allow_guests_: bool = true) -> AccountService:
	if _shared == null or _shared.store == null:
		_shared = AccountService.new(store_, rules_, secure_)
	else:
		_shared.secure = secure_
	_shared.allow_guests = allow_guests_ or not secure_
	return _shared


## `store_` null = guest-only (no accounts at all).
func _init(store_: AccountStore, rules_: AuthRulesDef, secure_: bool, registry_: PresenceRegistry = null) -> void:
	store = store_
	rules = rules_ if rules_ != null else AuthRulesDef.new()
	secure = secure_
	registry = registry_ if registry_ != null else PresenceRegistry.shared()
	rl_account = LoginRateLimiter.new(rules.max_failures_per_account, rules.failure_window_s, rules.lockout_s)
	rl_peer = LoginRateLimiter.new(rules.max_failures_per_peer, rules.failure_window_s, rules.lockout_s)
	online = OnlineRulesDef.load_default()
	launch_tokens = LaunchTokenStore.new(online.launch_token_ttl_s, online.launch_tokens_max)
	if store != null:
		var swept := store.sweep_inactive(int(Time.get_unix_time_from_system()), rules.retention_days)
		if not swept.is_empty():
			print("[accounts] retention: deleted %d inactive account(s)" % swept.size())


## A new server connection layer (scene reload): peer numbers restart, so
## every attached session becomes detached (it may be resumed in the grace).
func reset_peers() -> void:
	for p in peers.keys():
		on_disconnect(p)


## Identity of the logged-in (or guest) player on `peer`, or {}.
func identity(peer: int) -> Dictionary:
	return peers.get(peer, {})


## Account ids blocked by the player on `peer` (chat filtering).
func blocks_of(peer: int) -> Array:
	var who: Dictionary = peers.get(peer, {})
	if who.is_empty() or who.guest or store == null:
		return []
	return store.get_by_id(who.id).get("blocks", [])


## Re-attaches the detached session of `account_id` to `peer` (the match
## connection after the lobby handover), so it lives while connected.
func adopt(account_id: String, peer: int) -> void:
	for tok in sessions:
		var s: Dictionary = sessions[tok]
		if s.identity.id == account_id and s.peer < 0:
			s.peer = peer
			peers[peer] = s.identity
			return


## The connection `peer` is gone: its session is kept for the grace only.
func on_disconnect(peer: int) -> void:
	peers.erase(peer)
	_req_budget.erase(peer)
	for tok in sessions:
		var s: Dictionary = sessions[tok]
		if s.peer == peer:
			s.peer = -1
			s.detached_at = _now


## Main thread, every frame: finished hash jobs, session expiry, daily sweep.
func step(delta: float) -> void:
	_now += delta
	for job in hasher.poll():
		_finish(job)
	for tok in sessions.keys():
		var s: Dictionary = sessions[tok]
		if s.peer < 0 and _now - float(s.detached_at) > rules.session_grace_s:
			sessions.erase(tok)
	_since_purge += delta
	if _since_purge >= PURGE_EVERY_S:
		# Failed-login entries hold an IP address: drop them once expired (PRIVACY.md).
		_since_purge = 0.0
		rl_account.purge(_now)
		rl_peer.purge(_now)
		launch_tokens.purge(_now)
	_since_sweep += delta
	if _since_sweep >= SWEEP_EVERY_S and store != null:
		_since_sweep = 0.0
		var swept := store.sweep_inactive(int(Time.get_unix_time_from_system()), rules.retention_days)
		if not swept.is_empty():
			print("[accounts] retention: deleted %d inactive account(s)" % swept.size())


## Handles one ACCOUNT_REQ packet from `peer`, replying on `t`.
func handle(t: Transport, peer: int, data: PackedByteArray) -> void:
	if not _budget(peer):
		return
	var r := AccountCodec.decode_request(data)
	if r.is_empty():
		_reply(t, peer, data.decode_u8(1) if data.size() > 1 else 0, AccountCodec.E_BAD_REQUEST)
		return
	var op: int = r.op
	match op:
		AccountCodec.OP_REGISTER:
			_register(t, peer, r)
		AccountCodec.OP_LOGIN:
			_login(t, peer, r)
		AccountCodec.OP_RESUME:
			_resume(t, peer, r)
		AccountCodec.OP_GUEST:
			_guest(t, peer, r)
		AccountCodec.OP_REDEEM:
			_redeem(t, peer, r)
		AccountCodec.OP_PING:
			_reply(t, peer, op, AccountCodec.OK)  # W15 RTT probe: answered at once
		AccountCodec.OP_LOGOUT:
			_logout(peer)
			_reply(t, peer, op, AccountCodec.OK)
		_:
			var who: Dictionary = peers.get(peer, {})
			if who.is_empty():
				_reply(t, peer, op, AccountCodec.E_NOT_LOGGED_IN)
			elif op == AccountCodec.OP_UPDATE_PROFILE:
				_update_profile(t, peer, who, r)
			elif who.guest:
				_reply(t, peer, op, AccountCodec.E_GUEST)
			elif not secure:
				_reply(t, peer, op, AccountCodec.E_NOT_SECURE)
			else:
				_account_op(t, peer, who, r)


# --- sessions ---------------------------------------------------------------

func _register(t: Transport, peer: int, r: Dictionary) -> void:
	var op := AccountCodec.OP_REGISTER
	if _jobs_by_peer.has(peer):
		_reply(t, peer, op, AccountCodec.E_BUSY)
		return
	var code := _session_preconditions(r)
	if code == AccountCodec.OK:
		code = _validate_new(r)
	if code != AccountCodec.OK:
		_reply(t, peer, op, code)
		return
	var salt := _crypto.generate_random_bytes(rules.salt_bytes)
	_jobs_by_peer[peer] = true
	hasher.submit(str(r.password).to_utf8_buffer(), salt, rules.pbkdf2_iterations,
		{"op": op, "peer": peer, "t": t, "r": _without_passwords(r), "salt": salt})


func _login(t: Transport, peer: int, r: Dictionary) -> void:
	var op := AccountCodec.OP_LOGIN
	if _jobs_by_peer.has(peer):
		_reply(t, peer, op, AccountCodec.E_BUSY)
		return
	var code := _session_preconditions(r)
	if code != AccountCodec.OK:
		_reply(t, peer, op, code)
		return
	var uname := str(r.username).to_lower()
	var pk := source_key(t, peer)
	if rl_account.is_locked(account_key(uname, pk), _now) or rl_peer.is_locked(pk, _now):
		_reply(t, peer, op, AccountCodec.E_LOCKED)
		return
	var a := store.find_username(uname)
	var salt := DUMMY_SALT.hex_decode()
	var iters := rules.pbkdf2_iterations
	if not a.is_empty():
		salt = str(a.password.salt).hex_decode()
		iters = int(a.password.iterations)
	_jobs_by_peer[peer] = true
	hasher.submit(str(r.password).to_utf8_buffer(), salt, iters,
		{"op": op, "peer": peer, "t": t, "uname": uname, "id": str(a.get("id", "")), "pk": pk})


func _resume(t: Transport, peer: int, r: Dictionary) -> void:
	var op := AccountCodec.OP_RESUME
	if int(r.ver) != MsgType.PROTOCOL_VERSION:
		_reply(t, peer, op, AccountCodec.E_VERSION)
		return
	var s: Dictionary = sessions.get(str(r.token), {})
	if s.is_empty() or (s.peer >= 0 and s.peer != peer):
		_reply(t, peer, op, AccountCodec.E_SESSION)
		return
	if not s.identity.guest and not secure:
		_reply(t, peer, op, AccountCodec.E_NOT_SECURE)
		return
	s.peer = peer
	peers[peer] = s.identity
	_reply(t, peer, op, AccountCodec.OK, _session_fields(s.identity))


## W15: the game trades the launcher's single-use launch token for its own
## session. DTLS only (an account credential), bound to the account in `id`.
## Every failure looks the same to the client (E_SESSION) and counts as a
## failed login for the source address.
func _redeem(t: Transport, peer: int, r: Dictionary) -> void:
	var op := AccountCodec.OP_REDEEM
	var code := _session_preconditions(r)
	if code != AccountCodec.OK:
		_reply(t, peer, op, code)
		return
	var pk := source_key(t, peer)
	if rl_peer.is_locked(pk, _now):
		_reply(t, peer, op, AccountCodec.E_LOCKED)
		return
	var res := launch_tokens.redeem(str(r.token), str(r.id), _now)
	var a := store.get_by_id(str(r.id)) if res == LaunchTokenStore.Result.OK else {}
	if a.is_empty():
		rl_peer.fail(pk, _now)
		print("[accounts] launch token refused on peer %d (%s)" % [peer,
			LaunchTokenStore.Result.keys()[res].to_lower() if res != LaunchTokenStore.Result.OK else "no account"])
		_reply(t, peer, op, AccountCodec.E_SESSION)
		return
	a.last_login_at = int(Time.get_unix_time_from_system())
	store.put(a)
	print("[accounts] launch token redeemed: account #%s (peer %d)" % [PlayerProfile.tag_of(a.id), peer])
	_logout(peer)
	_start_session(t, peer, op, _identity_of(a))


## W15: a launch token for the logged-in account on `peer` (DTLS only; the
## caller already checked: logged in, not a guest, secure service).
func _issue_launch_token(t: Transport, peer: int, me: Dictionary) -> void:
	var tok := launch_tokens.issue(str(me.id), _now)
	print("[accounts] launch token issued: account #%s (peer %d)" % [PlayerProfile.tag_of(me.id), peer])
	_reply(t, peer, AccountCodec.OP_LAUNCH_TOKEN, AccountCodec.OK,
		{"token": tok, "ttl": int(online.launch_token_ttl_s)})


func _guest(t: Transport, peer: int, r: Dictionary) -> void:
	var op := AccountCodec.OP_GUEST
	if int(r.ver) != MsgType.PROTOCOL_VERSION:
		_reply(t, peer, op, AccountCodec.E_VERSION)
		return
	if not allow_guests:
		_reply(t, peer, op, AccountCodec.E_GUESTS_OFF)
		return
	if (int(r.flags) & AccountCodec.FLAG_PRIVACY) == 0:
		_reply(t, peer, op, AccountCodec.E_CONSENT)
		return
	if not _valid_display(str(r.display_name)) or int(r.emblem) >= PlayerProfile.EMBLEM_COUNT \
			or int(r.accent) >= PlayerProfile.ACCENTS.size():
		_reply(t, peer, op, AccountCodec.E_BAD_NAME)
		return
	_logout(peer)
	var who := {"id": PlayerProfile.random_hex(16), "username": "", "name": str(r.display_name),
		"emblem": int(r.emblem), "accent": int(r.accent), "favourite_hero": "", "guest": true}
	_start_session(t, peer, op, who)
	print("[accounts] guest #%s on peer %d" % [PlayerProfile.tag_of(who.id), peer])


func _logout(peer: int) -> void:
	var who: Dictionary = peers.get(peer, {})
	peers.erase(peer)
	if not who.is_empty():
		sessions.erase(str(who.get("token", "")))


func _start_session(t: Transport, peer: int, op: int, who: Dictionary) -> void:
	var tok := _crypto.generate_random_bytes(AccountCodec.TOKEN_BYTES).hex_encode()
	who["token"] = tok
	sessions[tok] = {"identity": who, "peer": peer, "detached_at": 0.0}
	peers[peer] = who
	_reply(t, peer, op, AccountCodec.OK, _session_fields(who))


func _session_fields(who: Dictionary) -> Dictionary:
	return {"token": who.token, "id": who.id, "username": who.username, "display_name": who.name,
		"emblem": who.emblem, "accent": who.accent, "favourite_hero": who.favourite_hero,
		"guest": 1 if who.guest else 0}


func _identity_of(a: Dictionary) -> Dictionary:
	var p: Dictionary = a.profile
	return {"id": a.id, "username": a.username, "name": str(p.get("display_name", a.username)),
		"emblem": int(p.get("emblem", 0)), "accent": int(p.get("accent", 0)),
		"favourite_hero": str(p.get("favourite_hero", "")), "guest": false}


## Version + DTLS + an account store, for register / login.
func _session_preconditions(r: Dictionary) -> int:
	if int(r.ver) != MsgType.PROTOCOL_VERSION:
		return AccountCodec.E_VERSION
	if not secure or store == null:
		return AccountCodec.E_NOT_SECURE
	return AccountCodec.OK


func _validate_new(r: Dictionary) -> int:
	var flags := int(r.flags)
	if (flags & AccountCodec.FLAG_PRIVACY) == 0:
		return AccountCodec.E_CONSENT
	if (flags & AccountCodec.FLAG_AGE) == 0:
		return AccountCodec.E_AGE
	if not valid_username(str(r.username)):
		return AccountCodec.E_BAD_USERNAME
	if not _valid_password(str(r.password)):
		return AccountCodec.E_WEAK_PASSWORD
	if not _valid_display(str(r.display_name)) or int(r.emblem) >= PlayerProfile.EMBLEM_COUNT \
			or int(r.accent) >= PlayerProfile.ACCENTS.size():
		return AccountCodec.E_BAD_NAME
	if not store.find_username(str(r.username)).is_empty():
		return AccountCodec.E_NAME_TAKEN
	if store.count() >= rules.max_accounts:
		return AccountCodec.E_LIMIT
	return AccountCodec.OK


## Usernames: 3-16 of a-z A-Z 0-9 _ - . (no spaces), not filtered; unique
## case-insensitively.
static func valid_username(u: String) -> bool:
	return PlayerProfile.validate_name(u) == PlayerProfile.NameError.OK and not u.contains(" ") \
		and PlayerProfile.name_allowed(u)


func _valid_password(p: String) -> bool:
	var n := p.to_utf8_buffer().size()
	return n >= rules.password_min and n <= rules.password_max


static func _valid_display(n: String) -> bool:
	return PlayerProfile.validate_name(n) == PlayerProfile.NameError.OK and PlayerProfile.name_allowed(n)


# --- hash jobs --------------------------------------------------------------

func _finish(job: PasswordHasher.Job) -> void:
	var c := job.context
	var peer: int = c.peer
	var t: Transport = c.t
	_jobs_by_peer.erase(peer)
	match int(c.op):
		AccountCodec.OP_REGISTER:
			var r: Dictionary = c.r
			if not store.find_username(str(r.username)).is_empty():
				_reply(t, peer, c.op, AccountCodec.E_NAME_TAKEN)
				return
			var now := int(Time.get_unix_time_from_system())
			var pw := {"algo": "pbkdf2-hmac-sha256", "hash": job.hash.hex_encode(),
				"salt": (c.salt as PackedByteArray).hex_encode(), "iterations": job.iterations}
			var profile := {"display_name": str(r.display_name), "emblem": int(r.emblem), "accent": int(r.accent),
				"favourite_hero": ""}
			var a := AccountStore.new_account(PlayerProfile.random_hex(16), str(r.username), pw, profile, now)
			if not store.put(a):
				_reply(t, peer, c.op, AccountCodec.E_STORE)
				return
			print("[accounts] registered account #%s (peer %d)" % [PlayerProfile.tag_of(a.id), peer])
			_logout(peer)
			_start_session(t, peer, c.op, _identity_of(a))
		AccountCodec.OP_LOGIN:
			var a := store.get_by_id(str(c.id)) if str(c.id) != "" else {}
			var ok := not a.is_empty() and Pbkdf2.constant_time_equals(job.hash, str(a.password.hash).hex_decode())
			if not ok:
				rl_account.fail(account_key(str(c.uname), str(c.pk)), _now)
				rl_peer.fail(str(c.pk), _now)
				print("[accounts] failed login on peer %d" % peer)
				_reply(t, peer, c.op, AccountCodec.E_CREDENTIALS)
				return
			rl_account.succeed(account_key(str(c.uname), str(c.pk)))
			a.last_login_at = int(Time.get_unix_time_from_system())
			store.put(a)
			print("[accounts] login account #%s (peer %d)" % [PlayerProfile.tag_of(a.id), peer])
			_logout(peer)
			_start_session(t, peer, c.op, _identity_of(a))
		AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.OP_DELETE_ACCOUNT:
			_finish_verified(job, c, t, peer)
		-1:
			# Second stage of a password change: the new hash.
			var a := store.get_by_id(str(c.id))
			if a.is_empty():
				_reply(t, peer, AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.E_NOT_FOUND)
				return
			a.password = {"algo": "pbkdf2-hmac-sha256", "hash": job.hash.hex_encode(),
				"salt": (c.salt as PackedByteArray).hex_encode(), "iterations": job.iterations}
			if not store.put(a):
				_reply(t, peer, AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.E_STORE)
				return
			end_other_sessions(a.id, peer)
			launch_tokens.revoke_account(a.id)
			_reply(t, peer, AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.OK)


## CHANGE_PASSWORD / DELETE_ACCOUNT after the current password was checked.
func _finish_verified(job: PasswordHasher.Job, c: Dictionary, t: Transport, peer: int) -> void:
	var op: int = c.op
	var a := store.get_by_id(str(c.id))
	if a.is_empty() or not Pbkdf2.constant_time_equals(job.hash, str(a.password.hash).hex_decode()):
		rl_account.fail(account_key(str(c.uname), str(c.pk)), _now)
		rl_peer.fail(str(c.pk), _now)
		_reply(t, peer, op, AccountCodec.E_CREDENTIALS)
		return
	if op == AccountCodec.OP_DELETE_ACCOUNT:
		store.delete_cascade(a.id)
		launch_tokens.revoke_account(a.id)
		for tok in sessions.keys():
			if sessions[tok].identity.id == a.id:
				sessions.erase(tok)
		for p in peers.keys():
			if peers[p].id == a.id:
				peers.erase(p)
		registry.forget(a.id)
		print("[accounts] deleted account #%s on request" % PlayerProfile.tag_of(a.id))
		_reply(t, peer, op, AccountCodec.OK)
		return
	var salt := _crypto.generate_random_bytes(rules.salt_bytes)
	_jobs_by_peer[peer] = true
	hasher.submit(str(c.new_password).to_utf8_buffer(), salt, rules.pbkdf2_iterations,
		{"op": -1, "peer": peer, "t": t, "id": a.id, "salt": salt})


# --- account ops (logged in, DTLS) -----------------------------------------

func _account_op(t: Transport, peer: int, who: Dictionary, r: Dictionary) -> void:
	var op: int = r.op
	var me := store.get_by_id(who.id)
	if me.is_empty():
		_logout(peer)
		_reply(t, peer, op, AccountCodec.E_NOT_LOGGED_IN)
		return
	match op:
		AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.OP_DELETE_ACCOUNT:
			if _jobs_by_peer.has(peer):
				_reply(t, peer, op, AccountCodec.E_BUSY)
				return
			var pk := source_key(t, peer)
			var uname := str(me.username).to_lower()
			if rl_account.is_locked(account_key(uname, pk), _now) or rl_peer.is_locked(pk, _now):
				_reply(t, peer, op, AccountCodec.E_LOCKED)
				return
			var pw := str(r.get("old_password", r.get("password", "")))
			if op == AccountCodec.OP_CHANGE_PASSWORD and not _valid_password(str(r.new_password)):
				_reply(t, peer, op, AccountCodec.E_WEAK_PASSWORD)
				return
			_jobs_by_peer[peer] = true
			hasher.submit(pw.to_utf8_buffer(), str(me.password.salt).hex_decode(), int(me.password.iterations),
				{"op": op, "peer": peer, "t": t, "id": me.id, "new_password": str(r.get("new_password", "")),
				"uname": uname, "pk": pk})
		AccountCodec.OP_EXPORT:
			_reply(t, peer, op, AccountCodec.OK, {"json": export_json(me)})
		AccountCodec.OP_LAUNCH_TOKEN:
			_issue_launch_token(t, peer, me)
		AccountCodec.OP_FRIENDS:
			_reply(t, peer, op, AccountCodec.OK, {"friends": friends_list(me)})
		AccountCodec.OP_FRIEND_REQUEST:
			var by_id := str(r.id)
			_reply(t, peer, op, friend_request(me, str(r.username)) if LobbyCodec.is_none_id(by_id) \
				else friend_request_id(me, by_id))
		AccountCodec.OP_FRIEND_ACCEPT:
			_reply(t, peer, op, friend_accept(me, str(r.id)))
		AccountCodec.OP_FRIEND_DECLINE:
			_reply(t, peer, op, friend_decline(me, str(r.id)))
		AccountCodec.OP_FRIEND_REMOVE:
			_reply(t, peer, op, friend_remove(me, str(r.id)))
		AccountCodec.OP_BLOCK:
			_reply(t, peer, op, block(me, str(r.id)))
		AccountCodec.OP_UNBLOCK:
			_reply(t, peer, op, unblock(me, str(r.id)))


func _update_profile(t: Transport, peer: int, who: Dictionary, r: Dictionary) -> void:
	var op := AccountCodec.OP_UPDATE_PROFILE
	var hero := str(r.favourite_hero)
	var hero_ok := hero == "" or ContentDB.shared().index_of(ContentDB.HERO, StringName("hero_" + hero)) != ContentDB.NONE
	if not _valid_display(str(r.display_name)) or int(r.emblem) >= PlayerProfile.EMBLEM_COUNT \
			or int(r.accent) >= PlayerProfile.ACCENTS.size() or not hero_ok:
		_reply(t, peer, op, AccountCodec.E_BAD_NAME)
		return
	who.name = str(r.display_name)
	who.emblem = int(r.emblem)
	who.accent = int(r.accent)
	who.favourite_hero = hero
	if not who.guest:
		if not secure:
			_reply(t, peer, op, AccountCodec.E_NOT_SECURE)
			return
		var a := store.get_by_id(who.id)
		if a.is_empty():
			_reply(t, peer, op, AccountCodec.E_NOT_FOUND)
			return
		a.profile = {"display_name": who.name, "emblem": who.emblem, "accent": who.accent, "favourite_hero": hero}
		if not store.put(a):
			_reply(t, peer, op, AccountCodec.E_STORE)
			return
	_reply(t, peer, op, AccountCodec.OK, {"display_name": who.name, "emblem": who.emblem, "accent": who.accent,
		"favourite_hero": hero})


## The account as readable JSON, without the password hash and salt.
static func export_json(a: Dictionary) -> String:
	var out := a.duplicate(true)
	out.password = {"algo": a.password.get("algo", ""), "iterations": a.password.get("iterations", 0),
		"note": "the password hash and salt are not exported"}
	out["exported_at"] = int(Time.get_unix_time_from_system())
	out["note"] = "Everything the Cybergram server stores about this account. Chat is never stored."
	return JSON.stringify(out, "  ")


## FRIENDS entries: friends with presence, incoming / outgoing requests, blocks.
func friends_list(me: Dictionary) -> Array:
	var out: Array = []
	var rel := [[me.friends, AccountCodec.REL_FRIEND], [me.requests_in, AccountCodec.REL_INCOMING],
		[me.requests_out, AccountCodec.REL_OUTGOING], [me.blocks, AccountCodec.REL_BLOCKED]]
	for pair in rel:
		for id in pair[0]:
			var o := store.get_by_id(str(id))
			if o.is_empty():
				continue
			var p: Dictionary = o.profile
			var st := status_of(o.id) if pair[1] == AccountCodec.REL_FRIEND else LobbyCodec.STATUS_OFFLINE
			out.append({"id": o.id, "status": st, "relation": pair[1], "username": o.username,
				"display_name": str(p.get("display_name", o.username)), "emblem": int(p.get("emblem", 0)),
				"accent": int(p.get("accent", 0))})
	return out


## Presence of an account: in lobby / in match (PresenceRegistry), online
## (an attached session), else offline. Only shown to accepted friends.
func status_of(account_id: String) -> int:
	var st := registry.status_of(account_id, PresenceRegistry.now_s())
	if st == LobbyCodec.STATUS_IN_LOBBY or st == LobbyCodec.STATUS_IN_MATCH:
		return st
	for p in peers:
		if peers[p].id == account_id:
			return LobbyCodec.STATUS_ONLINE
	return LobbyCodec.STATUS_OFFLINE


func friend_request(me: Dictionary, username: String) -> int:
	var o := store.find_username(username)
	return _friend_request(me, o)


## Friend request by player id (the "+" on a lobby row).
func friend_request_id(me: Dictionary, id: String) -> int:
	return _friend_request(me, store.get_by_id(id))


func _friend_request(me: Dictionary, o: Dictionary) -> int:
	if o.is_empty() or o.id == me.id:
		return AccountCodec.E_NOT_FOUND
	if (o.friends as Array).has(me.id):
		return AccountCodec.OK
	if (me.blocks as Array).has(o.id):
		return AccountCodec.E_BAD_REQUEST
	if (o.blocks as Array).has(me.id):
		return AccountCodec.OK  # silently dropped: a block is not revealed
	if (me.requests_in as Array).has(o.id):
		return friend_accept(me, o.id)  # they asked first: now friends
	if (me.requests_out as Array).size() >= rules.max_pending_requests \
			or (o.requests_in as Array).size() >= rules.max_pending_requests:
		return AccountCodec.E_LIMIT
	if not (me.requests_out as Array).has(o.id):
		me.requests_out.append(o.id)
		o.requests_in.append(me.id)
	return AccountCodec.OK if store.put(me) and store.put(o) else AccountCodec.E_STORE


func friend_accept(me: Dictionary, id: String) -> int:
	var o := store.get_by_id(id)
	if o.is_empty() or not (me.requests_in as Array).has(id):
		return AccountCodec.E_NOT_FOUND
	if (me.friends as Array).size() >= rules.max_friends or (o.friends as Array).size() >= rules.max_friends:
		return AccountCodec.E_LIMIT
	me.requests_in.erase(id)
	o.requests_out.erase(me.id)
	if not (me.friends as Array).has(id):
		me.friends.append(id)
	if not (o.friends as Array).has(me.id):
		o.friends.append(me.id)
	return AccountCodec.OK if store.put(me) and store.put(o) else AccountCodec.E_STORE


func friend_decline(me: Dictionary, id: String) -> int:
	var o := store.get_by_id(id)
	me.requests_in.erase(id)
	if not o.is_empty():
		o.requests_out.erase(me.id)
		store.put(o)
	return AccountCodec.OK if store.put(me) else AccountCodec.E_STORE


func friend_remove(me: Dictionary, id: String) -> int:
	var o := store.get_by_id(id)
	me.friends.erase(id)
	me.requests_out.erase(id)
	if not o.is_empty():
		o.friends.erase(me.id)
		o.requests_in.erase(me.id)
		store.put(o)
	return AccountCodec.OK if store.put(me) else AccountCodec.E_STORE


func block(me: Dictionary, id: String) -> int:
	var o := store.get_by_id(id)
	if o.is_empty() or id == me.id:
		return AccountCodec.E_NOT_FOUND
	if (me.blocks as Array).size() >= rules.max_blocks:
		return AccountCodec.E_LIMIT
	friend_remove(me, id)
	me = store.get_by_id(me.id)
	o = store.get_by_id(id)
	me.requests_in.erase(id)
	o.requests_out.erase(me.id)
	if not (me.blocks as Array).has(id):
		me.blocks.append(id)
	return AccountCodec.OK if store.put(me) and store.put(o) else AccountCodec.E_STORE


func unblock(me: Dictionary, id: String) -> int:
	me.blocks.erase(id)
	return AccountCodec.OK if store.put(me) else AccountCodec.E_STORE


# --- helpers ----------------------------------------------------------------

## Rate-limit key of the sender: its IP address, or the connection when the
## transport has none (loopback). In memory only, never logged.
static func source_key(t: Transport, peer: int) -> String:
	var addr := t.peer_address(peer) if t != null else ""
	return "a:" + addr if addr != "" else "p:%d" % peer


## Rate-limit key of an account as tried from one source.
static func account_key(uname: String, source: String) -> String:
	return "u:%s|%s" % [uname.to_lower(), source]


## Ends every session of `account_id` except the one on `keep_peer` (after a
## password change: a stolen token or a forgotten login elsewhere stops working).
func end_other_sessions(account_id: String, keep_peer: int) -> void:
	for tok in sessions.keys():
		var s: Dictionary = sessions[tok]
		if s.identity.id == account_id and s.peer != keep_peer:
			if int(s.peer) >= 0:
				peers.erase(s.peer)
			sessions.erase(tok)


func _reply(t: Transport, peer: int, op: int, code: int, fields: Dictionary = {}) -> void:
	t.send(peer, Transport.CH_CONTROL, AccountCodec.encode_result(op, code, fields))


func _budget(peer: int) -> bool:
	var b: Array = _req_budget.get(peer, [REQ_BURST, _now])
	var tokens := minf(REQ_BURST, float(b[0]) + (_now - float(b[1])) * REQ_PER_S)
	if tokens < 1.0:
		_req_budget[peer] = [tokens, _now]
		return false
	_req_budget[peer] = [tokens - 1.0, _now]
	return true


static func _without_passwords(r: Dictionary) -> Dictionary:
	var out := r.duplicate()
	out.erase("password")
	out.erase("old_password")
	out.erase("new_password")
	return out
