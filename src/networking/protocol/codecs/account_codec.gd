class_name AccountCodec
extends RefCounted
## Account messages (protocol v12, design/ux/lobby-and-social.md §6):
## ACCOUNT_REQ (C->S) = u8 op + fields; ACCOUNT_RESULT (S->C) = u8 op, u8 code
## + fields (only when code == OK). The fields of each op are fixed by SCHEMA
## below; decoding is strict (exact field list, bounded sizes, no trailing
## bytes) and returns {} on any mismatch. Reliable, ch0, on request only.
## Field types: u = u16, b = u8, s = str8 (<= 64 B), p = password str8
## (<= 128 B), i = player id (16 B), t = session token (32 B), L = str16 JSON
## (<= 60000 B), F = friends list, C = u16 length + raw bytes (<= CHUNK_MAX),
## P = party list (v15).
## Passwords only travel on a DTLS link (the server refuses them otherwise).

const OP_REGISTER: int = 1
const OP_LOGIN: int = 2
const OP_RESUME: int = 3
const OP_GUEST: int = 4
const OP_LOGOUT: int = 5
const OP_CHANGE_PASSWORD: int = 6
const OP_UPDATE_PROFILE: int = 7
const OP_DELETE_ACCOUNT: int = 8
const OP_EXPORT: int = 9
const OP_FRIEND_REQUEST: int = 10
const OP_FRIEND_ACCEPT: int = 11
const OP_FRIEND_DECLINE: int = 12
const OP_FRIEND_REMOVE: int = 13
const OP_BLOCK: int = 14
const OP_UNBLOCK: int = 15
const OP_FRIENDS: int = 16
## v15: launcher sign-in hand-over (single-use launch token, DTLS only).
const OP_LAUNCH_TOKEN: int = 17   ## logged in: ask for a launch token for the game
const OP_REDEEM: int = 18         ## the game: trade the launch token for its own session
## v15: opt-in crash report, sent in chunks (DTLS only, any session or none).
const OP_CRASH_CHUNK: int = 19
## v15: party (leader + members, friends only; memory only on the server).
const OP_PARTY: int = 20          ## own party state + invites
const OP_PARTY_INVITE: int = 21   ## invite a friend (by id)
const OP_PARTY_ACCEPT: int = 22   ## accept the invite of `id` (the inviter)
const OP_PARTY_DECLINE: int = 23  ## decline the invite of `id`
const OP_PARTY_LEAVE: int = 24    ## leave the party (a leader hands over)
## v15: RTT probe for the launcher's status widget (no fields, any session or none).
const OP_PING: int = 25
## v18 (W20-WEB): public leaderboard opt-in (accounts only, DTLS). Request
## `set`: LB_OFF / LB_ON change the flag, LB_QUERY only reads it. The result
## carries the stored value (`public` 0/1).
const OP_LEADERBOARD: int = 26
const LB_OFF: int = 0
const LB_ON: int = 1
const LB_QUERY: int = 2
## v19 (W21-N1): password recovery without e-mail (PRIVACY.md). The server
## issues a one-time recovery code at REGISTER (result field
## `recovery_code`, shown once). RECOVER (no session, DTLS only, rate-limited
## like LOGIN, the same E_CREDENTIALS for an unknown user or a wrong code):
## username + code + new password; on success the code is used up, a new
## one comes back with a fresh session and every other session ends.
## RECOVERY_CODE (logged in): the current password; returns a new code (the
## old one stops working). RECOVERY_INFO (logged in): whether a code exists.
const OP_RECOVER: int = 27
const OP_RECOVERY_CODE: int = 28
const OP_RECOVERY_INFO: int = 29
## v20 (P2) social: party leadership / kick / ready / chat, join requests,
## direct messages, away, and OP_NOTIFY: a server push (never sent by clients)
## carrying chat lines and social notifications (kind N_*).
const OP_PARTY_PROMOTE: int = 30
const OP_PARTY_KICK: int = 31
const OP_PARTY_READY: int = 32
const OP_PARTY_CHAT: int = 33
const OP_PARTY_JOIN_REQUEST: int = 34   ## ask the party of friend `id` to invite me
const OP_DM: int = 35                   ## direct message to friend `id` (online only, never stored)
const OP_SET_AWAY: int = 36
const OP_NOTIFY: int = 37

