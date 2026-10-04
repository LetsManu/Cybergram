class_name LobbyCodec
extends RefCounted
## Lobby, chat, presence and player-name messages (MsgType.LOBBY_* /
## PRESENCE* / PLAYER_NAMES), all on the reliable control channel.
## Decoders are strict: wrong type byte, wrong length, out-of-range counts or
## trailing bytes return {} (the server counts that as a violation). Strings
## travel as str8 (u8 byte length + UTF-8); ids as 16 raw bytes (hex in
## memory, see PlayerProfile). Field *values* (names, chat text) are validated
## by the server, not here.
##
## Replication: every message is reliable + ordered (ch0). LOBBY_STATE is sent
## on every change and at least once per second; PRESENCE answers a query;
## PLAYER_NAMES is sent when a named player joins or leaves the match.
## Budget: LOBBY_STATE <= 6 + 16 x 39 bytes; PRESENCE_QUERY <= MAX_C2S_BYTES.

const PHASE_WAITING: int = 0   ## players join, pick heroes, toggle Ready, switch teams
const PHASE_COUNTDOWN: int = 1 ## everyone is ready; un-readying cancels
const PHASE_IN_MATCH: int = 2  ## a match is running (late joiners take over a bot)
const PHASE_LOCKED: int = 3    ## the final seconds of the countdown: picks are final
const MAX_PLAYERS: int = 16
## Largest client->server lobby packet the server accepts.
const MAX_C2S_BYTES: int = 1200
## Chat limits (characters after sanitising, and raw bytes on the wire).
const CHAT_MAX_CHARS: int = 120
const CHAT_MAX_BYTES: int = 240
## Presence query limits.
const MAX_PRESENCE_IDS: int = 40
const MAX_PRESENCE_NAMES: int = 10
const MAX_PRESENCE_REPLY: int = 64
## Name bytes on the wire (names are ASCII, PlayerProfile.NAME_MAX chars).
const NAME_MAX_BYTES: int = 16
const ID_BYTES: int = 16
## No slot / no team on the wire.
const NONE_U8: int = 255

## Slot flags (LOBBY_STATE).
const FLAG_READY: int = 1
const FLAG_CONNECTED: int = 2

## Chat kinds.
const CHAT_PLAYER: int = 0
const CHAT_SYSTEM: int = 1
## System chat codes (composed client-side with tr(), name = the subject).
const SYS_JOINED: int = 1
const SYS_LEFT: int = 2
const SYS_RECONNECTING: int = 3
const SYS_RECONNECTED: int = 4
const SYS_SWITCHED: int = 5
const SYS_LOCKED_IN: int = 6
const SYS_SLOW_DOWN: int = 7
const SYS_TEAM_FULL: int = 8
const SYS_COUNT: int = 9

## Presence status values.
const STATUS_OFFLINE: int = 0
const STATUS_ONLINE: int = 1
const STATUS_IN_LOBBY: int = 2
const STATUS_IN_MATCH: int = 3


## Bounds-checked little-endian reader; `ok` turns false on any overrun.
class Reader:
	extends RefCounted
	var b: PackedByteArray
	var pos: int = 1
	var ok: bool = true

	func _init(bytes: PackedByteArray) -> void:
		b = bytes

	func _need(n: int) -> bool:
		if not ok or pos + n > b.size():
			ok = false
			return false
		return true

	func u8() -> int:
		if not _need(1):
			return 0
		pos += 1
		return b.decode_u8(pos - 1)

	func u16() -> int:
		if not _need(2):
			return 0
		pos += 2
		return b.decode_u16(pos - 2)

	## 16 raw bytes as lower-case hex.
	func id() -> String:
		if not _need(ID_BYTES):
			return ""
		pos += ID_BYTES
		return b.slice(pos - ID_BYTES, pos).hex_encode()

	## str8, at most `max_bytes` bytes; invalid UTF-8 fails the read.
	func str8(max_bytes: int) -> String:
		var n := u8()
		if not ok or n > max_bytes or not _need(n):
			ok = false
			return ""
		pos += n
		var raw := b.slice(pos - n, pos)
		if not LobbyCodec.is_valid_utf8(raw):
			ok = false  # not valid UTF-8 (or contains NUL)
			return ""
		return raw.get_string_from_utf8()

	## True when everything was read and nothing trails.
	func done() -> bool:
		return ok and pos == b.size()


