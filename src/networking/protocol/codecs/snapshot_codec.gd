class_name SnapshotCodec
extends RefCounted
## Snapshot (channel 2). Full state, f32 fields; quantisation and delta encoding
## (architecture.md §8.5) replace the entity block in a later epic.
##
## Layout: u8 type, u32 tick, u32 last_processed_seq, u16 own_net_id,
##   u8 has_own, [own block 27 B + own combat 19 B], u16 entity count, count x entity (41 B).
## Own block: pos f32x3, vel f32x3, u8 flags, u8 coyote ticks, u8 jump buffer ticks.
## Own combat: u16 hp, u16 max_hp, u8 dead, u32 respawn_tick, u8 feed_kind,
##   f32 ammo, u16 ammo_capacity, u16 reserve, u8 ammo_flags.
## Entity: u16 net_id, u8 kind, pos f32x3, vel f32x3, yaw f32, pitch f32, u8 flags,
##   u8 team, u16 hp, u16 max_hp.
## Wardlings (E8, after the entities): u16 count, count x wardling (14 B), then
##   u16 bolt count, count x bolt (12 B: from i16x3, to i16x3; 1/32 m).
## Wardling: u16 net_id, pos i16x3 (1/32 m), u8 yaw, u8 hp (1/255), u8 team (bit 7 =
##   Vanguard), u8 state, u16 owner net id.
## Objectives (E7, after the Wardlings): u8 hardpoint count, count x hardpoint (5 B),
##   u8 front count, count x i8 front index.
## E10: own block +17 B (f32 speed scale, u8 dash ticks, f32x3 dash velocity;
##   flags bit 4 = dash launch); own combat +25 B (4 x [u16 cd left, u16 cd total,
##   u8 flags], u16 shield, u8 level, u16 status); entity +2 B (u16 status).
## Skill FX (E10, between the Wardlings and the objectives): u16 count, count x
##   fx (20 B: u16 id, u8 kind, u8 team, pos i16x3, pos2 i16x3 (1/32 m), u8 yaw,
##   u8 param (1/255), u16 ticks left).
## Hardpoint: i8 owner, i8 capturing team, u8 flags (contested, overtime, severed,
##   locked0, locked1), u16 progress (P x 65535).
## Match (E9, after the objectives, ends the packet): u8 present; if 1: u8 phase,
##   f32 clock s, f32 next phase s, i8 winner, u8 end reason, u8 uplink count,
##   count x uplink (10 B: u8 team, f32 integrity, f32 max, u8 exposed).

const _HEADER: int = 12
const _OWN: int = 27 + 17
const _OWN_COMBAT: int = 19 + 25
const _ENTITY: int = 2 + 1 + 12 + 12 + 4 + 4 + 1 + 1 + 2 + 2 + 2
const _F_DASH_LAUNCH: int = 16
const _FX: int = 20
const _F_GROUNDED: int = 1
const _F_CROUCH: int = 2
const _F_JUMP_HELD: int = 4
const _F_DEAD: int = 8
const _HARDPOINT: int = 5
const _WARDLING: int = 14
const _BOLT: int = 12
const _POS_STEPS: float = 32.0
const _HF_CONTESTED: int = 1
const _HF_OVERTIME: int = 2
const _HF_SEVERED: int = 4
const _HF_LOCKED0: int = 8
const _HF_LOCKED1: int = 16
const _MATCH: int = 1 + 4 + 4 + 1 + 1 + 1
const _UPLINK: int = 10


