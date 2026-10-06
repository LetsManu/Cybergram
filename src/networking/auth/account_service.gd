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
## Profile key of the public leaderboard opt-in (W20-WEB; absent = off).
const PROFILE_LEADERBOARD := "leaderboard_public"
## Hash used to keep the timing of "no such user" like a real check.
const DUMMY_SALT := "c7b1e0a4d2f3958b6a1c0e9d8f7a6b5c"

## Internal second stages of hash jobs (negative: never a wire op).
const STAGE_NEW_PASSWORD := -1      ## change password: the new hash
const STAGE_REGISTER_CODE := -2     ## register: the recovery code hash
const STAGE_REGEN_CODE := -3        ## RECOVERY_CODE: the new code hash
const STAGE_RECOVER_PASSWORD := -4  ## RECOVER: the new password hash
const STAGE_RECOVER_CODE := -5      ## RECOVER: the next code hash
## Key of the recovery code record inside the account's `password` object
## (W21-N1). Nested there, not a new top-level key: AccountStore.is_well_formed
## stays the same, so an older server image still loads these accounts.
const RECOVERY_KEY := "recovery"

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
## W15: opt-in crash reports (null = not accepted on this server).
var crash_store: CrashReportStore
## W15: parties (memory only).
var parties: PartyService
## P2: presence from the matchmaking front: func(account_id) -> {status, mode}
## ({} = unknown, fall back to the lobby registry). Set by MatchmakingFront.
var presence_fn: Callable = Callable()
## P2: accounts that set themselves away (id -> true; memory only).
var away: Dictionary = {}
## P2: per-account social rate buckets ("chat:<id>" / "invite:<id>" -> [tokens, last_s]).
var _social_rl: Dictionary = {}
## The transport of the last request: social notifications are pushed on it.
var _push_t: Transport
var _crash_up: Dictionary = {}  # peer -> {total, next, buf: PackedByteArray, started}
## W21-N1: folder of host reset requests (AccountAdmin; "" = off).
var admin_dir: String = ""
var _since_admin: float = 1.0e9  # the first step() looks at once

## W17B: an account was deleted (by its owner or by the inactivity sweep);
## other stores (ratings, reports, match history, lockouts) erase it too.
signal account_deleted(account_id: String)


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
	if store_ != null and _shared.admin_dir == "":
		_shared.admin_dir = AuthConfig.from_os().admin_dir()  # W21-N1 host password resets
	if secure_ and _shared.crash_store == null:
		# W15: crash reports only where they can arrive encrypted.
		_shared.crash_store = CrashReportStore.new(AuthConfig.from_os().crash_reports_dir(), _shared.online)
		var n := _shared.crash_store.sweep(int(Time.get_unix_time_from_system()))
		if n > 0:
			print("[crash] retention: deleted %d old report(s)" % n)
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
	parties = PartyService.new(online.party_max, online.party_invite_ttl_s)
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
	_crash_up.erase(peer)
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
		parties.purge(_now)
		for id in away.keys():
			if not _has_session(str(id)):
				away.erase(id)  # P2: away is a session flag
		for id in parties.members() + parties.invites.keys():
			if not _has_session(str(id)):
				parties.forget(str(id))  # no connection left (after the grace): out of the party
	_since_sweep += delta
	if _since_sweep >= SWEEP_EVERY_S and store != null:
		_since_sweep = 0.0
		var swept := store.sweep_inactive(int(Time.get_unix_time_from_system()), rules.retention_days)
		if not swept.is_empty():
			print("[accounts] retention: deleted %d inactive account(s)" % swept.size())
		for id in swept:
			account_deleted.emit(str(id))
		if crash_store != null:
			var n := crash_store.sweep(int(Time.get_unix_time_from_system()))
			if n > 0:
				print("[crash] retention: deleted %d old report(s)" % n)
	for p in _crash_up.keys():
		if _now - float(_crash_up[p].started) > online.crash_upload_timeout_s:
			_crash_up.erase(p)
	if store != null and admin_dir != "":
		_since_admin += delta
		if _since_admin >= rules.admin_poll_s:
			_since_admin = 0.0
			poll_admin()