## Little-endian writer.
class Writer:
	extends RefCounted
	var b := PackedByteArray()

	func _init(type: int) -> void:
		u8(type)

	func u8(v: int) -> void:
		b.append(v & 0xFF)

	func u16(v: int) -> void:
		b.append(v & 0xFF)
		b.append((v >> 8) & 0xFF)

	## 32-char hex id as 16 bytes ("" or invalid = zeros).
	func id(hex: String) -> void:
		var raw := hex.hex_decode() if hex.length() == ID_BYTES * 2 else PackedByteArray()
		if raw.size() != ID_BYTES:
			raw = PackedByteArray()
			raw.resize(ID_BYTES)
		b.append_array(raw)

	## str8, truncated to `max_bytes` on a character boundary.
	func str8(s: String, max_bytes: int) -> void:
		var raw := s.to_utf8_buffer()
		while raw.size() > mini(max_bytes, 255):
			s = s.substr(0, s.length() - 1)
			raw = s.to_utf8_buffer()
		u8(raw.size())
		b.append_array(raw)


## Strict UTF-8 check without engine error output: no NUL, no overlong
## forms, no surrogates, nothing above U+10FFFF.
static func is_valid_utf8(raw: PackedByteArray) -> bool:
	var i := 0
	var n := raw.size()
	while i < n:
		var c := raw[i]
		var extra := 0
		var cp := 0
		if c == 0:
			return false
		elif c < 0x80:
			i += 1
			continue
		elif c >= 0xC2 and c <= 0xDF:
			extra = 1
			cp = c & 0x1F
		elif c >= 0xE0 and c <= 0xEF:
			extra = 2
			cp = c & 0x0F
		elif c >= 0xF0 and c <= 0xF4:
			extra = 3
			cp = c & 0x07
		else:
			return false
		if i + extra >= n:
			return false
		for k in extra:
			var cc := raw[i + 1 + k]
			if (cc & 0xC0) != 0x80:
				return false
			cp = (cp << 6) | (cc & 0x3F)
		if (extra == 2 and (cp < 0x800 or (cp >= 0xD800 and cp <= 0xDFFF))) \
				or (extra == 3 and (cp < 0x10000 or cp > 0x10FFFF)):
			return false
		i += 1 + extra
	return true


## The all-zero id means "none" (e.g. no party friend).
static func is_none_id(hex: String) -> bool:
	return hex == "" or hex == "0".repeat(ID_BYTES * 2)


# --- LOBBY_JOIN -------------------------------------------------------------

## `profile`: {id, key, name, emblem, accent}. `party_id`: friend to sit with ("" = none).
static func encode_join(protocol_version: int, profile: Dictionary, hero_index: int,
		party_id: String = "") -> PackedByteArray:
	var w := Writer.new(MsgType.LOBBY_JOIN)
	w.u16(protocol_version)
	w.id(str(profile.get("id", "")))
	w.id(str(profile.get("key", "")))
	w.str8(str(profile.get("name", "")), NAME_MAX_BYTES)
	w.u8(int(profile.get("emblem", 0)))
	w.u8(int(profile.get("accent", 0)))
	w.u16(hero_index)
	w.id(party_id)
	return w.b


## {protocol_version, id, key, name, emblem, accent, hero_index, party_id}.
## A pre-v11 join (5 bytes) decodes to {protocol_version} only, so the server
## can answer with a clean protocol-mismatch Reject.
static func decode_join(b: PackedByteArray) -> Dictionary:
	if b.size() < 3 or b.decode_u8(0) != MsgType.LOBBY_JOIN:
		return {}
	if b.size() == 5:
		return {"protocol_version": b.decode_u16(1), "legacy": true}
	var r := Reader.new(b)
	var d := {"protocol_version": r.u16(), "id": r.id(), "key": r.id(),
		"name": r.str8(NAME_MAX_BYTES), "emblem": r.u8(), "accent": r.u8(), "hero_index": r.u16(),
		"party_id": r.id()}
	if not r.done():
		return {}
	if is_none_id(d.party_id):
		d.party_id = ""
	return d


# --- LOBBY_PICK -------------------------------------------------------------

static func encode_pick(hero_index: int, ready: bool) -> PackedByteArray:
	var w := Writer.new(MsgType.LOBBY_PICK)
	w.u16(hero_index)
	w.u8(1 if ready else 0)
	return w.b


static func decode_pick(b: PackedByteArray) -> Dictionary:
	if b.size() != 4 or b.decode_u8(0) != MsgType.LOBBY_PICK:
		return {}
	var ready := b.decode_u8(3)
	if ready > 1:
		return {}
	return {"hero_index": b.decode_u16(1), "ready": ready != 0}


# --- LOBBY_TEAM -------------------------------------------------------------

