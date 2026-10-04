class_name LobbyCodec
extends RefCounted
## Lobby messages (MsgType.LOBBY_*), all on the reliable control channel.

const PHASE_WAITING: int = 0   ## players join, pick heroes, toggle Ready
const PHASE_COUNTDOWN: int = 1 ## everyone is ready; the match starts at 0
const PHASE_IN_MATCH: int = 2  ## a match is running (late joiners take over a bot)
const MAX_PLAYERS: int = 16


static func encode_join(protocol_version: int, hero_index: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(5)
	b.encode_u8(0, MsgType.LOBBY_JOIN)
	b.encode_u16(1, protocol_version)
	b.encode_u16(3, hero_index)
	return b


static func decode_join(b: PackedByteArray) -> Dictionary:
	if b.size() != 5 or b.decode_u8(0) != MsgType.LOBBY_JOIN:
		return {}
	return {"protocol_version": b.decode_u16(1), "hero_index": b.decode_u16(3)}


static func encode_pick(hero_index: int, ready: bool) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u8(0, MsgType.LOBBY_PICK)
	b.encode_u16(1, hero_index)
	b.encode_u8(3, 1 if ready else 0)
	return b


static func decode_pick(b: PackedByteArray) -> Dictionary:
	if b.size() != 4 or b.decode_u8(0) != MsgType.LOBBY_PICK:
		return {}
	return {"hero_index": b.decode_u16(1), "ready": b.decode_u8(3) != 0}


## `slots`: Array of {team, hero_index, ready}. `you`: index of the receiver.
static func encode_state(phase: int, countdown_s: int, you: int, slots: Array) -> PackedByteArray:
	var n := mini(slots.size(), MAX_PLAYERS)
	var b := PackedByteArray()
	b.resize(5 + n * 4)
	b.encode_u8(0, MsgType.LOBBY_STATE)
	b.encode_u8(1, phase)
	b.encode_u8(2, clampi(countdown_s, 0, 255))
	b.encode_u8(3, you)
	b.encode_u8(4, n)
	for i in n:
		var s: Dictionary = slots[i]
		b.encode_u8(5 + i * 4, s.team)
		b.encode_u16(6 + i * 4, s.hero_index)
		b.encode_u8(8 + i * 4, 1 if s.ready else 0)
	return b


static func decode_state(b: PackedByteArray) -> Dictionary:
	if b.size() < 5 or b.decode_u8(0) != MsgType.LOBBY_STATE:
		return {}
	var n := b.decode_u8(4)
	if b.size() != 5 + n * 4:
		return {}
	var slots: Array = []
	for i in n:
		slots.append({"team": b.decode_u8(5 + i * 4), "hero_index": b.decode_u16(6 + i * 4),
			"ready": b.decode_u8(8 + i * 4) != 0})
	return {"phase": b.decode_u8(1), "countdown": b.decode_u8(2), "you": b.decode_u8(3), "slots": slots}


static func encode_start(token: int, team: int, hero_index: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(6)
	b.encode_u8(0, MsgType.LOBBY_START)
	b.encode_u16(1, token)
	b.encode_u8(3, team)
	b.encode_u16(4, hero_index)
	return b


static func decode_start(b: PackedByteArray) -> Dictionary:
	if b.size() != 6 or b.decode_u8(0) != MsgType.LOBBY_START:
		return {}
	return {"token": b.decode_u16(1), "team": b.decode_u8(3), "hero_index": b.decode_u16(4)}