## Handles one ACCOUNT_REQ packet from `peer`, replying on `t`.
func handle(t: Transport, peer: int, data: PackedByteArray) -> void:
	# Crash report chunks have their own limits (CrashReportStore), not the request budget.
	_push_t = t
	var is_chunk := data.size() > 1 and data.decode_u8(1) == AccountCodec.OP_CRASH_CHUNK
	if not is_chunk and not _budget(peer):
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
		AccountCodec.OP_RECOVER:
			_recover(t, peer, r)
		AccountCodec.OP_RESUME:
			_resume(t, peer, r)
		AccountCodec.OP_GUEST:
			_guest(t, peer, r)
		AccountCodec.OP_REDEEM:
			_redeem(t, peer, r)
		AccountCodec.OP_CRASH_CHUNK:
			_crash_chunk(t, peer, r)
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
	hasher.submit(login_form(str(r.password)).to_utf8_buffer(), salt, iters,
		{"op": op, "peer": peer, "t": t, "uname": uname, "id": str(a.get("id", "")), "pk": pk})


## W21-N1: password recovery with the one-time recovery code. No session
## needed; DTLS only; rate-limited and answered exactly like a login (an
## unknown user, an account without a code and a wrong code all hash once
## and give E_CREDENTIALS), so it is not an account oracle.
func _recover(t: Transport, peer: int, r: Dictionary) -> void:
	var op := AccountCodec.OP_RECOVER
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
	if not _valid_password(str(r.new_password)):
		_reply(t, peer, op, AccountCodec.E_WEAK_PASSWORD)
		return
	var a := store.find_username(uname)
	var rec := recovery_of(a)
	var salt := DUMMY_SALT.hex_decode()
	var iters := rules.pbkdf2_iterations
	if not rec.is_empty():
		salt = str(rec.salt).hex_decode()
		iters = int(rec.iterations)
	var canon := RecoveryCode.normalize(str(r.code), rules)
	_jobs_by_peer[peer] = true
	hasher.submit((canon if canon != "" else str(r.code)).to_utf8_buffer(), salt, iters,
		{"op": op, "peer": peer, "t": t, "uname": uname, "id": str(a.get("id", "")), "pk": pk,
		"well_formed": canon != "", "new_password": str(r.new_password)})


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


## W15: one chunk of an opt-in crash report. DTLS only; chunks arrive in
## order (reliable channel); the first one checks the rate limits, the last
## one stores the report. Answers only on the last chunk or on an error.
func _crash_chunk(t: Transport, peer: int, r: Dictionary) -> void:
	var op := AccountCodec.OP_CRASH_CHUNK
	var seq := int(r.seq)
	var total := int(r.total)
	var max_chunks := ceili(float(online.crash_max_bytes) / AccountCodec.CHUNK_MAX)
	if not secure or crash_store == null:
		if seq == 0:
			_reply(t, peer, op, AccountCodec.E_NOT_SECURE)
		return
	var who: Dictionary = peers.get(peer, {})
	var account := "" if who.is_empty() or who.guest else str(who.id)
	if seq == 0:
		if total < 1 or total > max_chunks:
			_reply(t, peer, op, AccountCodec.E_BAD_REQUEST)
			return
		if not crash_store.allowed(source_key(t, peer), account, int(Time.get_unix_time_from_system())):
			_reply(t, peer, op, AccountCodec.E_RATE)
			return
		_crash_up[peer] = {"total": total, "next": 0, "buf": PackedByteArray(), "started": _now}
	var up: Dictionary = _crash_up.get(peer, {})
	if up.is_empty():
		return  # chunks of a refused / dropped upload
	if seq != int(up.next) or total != int(up.total):
		_crash_up.erase(peer)
		_reply(t, peer, op, AccountCodec.E_BAD_REQUEST)
		return
	var buf: PackedByteArray = up.buf  # a value type: append, then store back
	buf.append_array(r.data)
	up.buf = buf
	up.next = seq + 1
	if buf.size() > online.crash_max_bytes:
		_crash_up.erase(peer)
		_reply(t, peer, op, AccountCodec.E_BAD_REQUEST)
		return
	if int(up.next) < total:
		return
	_crash_up.erase(peer)
	var res := crash_store.accept(up.buf, source_key(t, peer), account, int(Time.get_unix_time_from_system()))
	var codes := {CrashReportStore.Result.OK: AccountCodec.OK, CrashReportStore.Result.RATE_LIMITED: AccountCodec.E_RATE,
		CrashReportStore.Result.STORE_FAILED: AccountCodec.E_STORE}
	var code: int = codes.get(res, AccountCodec.E_BAD_REQUEST)
	print("[crash] report from peer %d: %s (%d bytes)" % [peer, CrashReportStore.Result.keys()[res].to_lower(),
		(up.buf as PackedByteArray).size()])
	_reply(t, peer, op, code, {"seq": seq})


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


