class_name SnapshotCodec
extends RefCounted
## Snapshot (channel 2). Full state, f32 fields; quantisation and delta encoding
## (architecture.md §8.5) replace the entity block in a later epic.
##
## Layout: u8 type, u32 tick, u32 last_processed_seq, u16 own_net_id,
##   u8 has_own, [own block 27 B], u16 entity count, count x entity (36 B).
## Own block: pos f32x3, vel f32x3, u8 flags, u8 coyote ticks, u8 jump buffer ticks.
## Entity: u16 net_id, u8 kind, pos f32x3, vel f32x3, yaw f32, pitch f32, u8 flags.

const _HEADER: int = 12
const _OWN: int = 27
const _ENTITY: int = 2 + 1 + 12 + 12 + 4 + 4 + 1
const _F_GROUNDED: int = 1
const _F_CROUCH: int = 2
const _F_JUMP_HELD: int = 4


static func encode(s: SnapshotData) -> PackedByteArray:
	var has_own := s.own_state != null
	var b := PackedByteArray()
	b.resize(_HEADER + (_OWN if has_own else 0) + 2 + s.entities.size() * _ENTITY)
	b.encode_u8(0, MsgType.SNAPSHOT)
	b.encode_u32(1, s.tick)
	b.encode_u32(5, s.last_processed_seq)
	b.encode_u16(9, s.own_net_id)
	b.encode_u8(11, 1 if has_own else 0)
	var off := _HEADER
	if has_own:
		var m := s.own_state
		off = _put_v3(b, off, m.position)
		off = _put_v3(b, off, m.velocity)
		var f := (_F_GROUNDED if m.grounded else 0) | (_F_CROUCH if m.crouching else 0) \
			| (_F_JUMP_HELD if m.jump_held else 0)
		b.encode_u8(off, f)
		b.encode_u8(off + 1, clampi(m.coyote_ticks, 0, 255))
		b.encode_u8(off + 2, clampi(m.jump_buffer_ticks, 0, 255))
		off += 3
	b.encode_u16(off, s.entities.size())
	off += 2
	for e in s.entities:
		b.encode_u16(off, e.net_id)
		b.encode_u8(off + 2, e.kind)
		off = _put_v3(b, off + 3, e.position)
		off = _put_v3(b, off, e.velocity)
		b.encode_float(off, e.yaw)
		b.encode_float(off + 4, e.pitch)
		b.encode_u8(off + 8, (_F_GROUNDED if e.grounded else 0) | (_F_CROUCH if e.crouching else 0))
		off += 9
	return b


## Returns null if malformed.
static func decode(b: PackedByteArray) -> SnapshotData:
	if b.size() < _HEADER + 2 or b.decode_u8(0) != MsgType.SNAPSHOT:
		return null
	var s := SnapshotData.new()
	s.tick = b.decode_u32(1)
	s.last_processed_seq = b.decode_u32(5)
	s.own_net_id = b.decode_u16(9)
	var off := _HEADER
	if b.decode_u8(11) == 1:
		if b.size() < _HEADER + _OWN + 2:
			return null
		var m := MotorState.new()
		m.position = _get_v3(b, off)
		m.velocity = _get_v3(b, off + 12)
		var f := b.decode_u8(off + 24)
		m.grounded = (f & _F_GROUNDED) != 0
		m.crouching = (f & _F_CROUCH) != 0
		m.jump_held = (f & _F_JUMP_HELD) != 0
		m.coyote_ticks = b.decode_u8(off + 25)
		m.jump_buffer_ticks = b.decode_u8(off + 26)
		s.own_state = m
		off += _OWN
	var count := b.decode_u16(off)
	off += 2
	if b.size() != off + count * _ENTITY:
		return null
	for i in count:
		var e := SnapshotData.EntityState.new()
		e.net_id = b.decode_u16(off)
		e.kind = b.decode_u8(off + 2)
		e.position = _get_v3(b, off + 3)
		e.velocity = _get_v3(b, off + 15)
		e.yaw = b.decode_float(off + 27)
		e.pitch = b.decode_float(off + 31)
		var f := b.decode_u8(off + 35)
		e.grounded = (f & _F_GROUNDED) != 0
		e.crouching = (f & _F_CROUCH) != 0
		s.entities.append(e)
		off += _ENTITY
	return s


static func _put_v3(b: PackedByteArray, off: int, v: Vector3) -> int:
	b.encode_float(off, v.x)
	b.encode_float(off + 4, v.y)
	b.encode_float(off + 8, v.z)
	return off + 12


static func _get_v3(b: PackedByteArray, off: int) -> Vector3:
	return Vector3(b.decode_float(off), b.decode_float(off + 4), b.decode_float(off + 8))