## Request fields per op.
const REQ_SCHEMA := {
	OP_REGISTER: [["ver", "u"], ["username", "s"], ["password", "p"], ["display_name", "s"], ["emblem", "b"],
		["accent", "b"], ["flags", "b"]],
	OP_LOGIN: [["ver", "u"], ["username", "s"], ["password", "p"]],
	OP_RESUME: [["ver", "u"], ["token", "t"]],
	OP_GUEST: [["ver", "u"], ["display_name", "s"], ["emblem", "b"], ["accent", "b"], ["flags", "b"]],
	OP_LOGOUT: [],
	OP_CHANGE_PASSWORD: [["old_password", "p"], ["new_password", "p"]],
	OP_UPDATE_PROFILE: [["display_name", "s"], ["emblem", "b"], ["accent", "b"], ["favourite_hero", "s"]],
	OP_DELETE_ACCOUNT: [["password", "p"]],
	OP_EXPORT: [],
	OP_FRIEND_REQUEST: [["username", "s"], ["id", "i"]],  # by username, or by id (lobby row) when set
	OP_FRIEND_ACCEPT: [["id", "i"]],
	OP_FRIEND_DECLINE: [["id", "i"]],
	OP_FRIEND_REMOVE: [["id", "i"]],
	OP_BLOCK: [["id", "i"]],
	OP_UNBLOCK: [["id", "i"]],
	OP_FRIENDS: [],
	OP_LAUNCH_TOKEN: [],
	OP_REDEEM: [["ver", "u"], ["token", "t"], ["id", "i"]],
	OP_CRASH_CHUNK: [["seq", "u"], ["total", "u"], ["data", "C"]],
	OP_PARTY: [],
	OP_PARTY_INVITE: [["id", "i"]],
	OP_PARTY_ACCEPT: [["id", "i"]],
	OP_PARTY_DECLINE: [["id", "i"]],
	OP_PARTY_LEAVE: [],
	OP_PING: [],
	OP_LEADERBOARD: [["set", "b"]],
	OP_RECOVER: [["ver", "u"], ["username", "s"], ["code", "s"], ["new_password", "p"]],
	OP_RECOVERY_CODE: [["password", "p"]],
	OP_RECOVERY_INFO: [],
	OP_PARTY_PROMOTE: [["id", "i"]],
	OP_PARTY_KICK: [["id", "i"]],
	OP_PARTY_READY: [["ready", "b"]],
	OP_PARTY_CHAT: [["text", "m"]],
	OP_PARTY_JOIN_REQUEST: [["id", "i"]],
	OP_DM: [["id", "i"], ["text", "m"]],
	OP_SET_AWAY: [["away", "b"]],
	OP_NOTIFY: [],
}
const SESSION_FIELDS := [["token", "t"], ["id", "i"], ["username", "s"], ["display_name", "s"], ["emblem", "b"],
	["accent", "b"], ["favourite_hero", "s"], ["guest", "b"]]
## v19: a session that also hands out a new recovery code (shown once).
const SESSION_CODE_FIELDS := [["token", "t"], ["id", "i"], ["username", "s"], ["display_name", "s"],
	["emblem", "b"], ["accent", "b"], ["favourite_hero", "s"], ["guest", "b"], ["recovery_code", "s"]]
## OK-result fields per op (ops not listed carry none).
const RES_SCHEMA := {
	OP_REGISTER: SESSION_CODE_FIELDS,
	OP_LOGIN: SESSION_FIELDS,
	OP_RESUME: SESSION_FIELDS,
	OP_GUEST: SESSION_FIELDS,
	OP_UPDATE_PROFILE: [["display_name", "s"], ["emblem", "b"], ["accent", "b"], ["favourite_hero", "s"]],
	OP_EXPORT: [["json", "L"]],
	OP_FRIENDS: [["friends", "F"]],
	OP_LAUNCH_TOKEN: [["token", "t"], ["ttl", "u"]],
	OP_REDEEM: SESSION_FIELDS,
	OP_CRASH_CHUNK: [["seq", "u"]],
	OP_PARTY: [["party", "i"], ["leader", "i"], ["members", "P"]],
	OP_LEADERBOARD: [["public", "b"]],
	OP_RECOVER: SESSION_CODE_FIELDS,
	OP_RECOVERY_CODE: [["recovery_code", "s"]],
	OP_RECOVERY_INFO: [["has_code", "b"]],
	## kind N_*, sender id (zeros = the server), sender display name, chat text
	## or detail, queue index for presence notes (255 = none).
	OP_NOTIFY: [["kind", "b"], ["id", "i"], ["name", "s"], ["text", "m"], ["mode", "b"]],
}