## `extra`: more result fields (W21-N1: the new recovery code, shown once).
func _start_session(t: Transport, peer: int, op: int, who: Dictionary, extra: Dictionary = {}) -> void:
	var tok := _crypto.generate_random_bytes(AccountCodec.TOKEN_BYTES).hex_encode()
	who["token"] = tok
	sessions[tok] = {"identity": who, "peer": peer, "detached_at": 0.0}
	peers[peer] = who
	var fields := _session_fields(who)
	fields.merge(extra)
	_reply(t, peer, op, AccountCodec.OK, fields)


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


## The form of a typed password that is checked against the stored hash
## (W21-N1 relog fix). Up to v0.15 the game's password fields had
## max_length = password_max characters, so a longer password (pasted from a
## password manager) was cut to its first password_max characters at
## registration / change, while the launcher field (128) sent all of it: the
## same password then failed in the launcher with "wrong username or
## password". No stored password is longer than password_max bytes (the
## server never accepted one), so a longer one can only ever match as that
## prefix: checking the prefix gives an attacker nothing (still one hash per
## attempt, same rate limit) and makes both clients agree.
func login_form(p: String) -> String:
	if p.to_utf8_buffer().size() <= rules.password_max:
		return p
	return p.left(rules.password_max)


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
			_submit_code(STAGE_REGISTER_CODE, {"peer": peer, "t": t, "account": a})
		STAGE_REGISTER_CODE:
			var a: Dictionary = c.account
			if not store.find_username(str(a.username)).is_empty():
				_reply(t, peer, AccountCodec.OP_REGISTER, AccountCodec.E_NAME_TAKEN)
				return
			a.password[RECOVERY_KEY] = _code_record(job)
			if not store.put(a):
				_reply(t, peer, AccountCodec.OP_REGISTER, AccountCodec.E_STORE)
				return
			print("[accounts] registered account #%s (peer %d)" % [PlayerProfile.tag_of(a.id), peer])
			_logout(peer)
			_start_session(t, peer, AccountCodec.OP_REGISTER, _identity_of(a), {"recovery_code": str(c.code)})
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
		AccountCodec.OP_RECOVER:
			_finish_recover(job, c, t, peer)
		AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.OP_DELETE_ACCOUNT, AccountCodec.OP_RECOVERY_CODE:
			_finish_verified(job, c, t, peer)
		STAGE_REGEN_CODE:
			var a := store.get_by_id(str(c.id))
			if a.is_empty():
				_reply(t, peer, AccountCodec.OP_RECOVERY_CODE, AccountCodec.E_NOT_FOUND)
				return
			a.password[RECOVERY_KEY] = _code_record(job)
			if not store.put(a):
				_reply(t, peer, AccountCodec.OP_RECOVERY_CODE, AccountCodec.E_STORE)
				return
			print("[accounts] new recovery code: account #%s (peer %d)" % [PlayerProfile.tag_of(a.id), peer])
			_reply(t, peer, AccountCodec.OP_RECOVERY_CODE, AccountCodec.OK, {"recovery_code": str(c.code)})
		STAGE_RECOVER_PASSWORD:
			_submit_code(STAGE_RECOVER_CODE, {"peer": peer, "t": t, "id": str(c.id),
				"password": _password_record(job, c.salt)})
		STAGE_RECOVER_CODE:
			var a := store.get_by_id(str(c.id))
			if a.is_empty():
				_reply(t, peer, AccountCodec.OP_RECOVER, AccountCodec.E_CREDENTIALS)
				return
			var pw: Dictionary = c.password
			pw[RECOVERY_KEY] = _code_record(job)
			a.password = pw
			a.last_login_at = int(Time.get_unix_time_from_system())
			if not store.put(a):
				_reply(t, peer, AccountCodec.OP_RECOVER, AccountCodec.E_STORE)
				return
			end_other_sessions(a.id, -2)  # every session, this connection's included
			launch_tokens.revoke_account(a.id)
			print("[accounts] password recovered: account #%s (peer %d)" % [PlayerProfile.tag_of(a.id), peer])
			_logout(peer)
			_start_session(t, peer, AccountCodec.OP_RECOVER, _identity_of(a), {"recovery_code": str(c.code)})
		STAGE_NEW_PASSWORD:
			# Second stage of a password change: the new hash.
			var a := store.get_by_id(str(c.id))
			if a.is_empty():
				_reply(t, peer, AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.E_NOT_FOUND)
				return
			var keep := recovery_of(a)
			a.password = _password_record(job, c.salt)
			if not keep.is_empty():
				a.password[RECOVERY_KEY] = keep  # a password change keeps the recovery code
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
		account_deleted.emit(str(a.id))
		launch_tokens.revoke_account(a.id)
		parties.forget(a.id)
		away.erase(a.id)
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
	if op == AccountCodec.OP_RECOVERY_CODE:
		_submit_code(STAGE_REGEN_CODE, {"peer": peer, "t": t, "id": a.id})
		return
	var salt := _crypto.generate_random_bytes(rules.salt_bytes)
	_jobs_by_peer[peer] = true
	hasher.submit(str(c.new_password).to_utf8_buffer(), salt, rules.pbkdf2_iterations,
		{"op": STAGE_NEW_PASSWORD, "peer": peer, "t": t, "id": a.id, "salt": salt})


