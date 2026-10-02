class_name ControlCodec
extends RefCounted
## Hello / Welcome / Reject (channel 0). Decoders return {} on malformed input.


static func encode_hello(protocol_version: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(3)
	b.encode_u8(0, MsgType.HELLO)
	b.encode_u16(1, protocol_version)
	return b


static func decode_hello(b: PackedByteArray) -> Dictionary:
	if b.size() != 3 or b.decode_u8(0) != MsgType.HELLO:
		return {}
	return {"protocol_version": b.decode_u16(1)}


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
