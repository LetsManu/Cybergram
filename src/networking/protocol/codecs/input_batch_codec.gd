class_name InputBatchCodec
extends RefCounted
## InputBatch (channel 3, every client tick): u8 type, u32 ack_snapshot_tick,
## u8 count, count x InputCommand. Carries the last N commands (redundancy).

const HEADER_SIZE: int = 6


static func encode(ack_snapshot_tick: int, commands: Array[InputCommand]) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(HEADER_SIZE + commands.size() * InputCommand.WIRE_SIZE)
	b.encode_u8(0, MsgType.INPUT_BATCH)
	b.encode_u32(1, ack_snapshot_tick & 0xFFFFFFFF)
	b.encode_u8(5, commands.size())
	var off := HEADER_SIZE
	for c in commands:
		off = c.write_to(b, off)
	return b


## Decodes into `out` (cleared first). Returns the ack tick, or -1 if malformed
## (wrong type, count above `max_count`, or size mismatch).
static func decode(b: PackedByteArray, max_count: int, out: Array[InputCommand]) -> int:
	out.clear()
	if b.size() < HEADER_SIZE or b.decode_u8(0) != MsgType.INPUT_BATCH:
		return -1
	var count := b.decode_u8(5)
	if count > max_count or b.size() != HEADER_SIZE + count * InputCommand.WIRE_SIZE:
		return -1
	for i in count:
		var c := InputCommand.new()
		InputCommand.read_from(b, HEADER_SIZE + i * InputCommand.WIRE_SIZE, c)
		out.append(c)
	return b.decode_u32(1)
