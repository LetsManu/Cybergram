class_name HostChannelCodec
extends RefCounted
## Tiny datagram codec for the local supervisor <-> match-process channel
## (W17, loopback UDP). Layout (big-endian):
##   "CGH" | ver u8 | op u8 | slot u32 | seq u32 | len u16 | payload | mac[16]
## - payload: UTF-8 JSON object (len bytes, at most MAX_PAYLOAD);
## - mac: first 16 bytes of HMAC-SHA256 over everything before it, keyed with
##   the per-process secret from the boot file. Another local user cannot
##   forge a heartbeat or a result without that file (owner-only, deleted on read);
## - seq rises per sender; a receiver drops seq <= the last one (replay).

const MAGIC := "CGH"
const VERSION := 1
const HEADER := 15
const MAC_BYTES := 16
const MAX_PAYLOAD := 16000

## Match process -> supervisor.
const OP_READY := 1
const OP_HEARTBEAT := 2
const OP_ALLOCATED := 3
const OP_RESULT := 4
const OP_ABANDON := 5
const OP_VOID := 6
const OP_BYE := 7
## Supervisor -> match process.
const OP_ALLOCATE := 64
const OP_DRAIN := 65
const OP_SHUTDOWN := 66
const OP_RESULT_ACK := 67


static func encode(op: int, slot: int, seq: int, payload: Dictionary, secret: PackedByteArray) -> PackedByteArray:
	var body := JSON.stringify(payload).to_utf8_buffer() if not payload.is_empty() else PackedByteArray()
	if body.size() > MAX_PAYLOAD:
		return PackedByteArray()
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.put_data(MAGIC.to_ascii_buffer())
	b.put_u8(VERSION)
	b.put_u8(op)
	b.put_u32(slot)
	b.put_u32(seq)
	b.put_u16(body.size())
	b.put_data(body)
	var out := b.data_array
	out.append_array(_mac(secret, out))
	return out


## The slot id of a datagram (to look up its secret), or -1.
static func peek_slot(data: PackedByteArray) -> int:
	if data.size() < HEADER + MAC_BYTES or data.slice(0, 3).get_string_from_ascii() != MAGIC:
		return -1
	return _u32(data, 5)


## {op, slot, seq, payload} or {} when malformed or the MAC does not match.
static func decode(data: PackedByteArray, secret: PackedByteArray) -> Dictionary:
	if data.size() < HEADER + MAC_BYTES or data.size() > HEADER + MAX_PAYLOAD + MAC_BYTES:
		return {}
	if data.slice(0, 3).get_string_from_ascii() != MAGIC or data[3] != VERSION:
		return {}
	var n := (data[13] << 8) | data[14]
	if data.size() != HEADER + n + MAC_BYTES:
		return {}
	var signed := data.slice(0, HEADER + n)
	if not Pbkdf2.constant_time_equals(_mac(secret, signed), data.slice(HEADER + n)):
		return {}
	var payload: Variant = {}
	if n > 0:
		payload = JSON.parse_string(data.slice(HEADER, HEADER + n).get_string_from_utf8())
		if not payload is Dictionary:
			return {}
	return {"op": int(data[4]), "slot": _u32(data, 5), "seq": _u32(data, 9), "payload": payload}


static func _u32(d: PackedByteArray, at: int) -> int:
	return (d[at] << 24) | (d[at + 1] << 16) | (d[at + 2] << 8) | d[at + 3]


static func _mac(secret: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, secret, data).slice(0, MAC_BYTES)