static func encode(s: SnapshotData) -> PackedByteArray:
	var has_own := s.own_state != null
	var b := PackedByteArray()
	b.resize(_HEADER + (_OWN + _OWN_COMBAT if has_own else 0) + 2 + s.entities.size() * _ENTITY
		+ 2 + s.hardpoints.size() * _HARDPOINT + s.fronts.size()
		+ 4 + s.wardlings.size() * _WARDLING + s.bolts.size() * _BOLT
		+ 2 + s.fx.size() * _FX
		+ 1 + (_MATCH + s.match_state.uplinks.size() * _UPLINK if s.match_state != null else 0))
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
			| (_F_JUMP_HELD if m.jump_held else 0) | (_F_DASH_LAUNCH if m.dash_launch else 0)
		b.encode_u8(off, f)
		b.encode_u8(off + 1, clampi(m.coyote_ticks, 0, 255))
		b.encode_u8(off + 2, clampi(m.jump_buffer_ticks, 0, 255))
		b.encode_float(off + 3, m.speed_scale)
		b.encode_u8(off + 7, clampi(m.dash_ticks, 0, 255))
		off = _put_v3(b, off + 8, m.dash_velocity)
		var c := s.own_combat if s.own_combat != null else SnapshotData.OwnCombat.new()
		b.encode_u16(off, clampi(c.hp, 0, 65535))
		b.encode_u16(off + 2, clampi(c.max_hp, 0, 65535))
		b.encode_u8(off + 4, 1 if c.dead else 0)
		b.encode_u32(off + 5, c.respawn_tick & 0xFFFFFFFF)
		b.encode_u8(off + 9, c.feed_kind)
		b.encode_float(off + 10, c.ammo)
		b.encode_u16(off + 14, clampi(c.ammo_capacity, 0, 65535))
		b.encode_u16(off + 16, clampi(c.reserve, 0, 65535))
		b.encode_u8(off + 18, c.ammo_flags & 0xFF)
		_encode_skills(b, off + 19, c)
		off += _OWN_COMBAT
	b.encode_u16(off, s.entities.size())
	off += 2
	for e in s.entities:
		b.encode_u16(off, e.net_id)
		b.encode_u8(off + 2, e.kind)
		off = _put_v3(b, off + 3, e.position)
		off = _put_v3(b, off, e.velocity)
		b.encode_float(off, e.yaw)
		b.encode_float(off + 4, e.pitch)
		b.encode_u8(off + 8, (_F_GROUNDED if e.grounded else 0) | (_F_CROUCH if e.crouching else 0)
			| (_F_DEAD if e.dead else 0))
		b.encode_u8(off + 9, e.team & 0xFF)
		b.encode_u16(off + 10, clampi(e.hp, 0, 65535))
		b.encode_u16(off + 12, clampi(e.max_hp, 0, 65535))
		b.encode_u16(off + 14, e.status & 0xFFFF)
		off += 16
	off = _encode_wardlings(b, off, s)
	off = _encode_fx(b, off, s)
	off = _encode_objectives(b, off, s)
	_encode_match(b, off, s)
	return b


static func _encode_wardlings(b: PackedByteArray, off: int, s: SnapshotData) -> int:
	b.encode_u16(off, s.wardlings.size())
	off += 2
	for w in s.wardlings:
		b.encode_u16(off, w.net_id)
		_put_q3(b, off + 2, w.position)
		b.encode_u8(off + 8, roundi(fposmod(w.yaw, TAU) / TAU * 256.0) & 0xFF)
		b.encode_u8(off + 9, clampi(roundi(w.hp_frac * 255.0), 0, 255))
		b.encode_u8(off + 10, (w.team & 0x7F) | (0x80 if w.vanguard else 0))
		b.encode_u8(off + 11, w.state & 0xFF)
		b.encode_u16(off + 12, w.owner_net_id & 0xFFFF)
		off += _WARDLING
	b.encode_u16(off, s.bolts.size())
	off += 2
	for bolt in s.bolts:
		_put_q3(b, off, bolt[0])
		_put_q3(b, off + 6, bolt[1])
		off += _BOLT
	return off


## Decodes the Wardling and bolt blocks at `off`; returns the end offset or -1.
static func _decode_wardlings(b: PackedByteArray, off: int, s: SnapshotData) -> int:
	if b.size() < off + 2:
		return -1
	var n := b.decode_u16(off)
	off += 2
	if b.size() < off + n * _WARDLING + 2:
		return -1
	for i in n:
		var w := SnapshotData.WardlingState.new()
		w.net_id = b.decode_u16(off)
		w.position = _get_q3(b, off + 2)
		w.yaw = b.decode_u8(off + 8) * TAU / 256.0
		w.hp_frac = b.decode_u8(off + 9) / 255.0
		var t := b.decode_u8(off + 10)
		w.team = t & 0x7F
		w.vanguard = (t & 0x80) != 0
		w.state = b.decode_u8(off + 11)
		w.owner_net_id = b.decode_u16(off + 12)
		s.wardlings.append(w)
		off += _WARDLING
	var nb := b.decode_u16(off)
	off += 2
	if b.size() < off + nb * _BOLT:
		return -1
	for i in nb:
		s.bolts.append([_get_q3(b, off), _get_q3(b, off + 6)])
		off += _BOLT
	return off


static func _encode_skills(b: PackedByteArray, off: int, c: SnapshotData.OwnCombat) -> void:
	for i in 4:
		b.encode_u16(off + i * 5, clampi(c.skill_cd_left[i], 0, 65535))
		b.encode_u16(off + i * 5 + 2, clampi(c.skill_cd_total[i], 0, 65535))
		b.encode_u8(off + i * 5 + 4, c.skill_flags[i] & 0xFF)
	b.encode_u16(off + 20, clampi(c.shield, 0, 65535))
	b.encode_u8(off + 22, clampi(c.level, 0, 255))
	b.encode_u16(off + 23, c.status & 0xFFFF)