## RECOVER after the code hash: a match uses the code up at once (a second
## request with the same code fails from here on), then hashes the new
## password and the next code (STAGE_RECOVER_PASSWORD / _CODE).
func _finish_recover(job: PasswordHasher.Job, c: Dictionary, t: Transport, peer: int) -> void:
	var op := AccountCodec.OP_RECOVER
	var a := store.get_by_id(str(c.id)) if str(c.id) != "" else {}
	var rec := recovery_of(a)
	var ok := bool(c.well_formed) and not rec.is_empty() \
		and Pbkdf2.constant_time_equals(job.hash, str(rec.get("hash", "")).hex_decode())
	if not ok:
		rl_account.fail(account_key(str(c.uname), str(c.pk)), _now)
		rl_peer.fail(str(c.pk), _now)
		print("[accounts] failed recovery on peer %d" % peer)
		_reply(t, peer, op, AccountCodec.E_CREDENTIALS)
		return
	rl_account.succeed(account_key(str(c.uname), str(c.pk)))
	(a.password as Dictionary).erase(RECOVERY_KEY)
	if not store.put(a):
		_reply(t, peer, op, AccountCodec.E_STORE)
		return
	var salt := _crypto.generate_random_bytes(rules.salt_bytes)
	_jobs_by_peer[peer] = true
	hasher.submit(str(c.new_password).to_utf8_buffer(), salt, rules.pbkdf2_iterations,
		{"op": STAGE_RECOVER_PASSWORD, "peer": peer, "t": t, "id": a.id, "salt": salt})


## Queues the hash of a fresh recovery code as stage `stage`; `ctx` comes
## back with `code` (the plaintext, kept only until the reply) and `salt`.
func _submit_code(stage: int, ctx: Dictionary) -> void:
	var code := RecoveryCode.generate(rules)
	var salt := _crypto.generate_random_bytes(rules.salt_bytes)
	ctx["op"] = stage
	ctx["code"] = code
	ctx["salt"] = salt
	_jobs_by_peer[int(ctx.peer)] = true
	hasher.submit(RecoveryCode.normalize(code, rules).to_utf8_buffer(), salt, rules.pbkdf2_iterations, ctx)


func _code_record(job: PasswordHasher.Job) -> Dictionary:
	return RecoveryCode.record(job.hash, job.context.salt, job.iterations, int(Time.get_unix_time_from_system()))


static func _password_record(job: PasswordHasher.Job, salt: PackedByteArray) -> Dictionary:
	return {"algo": "pbkdf2-hmac-sha256", "hash": job.hash.hex_encode(), "salt": salt.hex_encode(),
		"iterations": job.iterations}


# --- account ops (logged in, DTLS) -----------------------------------------