static func encode_team(team: int) -> PackedByteArray:
	var w := Writer.new(MsgType.LOBBY_TEAM)
	w.u8(team)
	return w.b


static func decode_team(b: PackedByteArray) -> Dictionary:
	if b.size() != 2 or b.decode_u8(0) != MsgType.LOBBY_TEAM or b.decode_u8(1) > 1:
		return {}
	return {"team": b.decode_u8(1)}


# --- LOBBY_STATE ------------------------------------------------------------

## `slots`: Array of {team, hero_index, ready, connected, emblem, accent, id, name}.
## `you`: index of the receiver (NONE_U8 = not seated).
static func encode_state(phase: int, countdown_s: int, you: int, slots: Array, team_size: int = 3) -> PackedByteArray:
	var n := mini(slots.size(), MAX_PLAYERS)
	var w := Writer.new(MsgType.LOBBY_STATE)
	w.u8(phase)
	w.u8(clampi(countdown_s, 0, 255))
	w.u8(clampi(you, 0, 255))
	w.u8(clampi(team_size, 1, MAX_PLAYERS / 2))
	w.u8(n)
	for i in n:
		var s: Dictionary = slots[i]
		w.u8(int(s.get("team", 0)))
		w.u16(int(s.get("hero_index", 0)))
		w.u8((FLAG_READY if s.get("ready", false) else 0) | (FLAG_CONNECTED if s.get("connected", true) else 0))
		w.u8(int(s.get("emblem", 0)))
		w.u8(int(s.get("accent", 0)))
		w.id(str(s.get("id", "")))
		w.str8(str(s.get("name", "")), NAME_MAX_BYTES)
	return w.b


static func decode_state(b: PackedByteArray) -> Dictionary:
	if b.size() < 6 or b.decode_u8(0) != MsgType.LOBBY_STATE:
		return {}
	var r := Reader.new(b)
	var d := {"phase": r.u8(), "countdown": r.u8(), "you": r.u8(), "team_size": r.u8()}
	var n := r.u8()
	if n > MAX_PLAYERS or d.phase > PHASE_LOCKED:
		return {}
	var slots: Array = []
	for i in n:
		var team := r.u8()
		var hero := r.u16()
		var flags := r.u8()
		slots.append({"team": team, "hero_index": hero, "ready": (flags & FLAG_READY) != 0,
			"connected": (flags & FLAG_CONNECTED) != 0, "emblem": r.u8(), "accent": r.u8(),
			"id": r.id(), "name": r.str8(NAME_MAX_BYTES)})
		if team > 1:
			return {}
	if not r.done():
		return {}
	d["slots"] = slots
	return d


# --- LOBBY_START ------------------------------------------------------------

static func encode_start(token: int, team: int, hero_index: int) -> PackedByteArray:
	var w := Writer.new(MsgType.LOBBY_START)
	w.u16(token)
	w.u8(team)
	w.u16(hero_index)
	return w.b


static func decode_start(b: PackedByteArray) -> Dictionary:
	if b.size() != 6 or b.decode_u8(0) != MsgType.LOBBY_START:
		return {}
	return {"token": b.decode_u16(1), "team": b.decode_u8(3), "hero_index": b.decode_u16(4)}


# --- Chat -------------------------------------------------------------------

static func encode_chat_send(text: String) -> PackedByteArray:
	var w := Writer.new(MsgType.LOBBY_CHAT_SEND)
	w.str8(text, CHAT_MAX_BYTES)
	return w.b


## {text} (raw; the server sanitises it). Oversized text = {}.
static func decode_chat_send(b: PackedByteArray) -> Dictionary:
	if b.size() < 2 or b.decode_u8(0) != MsgType.LOBBY_CHAT_SEND:
		return {}
	var r := Reader.new(b)
	var t := r.str8(CHAT_MAX_BYTES)
	if not r.done():
		return {}
	return {"text": t}


## One chat line. System lines carry `code` (SYS_*) and the subject's name.
## `id`: the sender / subject's player id (lets clients mute by id).
static func encode_chat(kind: int, code: int, team: int, accent: int, name: String, text: String,
		id: String = "") -> PackedByteArray:
	var w := Writer.new(MsgType.LOBBY_CHAT)
	w.u8(kind)
	w.u8(code)
	w.u8(team)
	w.u8(accent)
	w.id(id)
	w.str8(name, NAME_MAX_BYTES)
	w.str8(text, CHAT_MAX_BYTES)
	return w.b


