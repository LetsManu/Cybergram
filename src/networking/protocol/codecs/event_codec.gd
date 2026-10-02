class_name EventCodec
extends RefCounted
## Event batch (channel 1, reliable): u8 type, u32 server tick, u8 count,
## count x record (22 B): u8 kind, u16 target, u16 source, f32 amount, u8 flags,
## f32x3 position.

const HEADER_SIZE: int = 6
const RECORD_SIZE: int = 22
const MAX_EVENTS: int = 255


static func encode(tick: int, events: Array[GameEvent]) -> PackedByteArray:
	var n := mini(events.size(), MAX_EVENTS)
	var b := PackedByteArray()
	b.resize(HEADER_SIZE + n * RECORD_SIZE)
	b.encode_u8(0, MsgType.EVENT)
	b.encode_u32(1, tick & 0xFFFFFFFF)
	b.encode_u8(5, n)
	var off := HEADER_SIZE
	for i in n:
		var e := events[i]
		b.encode_u8(off, e.kind)
		b.encode_u16(off + 1, e.target_net_id)
		b.encode_u16(off + 3, e.source_net_id)
		b.encode_float(off + 5, e.amount)
		b.encode_u8(off + 9, e.flags)
		b.encode_float(off + 10, e.position.x)
		b.encode_float(off + 14, e.position.y)
		b.encode_float(off + 18, e.position.z)
		off += RECORD_SIZE
	return b


## Decodes into `out` (cleared first). Returns the tick, or -1 if malformed.
static func decode(b: PackedByteArray, out: Array[GameEvent]) -> int:
	out.clear()
	if b.size() < HEADER_SIZE or b.decode_u8(0) != MsgType.EVENT:
		return -1
	var n := b.decode_u8(5)
	if b.size() != HEADER_SIZE + n * RECORD_SIZE:
		return -1
	var off := HEADER_SIZE
	for i in n:
		var e := GameEvent.new()
		e.kind = b.decode_u8(off)
		e.target_net_id = b.decode_u16(off + 1)
		e.source_net_id = b.decode_u16(off + 3)
		e.amount = b.decode_float(off + 5)
		e.flags = b.decode_u8(off + 9)
		e.position = Vector3(b.decode_float(off + 10), b.decode_float(off + 14), b.decode_float(off + 18))
		out.append(e)
		off += RECORD_SIZE
	return b.decode_u32(1)