func _account_op(t: Transport, peer: int, who: Dictionary, r: Dictionary) -> void:
	var op: int = r.op
	var me := store.get_by_id(who.id)
	if me.is_empty():
		_logout(peer)
		_reply(t, peer, op, AccountCodec.E_NOT_LOGGED_IN)
		return
	match op:
		AccountCodec.OP_CHANGE_PASSWORD, AccountCodec.OP_DELETE_ACCOUNT, AccountCodec.OP_RECOVERY_CODE:
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
			hasher.submit(login_form(pw).to_utf8_buffer(), str(me.password.salt).hex_decode(), int(me.password.iterations),
				{"op": op, "peer": peer, "t": t, "id": me.id, "new_password": str(r.get("new_password", "")),
				"uname": uname, "pk": pk})
		AccountCodec.OP_EXPORT:
			_reply(t, peer, op, AccountCodec.OK, {"json": export_json(me)})
		AccountCodec.OP_RECOVERY_INFO:
			_reply(t, peer, op, AccountCodec.OK, {"has_code": 1 if has_recovery_code(me) else 0})
		AccountCodec.OP_LAUNCH_TOKEN:
			_issue_launch_token(t, peer, me)
		AccountCodec.OP_PARTY:
			_reply(t, peer, op, AccountCodec.OK, party_fields(me))
		AccountCodec.OP_PARTY_INVITE:
			var to := str(r.id)
			if not (me.friends as Array).has(to) or (me.blocks as Array).has(to):
				_reply(t, peer, op, AccountCodec.E_NOT_FOUND)
				return
			var o := store.get_by_id(to)
			if o.is_empty() or (o.blocks as Array).has(me.id):
				_reply(t, peer, op, AccountCodec.E_NOT_FOUND)
				return
			if not _social_allow("invite", me.id):
				_reply(t, peer, op, AccountCodec.E_RATE)
				return
			var code := _party_code(parties.invite(me.id, to, _now))
			_reply(t, peer, op, code)
			if code == AccountCodec.OK and parties.member_of.get(to, "") != parties.member_of.get(me.id, "-"):
				notify(to, AccountCodec.N_PARTY_INVITE, me)
		AccountCodec.OP_PARTY_ACCEPT:
			var code := _party_code(parties.accept(me.id, str(r.id), _now))
			_reply(t, peer, op, code)
			if code == AccountCodec.OK:
				_notify_party(me.id, "joined", me, me.id)
		AccountCodec.OP_PARTY_DECLINE:
			_reply(t, peer, op, _party_code(parties.decline(me.id, str(r.id))))
		AccountCodec.OP_PARTY_LEAVE:
			var mates := parties.mates_of(me.id)
			parties.leave(me.id)
			_reply(t, peer, op, AccountCodec.OK)
			for m in mates:
				notify(str(m), AccountCodec.N_PARTY_CHANGED, me, "left")
		AccountCodec.OP_PARTY_PROMOTE:
			var code := _party_code(parties.promote(me.id, str(r.id)))
			_reply(t, peer, op, code)
			if code == AccountCodec.OK:
				_notify_party(me.id, "promoted", store.get_by_id(str(r.id)))
		AccountCodec.OP_PARTY_KICK:
			var kicked := str(r.id)
			var code := _party_code(parties.kick(me.id, kicked))
			_reply(t, peer, op, code)
			if code == AccountCodec.OK:
				notify(kicked, AccountCodec.N_KICKED, me)
				_notify_party(me.id, "kicked", store.get_by_id(kicked))
		AccountCodec.OP_PARTY_READY:
			var code := _party_code(parties.set_ready(me.id, int(r.ready) != 0))
			_reply(t, peer, op, code)
			if code == AccountCodec.OK:
				_notify_party(me.id, "ready" if int(r.ready) != 0 else "not_ready", me, me.id)
		AccountCodec.OP_PARTY_CHAT:
			_party_chat(t, peer, me, str(r.text))
		AccountCodec.OP_PARTY_JOIN_REQUEST:
			_join_request(t, peer, me, str(r.id))
		AccountCodec.OP_DM:
			_dm(t, peer, me, str(r.id), str(r.text))
		AccountCodec.OP_SET_AWAY:
			if int(r.away) != 0:
				away[me.id] = true
			else:
				away.erase(me.id)
			_reply(t, peer, op, AccountCodec.OK)
		AccountCodec.OP_NOTIFY:
			_reply(t, peer, op, AccountCodec.E_BAD_REQUEST)  # server push only
		AccountCodec.OP_FRIENDS:
			_reply(t, peer, op, AccountCodec.OK, {"friends": friends_list(me)})
		AccountCodec.OP_FRIEND_REQUEST:
			var by_id := str(r.id)
			var code := friend_request(me, str(r.username)) if LobbyCodec.is_none_id(by_id) \
				else friend_request_id(me, by_id)
			_reply(t, peer, op, code)
			if code == AccountCodec.OK:
				var o := store.find_username(str(r.username)) if LobbyCodec.is_none_id(by_id) else store.get_by_id(by_id)
				if not o.is_empty() and (o.requests_in as Array).has(me.id):  # never for a silent block drop
					notify(str(o.id), AccountCodec.N_FRIEND_REQUEST, me)
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
		AccountCodec.OP_LEADERBOARD:
			_leaderboard(t, peer, me, int(r.set))


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
		var keep_public := is_leaderboard_public(a)
		a.profile = {"display_name": who.name, "emblem": who.emblem, "accent": who.accent, "favourite_hero": hero}
		if keep_public:
			a.profile[PROFILE_LEADERBOARD] = true
		if not store.put(a):
			_reply(t, peer, op, AccountCodec.E_STORE)
			return
	_reply(t, peer, op, AccountCodec.OK, {"display_name": who.name, "emblem": who.emblem, "accent": who.accent,
		"favourite_hero": hero})