static func decode_chat(b: PackedByteArray) -> Dictionary:
	if b.size() < 23 or b.decode_u8(0) != MsgType.LOBBY_CHAT:
		return {}
	var r := Reader.new(b)
	var d := {"kind": r.u8(), "code": r.u8(), "team": r.u8(), "accent": r.u8(), "id": r.id(),
		"name": r.str8(NAME_MAX_BYTES), "text": r.str8(CHAT_MAX_BYTES)}
	if not r.done() or d.kind > CHAT_SYSTEM or d.code >= SYS_COUNT:
		return {}
	return d


# --- Presence ---------------------------------------------------------------

## `profile`: {id, key, name} of the asker (marks it online). `ids`: friends
## to look up; `names`: unresolved friend names (resolved by the server).
static func encode_presence_query(protocol_version: int, profile: Dictionary, ids: PackedStringArray,
		names: PackedStringArray) -> PackedByteArray:
	var w := Writer.new(MsgType.PRESENCE_QUERY)
	w.u16(protocol_version)
	w.id(str(profile.get("id", "")))
	w.id(str(profile.get("key", "")))
	w.str8(str(profile.get("name", "")), NAME_MAX_BYTES)
	var n := mini(ids.size(), MAX_PRESENCE_IDS)
	w.u8(n)
	for i in n:
		w.id(ids[i])
	var m := mini(names.size(), MAX_PRESENCE_NAMES)
	w.u8(m)
	for i in m:
		w.str8(names[i], NAME_MAX_BYTES)
	return w.b


static func decode_presence_query(b: PackedByteArray) -> Dictionary:
	if b.size() < 3 or b.size() > MAX_C2S_BYTES or b.decode_u8(0) != MsgType.PRESENCE_QUERY:
		return {}
	var r := Reader.new(b)
	var d := {"protocol_version": r.u16(), "id": r.id(), "key": r.id(), "name": r.str8(NAME_MAX_BYTES)}
	var n := r.u8()
	if n > MAX_PRESENCE_IDS:
		return {}
	var ids := PackedStringArray()
	for i in n:
		ids.append(r.id())
	var m := r.u8()
	if m > MAX_PRESENCE_NAMES:
		return {}
	var names := PackedStringArray()
	for i in m:
		names.append(r.str8(NAME_MAX_BYTES))
	if not r.done():
		return {}
	d["ids"] = ids
	d["names"] = names
	return d


## `entries`: Array of {id, status, name}.
static func encode_presence(entries: Array) -> PackedByteArray:
	var n := mini(entries.size(), MAX_PRESENCE_REPLY)
	var w := Writer.new(MsgType.PRESENCE)
	w.u8(n)
	for i in n:
		var e: Dictionary = entries[i]
		w.id(str(e.get("id", "")))
		w.u8(int(e.get("status", STATUS_OFFLINE)))
		w.str8(str(e.get("name", "")), NAME_MAX_BYTES)
	return w.b


## {entries: Array of {id, status, name}}.
static func decode_presence(b: PackedByteArray) -> Dictionary:
	if b.size() < 2 or b.decode_u8(0) != MsgType.PRESENCE:
		return {}
	var r := Reader.new(b)
	var n := r.u8()
	if n > MAX_PRESENCE_REPLY:
		return {}
	var entries: Array = []
	for i in n:
		var e := {"id": r.id(), "status": r.u8(), "name": r.str8(NAME_MAX_BYTES)}
		if e.status > STATUS_IN_MATCH:
			return {}
		entries.append(e)
	if not r.done():
		return {}
	return {"entries": entries}


# --- PLAYER_NAMES (match) ---------------------------------------------------

## `names`: net id -> {name, accent}.
static func encode_player_names(names: Dictionary) -> PackedByteArray:
	var w := Writer.new(MsgType.PLAYER_NAMES)
	var keys := names.keys()
	keys.sort()
	var n := mini(keys.size(), MAX_PLAYERS * 2)
	w.u8(n)
	for i in n:
		var e: Dictionary = names[keys[i]]
		w.u16(int(keys[i]))
		w.u8(int(e.get("accent", 0)))
		w.str8(str(e.get("name", "")), NAME_MAX_BYTES)
	return w.b


## net id -> {name, accent}, or null when malformed.
static func decode_player_names(b: PackedByteArray) -> Variant:
	if b.size() < 2 or b.decode_u8(0) != MsgType.PLAYER_NAMES:
		return null
	var r := Reader.new(b)
	var n := r.u8()
	if n > MAX_PLAYERS * 2:
		return null
	var out := {}
	for i in n:
		var id := r.u16()
		out[id] = {"accent": r.u8(), "name": r.str8(NAME_MAX_BYTES)}
	if not r.done():
		return null
	return out