static func _decode_skills(b: PackedByteArray, off: int, c: SnapshotData.OwnCombat) -> void:
	for i in 4:
		c.skill_cd_left[i] = b.decode_u16(off + i * 5)
		c.skill_cd_total[i] = b.decode_u16(off + i * 5 + 2)
		c.skill_flags[i] = b.decode_u8(off + i * 5 + 4)
	c.shield = b.decode_u16(off + 20)
	c.level = b.decode_u8(off + 22)
	c.status = b.decode_u16(off + 23)


static func _encode_fx(b: PackedByteArray, off: int, s: SnapshotData) -> int:
	b.encode_u16(off, s.fx.size())
	off += 2
	for f in s.fx:
		b.encode_u16(off, f.id & 0xFFFF)
		b.encode_u8(off + 2, f.kind & 0xFF)
		b.encode_u8(off + 3, f.team & 0xFF)
		_put_q3(b, off + 4, f.position)
		_put_q3(b, off + 10, f.position2)
		b.encode_u8(off + 16, roundi(fposmod(f.yaw, TAU) / TAU * 256.0) & 0xFF)
		b.encode_u8(off + 17, clampi(roundi(f.param * 255.0), 0, 255))
		b.encode_u16(off + 18, clampi(f.ticks_left, 0, 65535))
		off += _FX
	return off


## Decodes the skill FX block at `off`; returns the end offset or -1.
static func _decode_fx(b: PackedByteArray, off: int, s: SnapshotData) -> int:
	if b.size() < off + 2:
		return -1
	var n := b.decode_u16(off)
	off += 2
	if b.size() < off + n * _FX:
		return -1
	for i in n:
		var f := SnapshotData.FxState.new()
		f.id = b.decode_u16(off)
		f.kind = b.decode_u8(off + 2)
		f.team = b.decode_u8(off + 3)
		f.position = _get_q3(b, off + 4)
		f.position2 = _get_q3(b, off + 10)
		f.yaw = b.decode_u8(off + 16) * TAU / 256.0
		f.param = b.decode_u8(off + 17) / 255.0
		f.ticks_left = b.decode_u16(off + 18)
		s.fx.append(f)
		off += _FX
	return off


static func _put_q3(b: PackedByteArray, off: int, v: Vector3) -> void:
	b.encode_s16(off, clampi(roundi(v.x * _POS_STEPS), -32767, 32767))
	b.encode_s16(off + 2, clampi(roundi(v.y * _POS_STEPS), -32767, 32767))
	b.encode_s16(off + 4, clampi(roundi(v.z * _POS_STEPS), -32767, 32767))


static func _get_q3(b: PackedByteArray, off: int) -> Vector3:
	return Vector3(b.decode_s16(off), b.decode_s16(off + 2), b.decode_s16(off + 4)) / _POS_STEPS


static func _encode_objectives(b: PackedByteArray, off: int, s: SnapshotData) -> int:
	b.encode_u8(off, s.hardpoints.size())
	off += 1
	for h in s.hardpoints:
		b.encode_s8(off, h.owner)
		b.encode_s8(off + 1, h.capturing_team)
		var f := (_HF_CONTESTED if h.contested else 0) | (_HF_OVERTIME if h.overtime else 0) \
			| (_HF_SEVERED if h.severed else 0) | (_HF_LOCKED0 if h.locked[0] else 0) | (_HF_LOCKED1 if h.locked[1] else 0)
		b.encode_u8(off + 2, f)
		b.encode_u16(off + 3, roundi(clampf(h.progress, 0.0, 1.0) * 65535.0))
		off += _HARDPOINT
	b.encode_u8(off, s.fronts.size())
	off += 1
	for fr in s.fronts:
		b.encode_s8(off, clampi(fr, -128, 127))
		off += 1
	return off


static func _encode_match(b: PackedByteArray, off: int, s: SnapshotData) -> void:
	var m := s.match_state
	b.encode_u8(off, 1 if m != null else 0)
	if m == null:
		return
	b.encode_u8(off + 1, m.phase)
	b.encode_float(off + 2, m.time_s)
	b.encode_float(off + 6, m.next_phase_s)
	b.encode_s8(off + 10, clampi(m.winner, -1, 1))
	b.encode_u8(off + 11, m.end_reason)
	b.encode_u8(off + 12, m.uplinks.size())
	off += 1 + _MATCH
	for u in m.uplinks:
		b.encode_u8(off, u.team)
		b.encode_float(off + 1, u.integrity)
		b.encode_float(off + 5, u.max_integrity)
		b.encode_u8(off + 9, 1 if u.exposed else 0)
		off += _UPLINK