## W20-WEB: the public leaderboard opt-in (default off, PRIVACY.md). Only
## the stored value changes; LB_QUERY reads it. The flag lives in the
## account's profile, so deleting the account removes it with everything else.
func _leaderboard(t: Transport, peer: int, me: Dictionary, set_: int) -> void:
	var op := AccountCodec.OP_LEADERBOARD
	if set_ != AccountCodec.LB_QUERY:
		if set_ != AccountCodec.LB_OFF and set_ != AccountCodec.LB_ON:
			_reply(t, peer, op, AccountCodec.E_BAD_REQUEST)
			return
		set_leaderboard_public(me, set_ == AccountCodec.LB_ON)
		if not store.put(me):
			_reply(t, peer, op, AccountCodec.E_STORE)
			return
	_reply(t, peer, op, AccountCodec.OK, {"public": 1 if is_leaderboard_public(me) else 0})


## True when the account opted in to the public leaderboard (W20-WEB).
static func is_leaderboard_public(a: Dictionary) -> bool:
	var p: Variant = a.get("profile", {})
	return p is Dictionary and bool((p as Dictionary).get(PROFILE_LEADERBOARD, false))


## Sets or clears the opt-in on `a` (in memory; the caller stores it). Off
## removes the key, so an account that never opted in carries nothing.
static func set_leaderboard_public(a: Dictionary, on: bool) -> void:
	var p: Dictionary = a.get("profile", {})
	if on:
		p[PROFILE_LEADERBOARD] = true
	else:
		p.erase(PROFILE_LEADERBOARD)
	a["profile"] = p


## The account as readable JSON, without the password hash and salt and
## without the recovery code hash (only whether one exists, and since when).
static func export_json(a: Dictionary) -> String:
	var out := a.duplicate(true)
	var rec := recovery_of(a)
	out.password = {"algo": a.password.get("algo", ""), "iterations": a.password.get("iterations", 0),
		"recovery_code_set": not rec.is_empty(), "recovery_code_created_at": int(rec.get("created_at", 0)),
		"note": "the password hash and salt and the recovery code hash are not exported"}
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
			var friend: bool = pair[1] == AccountCodec.REL_FRIEND
			var st := status_of(o.id) if friend else LobbyCodec.STATUS_OFFLINE
			out.append({"id": o.id, "status": st, "mode": mode_of(o.id) if friend else 255, "relation": pair[1],
				"username": o.username,
				"display_name": str(p.get("display_name", o.username)), "emblem": int(p.get("emblem", 0)),
				"accent": int(p.get("accent", 0))})
	return out


## Presence of an account: in lobby / in match (PresenceRegistry), online
## (an attached session), else offline. Only shown to accepted friends.
func status_of(account_id: String) -> int:
	if presence_fn.is_valid():
		var pr: Dictionary = presence_fn.call(account_id)
		if not pr.is_empty():
			var s_ := int(pr.status)
			if s_ == LobbyCodec.STATUS_ONLINE and away.has(account_id):
				return LobbyCodec.STATUS_AWAY
			return s_
	var st := registry.status_of(account_id, PresenceRegistry.now_s())
	if st == LobbyCodec.STATUS_IN_LOBBY or st == LobbyCodec.STATUS_IN_MATCH:
		return st
	for p in peers:
		if peers[p].id == account_id:
			return LobbyCodec.STATUS_AWAY if away.has(account_id) else LobbyCodec.STATUS_ONLINE
	return LobbyCodec.STATUS_OFFLINE


## P2: the queue index a friend is in / playing (255 = none or unknown).
func mode_of(account_id: String) -> int:
	if presence_fn.is_valid():
		var pr: Dictionary = presence_fn.call(account_id)
		return int(pr.get("mode", 255))
	return 255


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


# --- party (W15) --------------------------------------------------------------