## OP_NOTIFY kinds (v20, P2).
const N_PARTY_CHAT: int = 1
const N_DM: int = 2
const N_PARTY_INVITE: int = 3     ## `id` invited you to their party
const N_FRIEND_REQUEST: int = 4   ## `id` sent you a friend request
const N_JOIN_REQUEST: int = 5     ## `id` asks your party for an invite (leader only)
const N_PARTY_CHANGED: int = 6    ## your party changed (text: joined / left / kicked / promoted); refresh OP_PARTY
const N_KICKED: int = 7           ## the leader removed you from the party
## Party entry flags (v20).
const PF_READY: int = 1
## Chat / DM text limit in bytes (UTF-8).
const CHAT_MAX: int = 240

## REGISTER / GUEST flags.
const FLAG_PRIVACY: int = 1  ## accepted the privacy notice (PRIVACY.md)
const FLAG_AGE: int = 2      ## confirmed the minimum age (AuthRulesDef.min_age)

## Result codes.
const OK: int = 0
const E_BAD_REQUEST: int = 1
const E_NOT_SECURE: int = 2      ## accounts need a DTLS link; this server / link has none
const E_CREDENTIALS: int = 3
const E_LOCKED: int = 4          ## too many failed logins; try later
const E_NAME_TAKEN: int = 5
const E_BAD_USERNAME: int = 6
const E_WEAK_PASSWORD: int = 7
const E_BAD_NAME: int = 8
const E_CONSENT: int = 9
const E_AGE: int = 10
const E_NOT_LOGGED_IN: int = 11
const E_NOT_FOUND: int = 12
const E_LIMIT: int = 13
const E_VERSION: int = 14
const E_BUSY: int = 15
const E_SESSION: int = 16
const E_STORE: int = 17
const E_GUEST: int = 18          ## not available to guests
const E_GUESTS_OFF: int = 19     ## this server needs an account (no guests)
const E_RATE: int = 20           ## v15: too many reports / requests from this address or account
const CODE_COUNT: int = 21

## Friend relations in the FRIENDS list.
const REL_FRIEND: int = 0
const REL_INCOMING: int = 1
const REL_OUTGOING: int = 2
const REL_BLOCKED: int = 3

## Party list entry kinds (v15).
const PARTY_LEADER: int = 0
const PARTY_MEMBER: int = 1
const PARTY_INVITE_IN: int = 2   ## someone invited me (id = the inviter)
const PARTY_INVITE_OUT: int = 3  ## I (or my party) invited this friend

const STR_MAX: int = 64
const PASSWORD_MAX_BYTES: int = 128
const JSON_MAX: int = 60000
const TOKEN_BYTES: int = 32
const MAX_LIST: int = 255
## Largest raw chunk in a "C" field (keeps a request under LobbyCodec.MAX_C2S_BYTES).
const CHUNK_MAX: int = 1024


static func encode_request(op: int, fields: Dictionary) -> PackedByteArray:
	var w := LobbyCodec.Writer.new(MsgType.ACCOUNT_REQ)
	w.u8(op)
	_write(w, REQ_SCHEMA.get(op, []), fields)
	return w.b


## {op, ...fields} or {} when malformed / unknown op.
static func decode_request(b: PackedByteArray) -> Dictionary:
	if b.size() < 2 or b.size() > LobbyCodec.MAX_C2S_BYTES or b.decode_u8(0) != MsgType.ACCOUNT_REQ:
		return {}
	var op := b.decode_u8(1)
	if not REQ_SCHEMA.has(op):
		return {}
	var r := LobbyCodec.Reader.new(b)
	r.pos = 2
	var d := _read(r, REQ_SCHEMA[op])
	if d.is_empty() and not (REQ_SCHEMA[op] as Array).is_empty():
		return {}
	if not r.done():
		return {}
	d["op"] = op
	return d


static func encode_result(op: int, code: int, fields: Dictionary = {}) -> PackedByteArray:
	var w := LobbyCodec.Writer.new(MsgType.ACCOUNT_RESULT)
	w.u8(op)
	w.u8(code)
	if code == OK:
		_write(w, RES_SCHEMA.get(op, []), fields)
	return w.b


## {op, code, ...fields} or {}.
static func decode_result(b: PackedByteArray) -> Dictionary:
	if b.size() < 3 or b.decode_u8(0) != MsgType.ACCOUNT_RESULT:
		return {}
	var op := b.decode_u8(1)
	var code := b.decode_u8(2)
	if not REQ_SCHEMA.has(op) or code >= CODE_COUNT:
		return {}
	var r := LobbyCodec.Reader.new(b)
	r.pos = 3
	var d := {}
	if code == OK and RES_SCHEMA.has(op):
		d = _read(r, RES_SCHEMA[op])
		if d.is_empty():
			return {}
	if not r.done():
		return {}
	d["op"] = op
	d["code"] = code
	return d


