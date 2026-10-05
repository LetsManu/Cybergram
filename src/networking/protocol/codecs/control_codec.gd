class_name ControlCodec
extends RefCounted
## Hello / Welcome / Reject (channel 0). Decoders return {} on malformed input.


## Longest join ticket in a Hello (JoinTicket.MAX_LENGTH fits a str8).
const TICKET_MAX: int = 255


## Hello: protocol version + the hero the player picked (ContentDB HERO index,
## 0 = server default) + the lobby slot token (0 = none). v9 added the hero,
## v10 the token, v17 the optional join ticket (str8 ASCII; matchmade matches).
static func encode_hello(protocol_version: int, hero_index: int = 0, token: int = 0, ticket: String = "") -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(7)
	b.encode_u8(0, MsgType.HELLO)
	b.encode_u16(1, protocol_version)
	b.encode_u16(3, hero_index)
	b.encode_u16(5, token)
	if ticket != "":
		var raw := ticket.to_ascii_buffer()
		if raw.size() <= TICKET_MAX:
			b.append(raw.size())
			b.append_array(raw)
	return b


## Accepts the shorter pre-v10 forms too, so an old client gets a clean
## protocol-mismatch Reject instead of a malformed-packet violation.
static func decode_hello(b: PackedByteArray) -> Dictionary:
	if b.size() < 3 or b.decode_u8(0) != MsgType.HELLO:
		return {}
	var ticket := ""
	if b.size() > 7:
		var n := b.decode_u8(7)
		if b.size() != 8 + n or n == 0:
			return {}
		var raw := b.slice(8)
		for c in raw:
			if c < 0x21 or c > 0x7E:
				return {}  # tickets are printable ASCII only
		ticket = raw.get_string_from_ascii()
	elif not (b.size() in [3, 5, 7]):
		return {}
	return {"protocol_version": b.decode_u16(1),
		"hero_index": b.decode_u16(3) if b.size() >= 5 else 0,
		"token": b.decode_u16(5) if b.size() >= 7 else 0, "ticket": ticket}


## v17: `mood_seed` = the match mood seed (u32), the same for every client of
## the match; the client ambience derives its look from it.
static func encode_welcome(own_net_id: int, server_tick: int, tick_rate_hz: int, mood_seed: int = 0) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(13)
	b.encode_u8(0, MsgType.WELCOME)
	b.encode_u16(1, own_net_id)
	b.encode_u32(3, server_tick)
	b.encode_u16(7, tick_rate_hz)
	b.encode_u32(9, mood_seed & 0xFFFFFFFF)
	return b


static func decode_welcome(b: PackedByteArray) -> Dictionary:
	if b.size() != 13 or b.decode_u8(0) != MsgType.WELCOME:
		return {}
	return {"own_net_id": b.decode_u16(1), "server_tick": b.decode_u32(3), "tick_rate_hz": b.decode_u16(7),
		"mood_seed": b.decode_u32(9)}


static func encode_reject(reason: int) -> PackedByteArray:
	return PackedByteArray([MsgType.REJECT, reason])


static func decode_reject(b: PackedByteArray) -> Dictionary:
	if b.size() != 2 or b.decode_u8(0) != MsgType.REJECT:
		return {}
	return {"reason": b.decode_u8(1)}