## OP_PARTY result: party id, leader, then one "P" entry per member, incoming
## invite and outgoing invite (display name, emblem, accent, presence).
func party_fields(me: Dictionary) -> Dictionary:
	var st := parties.state_of(me.id, _now)
	var list: Array = []
	for m in st.members:
		list.append(_party_entry(str(m), AccountCodec.PARTY_LEADER if m == st.leader else AccountCodec.PARTY_MEMBER))
	for m in st.invites_in:
		list.append(_party_entry(str(m), AccountCodec.PARTY_INVITE_IN))
	for m in st.invites_out:
		list.append(_party_entry(str(m), AccountCodec.PARTY_INVITE_OUT))
	return {"party": st.party, "leader": st.leader, "members": list.filter(func(e: Dictionary) -> bool: return not e.is_empty())}


func _party_entry(id: String, kind: int) -> Dictionary:
	var o := store.get_by_id(id) if store != null else {}
	if o.is_empty():
		return {}
	var p: Dictionary = o.profile
	return {"id": id, "kind": kind, "status": status_of(id), "display_name": str(p.get("display_name", o.username)),
		"emblem": int(p.get("emblem", 0)), "accent": int(p.get("accent", 0)),
		"flags": AccountCodec.PF_READY if parties.ready.has(id) else 0}


static func _party_code(c: int) -> int:
	match c:
		PartyService.OK:
			return AccountCodec.OK
		PartyService.E_FULL:
			return AccountCodec.E_LIMIT
		PartyService.E_NO_INVITE, PartyService.E_NOT_ALLOWED:
			return AccountCodec.E_NOT_FOUND
	return AccountCodec.E_BAD_REQUEST


# --- social (P2): chat, DMs, join requests, notifications ---------------------
# Chat text is never logged and never stored; it lives only in the packets.

## Pushes an OP_NOTIFY to `to` when online. `from` = the sender's account
## record ({} = the server). Returns true when sent.
func notify(to: String, kind: int, from: Dictionary, text: String = "") -> bool:
	if _push_t == null:
		return false
	var peer := _peer_of_account(to)
	if peer < 0:
		return false
	var name := ""
	if not from.is_empty():
		name = str((from.get("profile", {}) as Dictionary).get("display_name", from.get("username", "")))
	_reply(_push_t, peer, AccountCodec.OP_NOTIFY, AccountCodec.OK, {"kind": kind,
		"id": str(from.get("id", "")), "name": name, "text": text, "mode": 255})
	return true


func _notify_party(member: String, what: String, about: Dictionary, skip: String = "") -> void:
	var pid: String = parties.member_of.get(member, "")
	if pid == "":
		return
	for m in parties.parties[pid].members:
		if str(m) != skip:
			notify(str(m), AccountCodec.N_PARTY_CHANGED, about, what)


func _party_chat(t: Transport, peer: int, me: Dictionary, raw: String) -> void:
	var op := AccountCodec.OP_PARTY_CHAT
	var text := ChatFilter.sanitize(raw)
	var pid: String = parties.member_of.get(me.id, "")
	if pid == "" or text == "":
		_reply(t, peer, op, AccountCodec.E_NOT_FOUND if pid == "" else AccountCodec.E_BAD_REQUEST)
		return
	if not _social_allow("chat", me.id):
		_reply(t, peer, op, AccountCodec.E_RATE)
		return
	_reply(t, peer, op, AccountCodec.OK)
	for m in parties.parties[pid].members:
		var o := store.get_by_id(str(m))
		if not o.is_empty() and not (o.blocks as Array).has(me.id):  # a block hides chat too
			notify(str(m), AccountCodec.N_PARTY_CHAT, me, text)


func _dm(t: Transport, peer: int, me: Dictionary, to: String, raw: String) -> void:
	var op := AccountCodec.OP_DM
	var text := ChatFilter.sanitize(raw)
	var o := store.get_by_id(to)
	if o.is_empty() or not (me.friends as Array).has(to) or (me.blocks as Array).has(to) \
			or (o.blocks as Array).has(me.id):
		_reply(t, peer, op, AccountCodec.E_NOT_FOUND)
		return
	if text == "":
		_reply(t, peer, op, AccountCodec.E_BAD_REQUEST)
		return
	if not _social_allow("chat", me.id):
		_reply(t, peer, op, AccountCodec.E_RATE)
		return
	# Online only: messages are never stored (PRIVACY.md "Chat").
	_reply(t, peer, op, AccountCodec.OK if notify(to, AccountCodec.N_DM, me, text) else AccountCodec.E_NOT_FOUND)