## Decodes the match block at `off`; false if malformed or not ending the packet.
static func _decode_match(b: PackedByteArray, off: int, s: SnapshotData) -> bool:
	if b.size() < off + 1:
		return false
	if b.decode_u8(off) == 0:
		return b.size() == off + 1
	if b.size() < off + 1 + _MATCH:
		return false
	var m := SnapshotData.MatchState.new()
	m.phase = b.decode_u8(off + 1)
	m.time_s = b.decode_float(off + 2)
	m.next_phase_s = b.decode_float(off + 6)
	m.winner = b.decode_s8(off + 10)
	m.end_reason = b.decode_u8(off + 11)
	var n := b.decode_u8(off + 12)
	off += 1 + _MATCH
	if b.size() != off + n * _UPLINK:
		return false
	for i in n:
		var u := SnapshotData.UplinkState.new()
		u.team = b.decode_u8(off)
		u.integrity = b.decode_float(off + 1)
		u.max_integrity = b.decode_float(off + 5)
		u.exposed = b.decode_u8(off + 9) != 0
		m.uplinks.append(u)
		off += _UPLINK
	s.match_state = m
	return true


## Decodes the objectives block at `off`; returns the end offset or -1.
static func _decode_objectives(b: PackedByteArray, off: int, s: SnapshotData) -> int:
	if b.size() < off + 1:
		return -1
	var n := b.decode_u8(off)
	off += 1
	if b.size() < off + n * _HARDPOINT + 1:
		return -1
	for i in n:
		var h := SnapshotData.HardpointState.new()
		h.owner = b.decode_s8(off)
		h.capturing_team = b.decode_s8(off + 1)
		var f := b.decode_u8(off + 2)
		h.contested = (f & _HF_CONTESTED) != 0
		h.overtime = (f & _HF_OVERTIME) != 0
		h.severed = (f & _HF_SEVERED) != 0
		h.locked = [(f & _HF_LOCKED0) != 0, (f & _HF_LOCKED1) != 0]
		h.progress = b.decode_u16(off + 3) / 65535.0
		s.hardpoints.append(h)
		off += _HARDPOINT
	var nf := b.decode_u8(off)
	off += 1
	if b.size() < off + nf:
		return -1
	for i in nf:
		s.fronts.append(b.decode_s8(off + i))
	return off + nf


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
		if b.size() < _HEADER + _OWN + _OWN_COMBAT + 2:
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
		m.dash_launch = (f & _F_DASH_LAUNCH) != 0
		m.speed_scale = b.decode_float(off + 27)
		m.dash_ticks = b.decode_u8(off + 31)
		m.dash_velocity = _get_v3(b, off + 32)
		s.own_state = m
		off += _OWN
		var c := SnapshotData.OwnCombat.new()
		c.hp = b.decode_u16(off)
		c.max_hp = b.decode_u16(off + 2)
		c.dead = b.decode_u8(off + 4) != 0
		c.respawn_tick = b.decode_u32(off + 5)
		c.feed_kind = b.decode_u8(off + 9)
		c.ammo = b.decode_float(off + 10)
		c.ammo_capacity = b.decode_u16(off + 14)
		c.reserve = b.decode_u16(off + 16)
		c.ammo_flags = b.decode_u8(off + 18)
		_decode_skills(b, off + 19, c)
		s.own_combat = c
		off += _OWN_COMBAT
	var count := b.decode_u16(off)
	off += 2
	if b.size() < off + count * _ENTITY:
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
		e.dead = (f & _F_DEAD) != 0
		e.team = b.decode_u8(off + 36)
		e.hp = b.decode_u16(off + 37)
		e.max_hp = b.decode_u16(off + 39)
		e.status = b.decode_u16(off + 41)
		s.entities.append(e)
		off += _ENTITY
	off = _decode_wardlings(b, off, s)
	if off >= 0:
		off = _decode_fx(b, off, s)
	if off >= 0:
		off = _decode_objectives(b, off, s)
	if off < 0 or not _decode_match(b, off, s):
		return null
	return s


static func _put_v3(b: PackedByteArray, off: int, v: Vector3) -> int:
	b.encode_float(off, v.x)
	b.encode_float(off + 4, v.y)
	b.encode_float(off + 8, v.z)
	return off + 12


static func _get_v3(b: PackedByteArray, off: int) -> Vector3:
	return Vector3(b.decode_float(off), b.decode_float(off + 4), b.decode_float(off + 8))