static func _write(w: LobbyCodec.Writer, schema: Array, f: Dictionary) -> void:
	for field in schema:
		var v: Variant = f.get(field[0])
		match field[1]:
			"u":
				w.u16(int(v) if v != null else 0)
			"b":
				w.u8(int(v) if v != null else 0)
			"s":
				w.str8(str(v) if v != null else "", STR_MAX)
			"m":
				w.str8(str(v) if v != null else "", CHAT_MAX)
			"p":
				w.str8(str(v) if v != null else "", PASSWORD_MAX_BYTES)
			"i":
				w.id(str(v) if v != null else "")
			"t":
				var raw := str(v).hex_decode() if v != null else PackedByteArray()
				if raw.size() != TOKEN_BYTES:
					raw = PackedByteArray()
					raw.resize(TOKEN_BYTES)
				w.b.append_array(raw)
			"L":
				var raw := (str(v) if v != null else "").to_utf8_buffer()
				if raw.size() > JSON_MAX:
					raw = PackedByteArray()
				w.u16(raw.size())
				w.b.append_array(raw)
			"C":
				var raw: PackedByteArray = v if v is PackedByteArray else PackedByteArray()
				if raw.size() > CHUNK_MAX:
					raw = raw.slice(0, CHUNK_MAX)
				w.u16(raw.size())
				w.b.append_array(raw)
			"P":
				var l: Array = v if v is Array else []
				var n := mini(l.size(), MAX_LIST)
				w.u8(n)
				for k in n:
					var e: Dictionary = l[k]
					w.id(str(e.get("id", "")))
					w.u8(int(e.get("kind", 0)))
					w.u8(int(e.get("status", 0)))
					w.str8(str(e.get("display_name", "")), STR_MAX)
					w.u8(int(e.get("emblem", 0)))
					w.u8(int(e.get("accent", 0)))
					w.u8(int(e.get("flags", 0)))
			"F":
				var l: Array = v if v is Array else []
				var n := mini(l.size(), MAX_LIST)
				w.u8(n)
				for k in n:
					var e: Dictionary = l[k]
					w.id(str(e.get("id", "")))
					w.u8(int(e.get("status", 0)))
					w.u8(int(e.get("mode", 255)))
					w.u8(int(e.get("relation", 0)))
					w.str8(str(e.get("username", "")), STR_MAX)
					w.str8(str(e.get("display_name", "")), STR_MAX)
					w.u8(int(e.get("emblem", 0)))
					w.u8(int(e.get("accent", 0)))


## Reads `schema`; {} on failure (check r.ok).
static func _read(r: LobbyCodec.Reader, schema: Array) -> Dictionary:
	var d := {}
	for field in schema:
		match field[1]:
			"u":
				d[field[0]] = r.u16()
			"b":
				d[field[0]] = r.u8()
			"s":
				d[field[0]] = r.str8(STR_MAX)
			"m":
				d[field[0]] = r.str8(CHAT_MAX)
			"p":
				d[field[0]] = r.str8(PASSWORD_MAX_BYTES)
			"i":
				d[field[0]] = r.id()
			"t":
				if not r._need(TOKEN_BYTES):
					return {}
				r.pos += TOKEN_BYTES
				d[field[0]] = r.b.slice(r.pos - TOKEN_BYTES, r.pos).hex_encode()
			"L":
				var n := r.u16()
				if not r.ok or n > JSON_MAX or not r._need(n):
					return {}
				r.pos += n
				var raw := r.b.slice(r.pos - n, r.pos)
				if not LobbyCodec.is_valid_utf8(raw):
					return {}
				d[field[0]] = raw.get_string_from_utf8()
			"C":
				var n := r.u16()
				if not r.ok or n > CHUNK_MAX or not r._need(n):
					return {}
				r.pos += n
				d[field[0]] = r.b.slice(r.pos - n, r.pos)
			"P":
				var n := r.u8()
				var l: Array = []
				for k in n:
					l.append({"id": r.id(), "kind": r.u8(), "status": r.u8(), "display_name": r.str8(STR_MAX),
						"emblem": r.u8(), "accent": r.u8(), "flags": r.u8()})
				d[field[0]] = l
			"F":
				var n := r.u8()
				var l: Array = []
				for k in n:
					l.append({"id": r.id(), "status": r.u8(), "mode": r.u8(), "relation": r.u8(), "username": r.str8(STR_MAX),
						"display_name": r.str8(STR_MAX), "emblem": r.u8(), "accent": r.u8()})
				d[field[0]] = l
		if not r.ok:
			return {}
	return d