## Ask friend `to`'s party (its leader, or the friend when alone) for an invite.
func _join_request(t: Transport, peer: int, me: Dictionary, to: String) -> void:
	var op := AccountCodec.OP_PARTY_JOIN_REQUEST
	var o := store.get_by_id(to)
	if o.is_empty() or not (me.friends as Array).has(to) or (me.blocks as Array).has(to) \
			or (o.blocks as Array).has(me.id):
		_reply(t, peer, op, AccountCodec.E_NOT_FOUND)
		return
	if not _social_allow("invite", me.id):
		_reply(t, peer, op, AccountCodec.E_RATE)
		return
	var target := to
	var ps := parties.state_of(to, _now)
	if str(ps.party) != "":
		target = str(ps.leader)
		var lead := store.get_by_id(target)
		if lead.is_empty() or (lead.blocks as Array).has(me.id):
			_reply(t, peer, op, AccountCodec.E_NOT_FOUND)
			return
	_reply(t, peer, op, AccountCodec.OK if notify(target, AccountCodec.N_JOIN_REQUEST, me) else AccountCodec.E_NOT_FOUND)


## Token bucket per account and kind ("chat" / "invite").
func _social_allow(kind: String, account_id: String) -> bool:
	var burst := float(online.chat_burst if kind == "chat" else online.invite_burst)
	var refill := online.chat_refill_s if kind == "chat" else online.invite_refill_s
	var k := kind + ":" + account_id
	var b: Array = _social_rl.get(k, [burst, _now])
	var tokens := minf(burst, float(b[0]) + (_now - float(b[1])) / refill)
	if tokens < 1.0:
		_social_rl[k] = [tokens, _now]
		return false
	_social_rl[k] = [tokens - 1.0, _now]
	if _social_rl.size() > 8192:
		_social_rl.clear()
	return true


func _peer_of_account(account_id: String) -> int:
	for p in peers:
		if str(peers[p].get("id", "")) == account_id:
			return int(p)
	return -1


func _has_session(account_id: String) -> bool:
	for tok in sessions:
		if sessions[tok].identity.id == account_id:
			return true
	return false


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
	out.erase("code")
	out.erase("password")
	out.erase("old_password")
	out.erase("new_password")
	return out


# --- recovery code (W21-N1) ----------------------------------------------------

## The recovery code record of account `a` ({algo, hash, salt, iterations,
## created_at}) or {} when it has none (accounts from before v0.16, or a used code).
static func recovery_of(a: Dictionary) -> Dictionary:
	var pw: Variant = a.get("password", {})
	if not (pw is Dictionary):
		return {}
	var rec: Variant = (pw as Dictionary).get(RECOVERY_KEY, {})
	return rec if rec is Dictionary and str((rec as Dictionary).get("hash", "")) != "" else {}


static func has_recovery_code(a: Dictionary) -> bool:
	return not recovery_of(a).is_empty()


## Applies every waiting host reset request (AccountAdmin) and answers it.
## Called from step() every AuthRulesDef.admin_poll_s.
func poll_admin() -> void:
	for item in AccountAdmin.take_requests(admin_dir):
		AccountAdmin.write_result(admin_dir, str(item.id), apply_admin_reset(item.request))


## One host reset: the old password stops working, the request's recovery
## code (hash only) replaces any old one, every session of the account ends
## and its launch tokens are revoked. Returns {ok, error, tag}.
func apply_admin_reset(req: Dictionary) -> Dictionary:
	if not AccountAdmin.is_valid_reset(req):
		print("[accounts] admin request refused: malformed")
		return {"ok": false, "error": "malformed request"}
	var a := store.find_username(str(req.username))
	if a.is_empty():
		print("[accounts] admin reset: no such account")
		return {"ok": false, "error": "no such account"}
	var rec: Dictionary = req.recovery
	var pw: Dictionary = a.password
	pw["hash"] = ""  # no password matches an empty hash: the player sets a new one with the code
	pw[RECOVERY_KEY] = {"algo": "pbkdf2-hmac-sha256", "hash": str(rec.hash).to_lower(), "salt": str(rec.salt).to_lower(),
		"iterations": int(rec.iterations), "created_at": int(rec.get("created_at", 0))}
	a.password = pw
	if not store.put(a):
		print("[accounts] admin reset: account #%s could not be saved" % PlayerProfile.tag_of(a.id))
		return {"ok": false, "error": "could not save the account"}
	end_other_sessions(a.id, -2)
	launch_tokens.revoke_account(a.id)
	print("[accounts] admin reset: account #%s (password cleared, new recovery code, sessions ended)" %
		PlayerProfile.tag_of(a.id))
	return {"ok": true, "error": "", "tag": PlayerProfile.tag_of(a.id)}
