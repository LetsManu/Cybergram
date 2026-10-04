class_name ControlCodec
extends RefCounted
## Hello / Welcome / Reject (channel 0). Decoders return {} on malformed input.


## Hello: protocol version + the hero the player picked (ContentDB HERO index,
## 0 = server default). v9 added the hero index.
static func encode_hello(protocol_version: int, hero_index: int = 0) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(5)
	b.encode_u8(0, MsgType.HELLO)
	b.encode_u16(1, protocol_version)
	b.encode_u16(3, hero_index)
	return b


## Accepts the 3-byte pre-v9 form too, so an old client gets a clean
## protocol-mismatch Reject instead of a malformed-packet violation.
static func decode_hello(b: PackedByteArray) -> Dictionary:
	if (b.size() != 5 and b.size() != 3) or b.decode_u8(0) != MsgType.HELLO:
		return {}
	return {"protocol_version": b.decode_u16(1), "hero_index": b.decode_u16(3) if b.size() == 5 else 0}


static func encode_welcome(own_net_id: int, server_tick: int, tick_rate_hz: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(9)
	b.encode_u8(0, MsgType.WELCOME)
	b.encode_u16(1, own_net_id)
	b.encode_u32(3, server_tick)
	b.encode_u16(7, tick_rate_hz)
	return b


static func decode_welcome(b: PackedByteArray) -> Dictionary:
	if b.size() != 9 or b.decode_u8(0) != MsgType.WELCOME:
		return {}
	return {"own_net_id": b.decode_u16(1), "server_tick": b.decode_u32(3), "tick_rate_hz": b.decode_u16(7)}


static func encode_reject(reason: int) -> PackedByteArray:
	return PackedByteArray([MsgType.REJECT, reason])


static func decode_reject(b: PackedByteArray) -> Dictionary:
	if b.size() != 2 or b.decode_u8(0) != MsgType.REJECT:
		return {}
	return {"reason": b.decode_u8(1)}
