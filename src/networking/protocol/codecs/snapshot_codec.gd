class_name SnapshotCodec
extends RefCounted
## Snapshot (channel 2), protocol v16 (W16-NET, architecture.md §8.5):
## quantised records, delta-encoded against a snapshot the client acknowledged,
## inside a byte budget. SnapshotEncoder / SnapshotDecoder keep the per-client
## baselines; encode() / decode() here are the stateless full-state forms.
##
## Header (16 B): u8 type, u32 tick, u32 base tick, u32 last_processed_seq,
##   u16 own_net_id, u8 flags (bit 0 has own, bit 1 delta against `base tick`).
## Then, in order:
##   own motor (if has own, 44 B, f32: reconciliation needs full precision):
##     pos f32x3, vel f32x3, u8 flags, u8 coyote, u8 jump buffer, f32 speed scale,
##     u8 dash ticks, f32x3 dash velocity.
##   blob OWN_COMBAT, keyed HEROES, keyed FX, keyed HARDPOINTS, blob FRONTS,
##   blob PROGRESS, blob MATCH (+ f32 match clock when the match is present),
##   u16 bolt count + bolts (12 B: from i16x3, to i16x3, 1/32 m; this tick only),
##   keyed WARDLINGS (last: the budget defers their updates).
## Blob: u8 tag (0 absent, 1 same as baseline, 2 new: u16 length + bytes).
## Keyed section (records keyed by u16 net id / FX id / hardpoint index):
##   u16 removed count + keys, u16 update count + (u16 key, u8 group mask,
##   the masked groups' bytes), u8 stale flag (+ bitmask over the resulting
##   sorted keys, 1 = not refreshed this tick: deferred by priority/budget).
##   A key the baseline lacks must carry every group.
## Records (fixed size, groups are byte ranges):
##   HERO 39 B: pos i16x3 1/32 m | vel i16x3 1/128 m/s | yaw u16, pitch i16 |
##     u8 flags, u16 hp | u16 status | u8 kind, u8 team, u16 max hp, u16 hero index, u8 fork |
##     public build 11 x s8 (v22, items-and-armory.md §3.8: catalog index per
##     INV_LOCS place, -1 empty). Its own group, so it only travels when the
##     build changes (or the client first sees the hero): 14 B per change.
##   WARDLING 13 B: pos i16x3 | u8 yaw | u8 hp (1/255) | u8 state |
##     u8 team (bit 7 Vanguard), u16 owner, u8 tier.
##   FX 18 B: u8 kind, u8 team | pos i16x3 | pos2 i16x3 | u8 yaw, u8 param | u16 expiry tick.
##   HARDPOINT 20 B: i8 owner, i8 capturing, u8 flags, u16 progress | u8 task,
##     u8 task flags, u8 generator HP, u8 cell state, i8 cell team | cell pos i16x3 |
##     u16 carrier, u8 channel, u8 channel done.
## Blob payloads: OWN_COMBAT 44 B (u16 hp, u16 max, u8 dead, u32 respawn tick,
##   u8 feed, f32 ammo, u16 capacity, u16 reserve, u8 ammo flags, 4 x [u16 cd
##   left, u16 cd total, u8 flags], u16 shield, u8 level, u16 status, then (v22, C2
##   prediction parity) u8 x 4 weapon rate / spread / recoil / kick multipliers in
##   hundredths, appended after the v16 bytes so earlier offsets stay put: 48 B);
##   FRONTS u8 n + n x i8; PROGRESS / MATCH as in v15 without the presence
##   byte (the MATCH payload carries clock 0, the clock follows the blob).
## Positions are 1/32 m in i16: +-1023 m covers the maps (Front spans 160 x 415 m).

const HEADER_SIZE: int = 16
const FLAG_HAS_OWN: int = 1
const FLAG_DELTA: int = 2
const OWN_MOTOR_SIZE: int = 44
const OWN_COMBAT_SIZE: int = 48
## v22 C2: first of the 4 weapon multiplier bytes in OWN_COMBAT.
const OWN_MULT_OFF: int = 44

## Keyed sections.
const SEC_HERO: int = 0
const SEC_WARD: int = 1
const SEC_FX: int = 2
const SEC_HP: int = 3
## Blobs.
const BLOB_OWN_COMBAT: int = 0
const BLOB_FRONTS: int = 1
const BLOB_PROGRESS: int = 2
const BLOB_MATCH: int = 3

const BLOB_ABSENT: int = 0
const BLOB_SAME: int = 1
const BLOB_NEW: int = 2

## [offset, length] byte groups per section record.
const GROUPS: Array = [
	[[0, 6], [6, 6], [12, 4], [16, 3], [19, 2], [21, 7], [28, 11]],  # HERO 39
	[[0, 6], [6, 1], [7, 1], [8, 1], [9, 4]],  # WARDLING 13
	[[0, 2], [2, 6], [8, 6], [14, 2], [16, 2]],  # FX 18
	[[0, 5], [5, 5], [10, 6], [16, 4]],  # HARDPOINT 20
]
const RECORD_SIZE: Array[int] = [39, 13, 18, 20]
## v22 public build bytes in the HERO record (SnapshotData.EntityState.build).
const HERO_BUILD_OFF: int = 28

const POS_STEPS: float = 32.0
const VEL_STEPS: float = 128.0
const _BOLT: int = 12
const _F_GROUNDED: int = 1
const _F_CROUCH: int = 2
const _F_JUMP_HELD: int = 4
const _F_DEAD: int = 8
const _F_DASH_LAUNCH: int = 16
const _HF_CONTESTED: int = 1
const _HF_OVERTIME: int = 2
const _HF_SEVERED: int = 4
const _HF_LOCKED0: int = 8
const _HF_LOCKED1: int = 16
const _MATCH: int = 1 + 4 + 4 + 1 + 1 + 1
const _UPLINK: int = 10
## v21: + shop seq/result, visit squad bits (u32), visit Med-Packs, signals; 4 mount slots.
## v22: + 11 inventory places (s8), undo bits (u16), visit transactions (u8).
const _PROGRESS: int = 1 + 4 + 1 + 4 + 1 + 1 + 4 + 1 + 1 + 4 + 1 + 1 + 4 * 6 + 11 + 2 + 1 + 1
const _MOTE: int = 6


## What one client holds at one tick: every section's records by key, the
## Wardlings not refreshed at that tick, and the blob payloads (null = absent).
class View:
	var tick: int = 0
	var sections: Array = [{}, {}, {}, {}]
	var stale: Dictionary = {}  # Wardling key -> true
	var blobs: Array = [null, null, null, null]
	## Decode only: Wardling keys this packet removed explicitly (died / despawned).
	var removed_wardlings: PackedInt32Array = PackedInt32Array()


## Result of encode_delta().
class Encoded:
	var bytes: PackedByteArray
	var view: View
	var is_delta: bool = false
	## Wardling updates deferred (changed but not sent this tick).
	var deferred: int = 0
	## Wardling keys sent this tick.
	var sent: Array[int] = []
	## Wardling keys whose client view is current (sent or unchanged).
	var fresh: Array[int] = []
	## Bolts dropped to fit the budget.
	var bolts_dropped: int = 0


## W11-V1: each basic slot has 6 states (Fork none/A/B x Mastery), 6^3 = 216 fit one byte.
## `bits` is SnapshotData.EntityState.fork_bits; returns 0..215.
static func pack_fork(bits: int) -> int:
	var v := 0
	for slot in 3:
		var st := mini((bits >> (slot * 3)) & 3, 2) * 2 + ((bits >> (slot * 3 + 2)) & 1)
		v = v * 6 + st
	return v


static func unpack_fork(v: int) -> int:
	var bits := 0
	for slot in [2, 1, 0]:
		var st := v % 6
		v /= 6
		bits |= ((st >> 1) | ((st & 1) << 2)) << (slot * 3)
	return bits


## Full state, no budget (tests, tools). Same wire as a delta without baseline.
static func encode(s: SnapshotData) -> PackedByteArray:
	return encode_delta(s, null, 0).bytes


## Decodes a full snapshot; null if malformed or if it is a delta.
static func decode(b: PackedByteArray) -> SnapshotData:
	var r := decode_delta(b, {})
	return r[0] if r[1] == OK else null


# --- quantisation ------------------------------------------------------------

static func q_pos(v: float) -> int:
	return clampi(roundi(v * POS_STEPS), -32767, 32767)


static func q_vel(v: float) -> int:
	return clampi(roundi(v * VEL_STEPS), -32767, 32767)


static func q_yaw(a: float) -> int:
	return roundi(fposmod(a, TAU) / TAU * 65536.0) & 0xFFFF


static func q_pitch(a: float) -> int:
	return clampi(roundi(a / PI * 65536.0), -32767, 32767)


static func _put_q3(b: PackedByteArray, off: int, v: Vector3) -> void:
	b.encode_s16(off, q_pos(v.x))
	b.encode_s16(off + 2, q_pos(v.y))
	b.encode_s16(off + 4, q_pos(v.z))


static func _get_q3(b: PackedByteArray, off: int) -> Vector3:
	return Vector3(b.decode_s16(off), b.decode_s16(off + 2), b.decode_s16(off + 4)) / POS_STEPS


# --- records -------------------------------------------------------------------

static func hero_record(e: SnapshotData.EntityState) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(39)
	_put_q3(r, 0, e.position)
	r.encode_s16(6, q_vel(e.velocity.x))
	r.encode_s16(8, q_vel(e.velocity.y))
	r.encode_s16(10, q_vel(e.velocity.z))
	r.encode_u16(12, q_yaw(e.yaw))
	r.encode_s16(14, q_pitch(e.pitch))
	r.encode_u8(16, (_F_GROUNDED if e.grounded else 0) | (_F_CROUCH if e.crouching else 0) | (_F_DEAD if e.dead else 0))
	r.encode_u16(17, clampi(e.hp, 0, 65535))
	r.encode_u16(19, e.status & 0xFFFF)
	r.encode_u8(21, e.kind & 0xFF)
	r.encode_u8(22, e.team & 0xFF)
	r.encode_u16(23, clampi(e.max_hp, 0, 65535))
	r.encode_u16(25, clampi(e.hero_index, 0, 65535))
	r.encode_u8(27, pack_fork(e.fork_bits))
	for i in SnapshotData.EntityState.BUILD_SIZE:
		r.encode_s8(HERO_BUILD_OFF + i, clampi(e.build[i] if i < e.build.size() else -1, -1, 127))
	return r


static func hero_from(key: int, r: PackedByteArray) -> SnapshotData.EntityState:
	var e := SnapshotData.EntityState.new()
	e.net_id = key
	e.position = _get_q3(r, 0)
	e.velocity = Vector3(r.decode_s16(6), r.decode_s16(8), r.decode_s16(10)) / VEL_STEPS
	e.yaw = r.decode_u16(12) / 65536.0 * TAU
	e.pitch = r.decode_s16(14) / 65536.0 * PI
	var f := r.decode_u8(16)
	e.grounded = (f & _F_GROUNDED) != 0
	e.crouching = (f & _F_CROUCH) != 0
	e.dead = (f & _F_DEAD) != 0
	e.hp = r.decode_u16(17)
	e.status = r.decode_u16(19)
	e.kind = r.decode_u8(21)
	e.team = r.decode_u8(22)
	e.max_hp = r.decode_u16(23)
	e.hero_index = r.decode_u16(25)
	e.fork_bits = unpack_fork(mini(r.decode_u8(27), 215))
	for i in SnapshotData.EntityState.BUILD_SIZE:
		e.build[i] = r.decode_s8(HERO_BUILD_OFF + i)
	return e


static func wardling_record(w: SnapshotData.WardlingState) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(13)
	_put_q3(r, 0, w.position)
	r.encode_u8(6, roundi(fposmod(w.yaw, TAU) / TAU * 256.0) & 0xFF)
	r.encode_u8(7, clampi(roundi(w.hp_frac * 255.0), 0, 255))
	r.encode_u8(8, w.state & 0xFF)
	r.encode_u8(9, (w.team & 0x7F) | (0x80 if w.vanguard else 0))
	r.encode_u16(10, w.owner_net_id & 0xFFFF)
	r.encode_u8(12, clampi(w.tier, 0, 255))
	return r


static func wardling_from(key: int, r: PackedByteArray) -> SnapshotData.WardlingState:
	var w := SnapshotData.WardlingState.new()
	w.net_id = key
	w.position = _get_q3(r, 0)
	w.yaw = r.decode_u8(6) * TAU / 256.0
	w.hp_frac = r.decode_u8(7) / 255.0
	w.state = r.decode_u8(8)
	var t := r.decode_u8(9)
	w.team = t & 0x7F
	w.vanguard = (t & 0x80) != 0
	w.owner_net_id = r.decode_u16(10)
	w.tier = r.decode_u8(12)
	return w


## FX expiry is an absolute tick (low 16 bits), so a running FX is unchanged.
static func fx_record(f: SnapshotData.FxState, tick: int) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(18)
	r.encode_u8(0, f.kind & 0xFF)
	r.encode_u8(1, f.team & 0xFF)
	_put_q3(r, 2, f.position)
	_put_q3(r, 8, f.position2)
	r.encode_u8(14, roundi(fposmod(f.yaw, TAU) / TAU * 256.0) & 0xFF)
	r.encode_u8(15, clampi(roundi(f.param * 255.0), 0, 255))
	r.encode_u16(16, (tick + clampi(f.ticks_left, 0, 32767)) & 0xFFFF)
	return r


static func fx_from(key: int, r: PackedByteArray, tick: int) -> SnapshotData.FxState:
	var f := SnapshotData.FxState.new()
	f.id = key
	f.kind = r.decode_u8(0)
	f.team = r.decode_u8(1)
	f.position = _get_q3(r, 2)
	f.position2 = _get_q3(r, 8)
	f.yaw = r.decode_u8(14) * TAU / 256.0
	f.param = r.decode_u8(15) / 255.0
	var left := (r.decode_u16(16) - tick) & 0xFFFF
	f.ticks_left = left if left < 0x8000 else 0
	return f


static func hardpoint_record(h: SnapshotData.HardpointState) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(20)
	r.encode_s8(0, clampi(h.owner, -128, 127))
	r.encode_s8(1, clampi(h.capturing_team, -128, 127))
	var f := (_HF_CONTESTED if h.contested else 0) | (_HF_OVERTIME if h.overtime else 0) \
		| (_HF_SEVERED if h.severed else 0) | (_HF_LOCKED0 if h.locked[0] else 0) | (_HF_LOCKED1 if h.locked[1] else 0)
	r.encode_u8(2, f)
	r.encode_u16(3, roundi(clampf(h.progress, 0.0, 1.0) * 65535.0))
	r.encode_u8(5, h.task & 0xFF)
	# bits 0-1 Breach, 2-3 Forward Beacon state, 4-7 attunement (0..15): free bits, no layout change
	r.encode_u8(6, (1 if h.breach_phase2 else 0) | (2 if h.shielded else 0) | ((h.beacon & 3) << 2)
		| (roundi(clampf(h.beacon_attune, 0.0, 1.0) * 15.0) << 4))
	r.encode_u8(7, roundi(clampf(h.gen_frac, 0.0, 1.0) * 255.0))
	r.encode_u8(8, h.cell_state & 0xFF)
	r.encode_s8(9, clampi(h.cell_team, -1, 1))
	_put_q3(r, 10, h.cell_pos)
	r.encode_u16(16, h.carrier_id & 0xFFFF)
	r.encode_u8(18, h.channel & 0xFF)
	r.encode_u8(19, roundi(clampf(h.channel_frac, 0.0, 1.0) * 255.0))
	return r


static func hardpoint_from(r: PackedByteArray) -> SnapshotData.HardpointState:
	var h := SnapshotData.HardpointState.new()
	h.owner = r.decode_s8(0)
	h.capturing_team = r.decode_s8(1)
	var f := r.decode_u8(2)
	h.contested = (f & _HF_CONTESTED) != 0
	h.overtime = (f & _HF_OVERTIME) != 0
	h.severed = (f & _HF_SEVERED) != 0
	h.locked = [(f & _HF_LOCKED0) != 0, (f & _HF_LOCKED1) != 0]
	h.progress = r.decode_u16(3) / 65535.0
	h.task = r.decode_u8(5)
	var tf := r.decode_u8(6)
	h.breach_phase2 = (tf & 1) != 0
	h.shielded = (tf & 2) != 0
	h.beacon = (tf >> 2) & 3
	h.beacon_attune = ((tf >> 4) & 15) / 15.0
	h.gen_frac = r.decode_u8(7) / 255.0
	h.cell_state = r.decode_u8(8)
	h.cell_team = r.decode_s8(9)
	h.cell_pos = _get_q3(r, 10)
	h.carrier_id = r.decode_u16(16)
	h.channel = r.decode_u8(18)
	h.channel_frac = r.decode_u8(19) / 255.0
	return h


## Bit i set when group i of `a` and `b` differ (0 = equal).
static func diff_mask(a: PackedByteArray, b: PackedByteArray, groups: Array) -> int:
	var m := 0
	for gi in groups.size():
		var g: Array = groups[gi]
		for i in range(g[0], g[0] + g[1]):
			if a[i] != b[i]:
				m |= 1 << gi
				break
	return m


static func group_bytes(mask: int, groups: Array) -> int:
	var n := 0
	for gi in groups.size():
		if mask & (1 << gi):
			n += groups[gi][1]
	return n


# --- blobs ---------------------------------------------------------------------

static func own_combat_blob(c: SnapshotData.OwnCombat) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(OWN_COMBAT_SIZE)
	b.encode_u16(0, clampi(c.hp, 0, 65535))
	b.encode_u16(2, clampi(c.max_hp, 0, 65535))
	b.encode_u8(4, 1 if c.dead else 0)
	b.encode_u32(5, c.respawn_tick & 0xFFFFFFFF)
	b.encode_u8(9, c.feed_kind & 0xFF)
	b.encode_float(10, c.ammo)
	b.encode_u16(14, clampi(c.ammo_capacity, 0, 65535))
	b.encode_u16(16, clampi(c.reserve, 0, 65535))
	b.encode_u8(18, c.ammo_flags & 0xFF)
	for i in 4:
		b.encode_u16(19 + i * 5, clampi(c.skill_cd_left[i], 0, 65535))
		b.encode_u16(21 + i * 5, clampi(c.skill_cd_total[i], 0, 65535))
		b.encode_u8(23 + i * 5, c.skill_flags[i] & 0xFF)
	b.encode_u16(39, clampi(c.shield, 0, 65535))
	b.encode_u8(41, clampi(c.level, 0, 255))
	b.encode_u16(42, c.status & 0xFFFF)
	var mults := [c.weapon_rate_mult, c.weapon_spread_mult, c.weapon_recoil_mult, c.weapon_kick_mult]
	for i in mults.size():
		b.encode_u8(OWN_MULT_OFF + i, q_mult(mults[i]))
	return b


## v22 C2 weapon multiplier on the wire: hundredths in a u8 (0..2.55).
static func q_mult(v: float) -> int:
	return clampi(roundi(v * 100.0), 0, 255)


static func own_combat_from(b: PackedByteArray) -> SnapshotData.OwnCombat:
	if b.size() != OWN_COMBAT_SIZE:
		return null
	var c := SnapshotData.OwnCombat.new()
	c.hp = b.decode_u16(0)
	c.max_hp = b.decode_u16(2)
	c.dead = b.decode_u8(4) != 0
	c.respawn_tick = b.decode_u32(5)
	c.feed_kind = b.decode_u8(9)
	c.ammo = b.decode_float(10)
	c.ammo_capacity = b.decode_u16(14)
	c.reserve = b.decode_u16(16)
	c.ammo_flags = b.decode_u8(18)
	for i in 4:
		c.skill_cd_left[i] = b.decode_u16(19 + i * 5)
		c.skill_cd_total[i] = b.decode_u16(21 + i * 5)
		c.skill_flags[i] = b.decode_u8(23 + i * 5)
	c.shield = b.decode_u16(39)
	c.level = b.decode_u8(41)
	c.status = b.decode_u16(42)
	c.weapon_rate_mult = b.decode_u8(OWN_MULT_OFF) / 100.0
	c.weapon_spread_mult = b.decode_u8(OWN_MULT_OFF + 1) / 100.0
	c.weapon_recoil_mult = b.decode_u8(OWN_MULT_OFF + 2) / 100.0
	c.weapon_kick_mult = b.decode_u8(OWN_MULT_OFF + 3) / 100.0
	return c


static func fronts_blob(fronts: PackedInt32Array) -> PackedByteArray:
	var n := mini(fronts.size(), 255)
	var b := PackedByteArray()
	b.resize(1 + n)
	b.encode_u8(0, n)
	for i in n:
		b.encode_s8(1 + i, clampi(fronts[i], -128, 127))
	return b


static func fronts_from(b: PackedByteArray) -> Variant:
	if b.is_empty() or b.size() != 1 + b.decode_u8(0):
		return null
	var out := PackedInt32Array()
	for i in b.decode_u8(0):
		out.append(b.decode_s8(1 + i))
	return out


static func progress_blob(p: SnapshotData.ProgressState) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(1 + _PROGRESS + mini(p.motes.size(), 255) * _MOTE)
	var s := SnapshotData.new()
	s.progress = p
	_encode_progress(tmp, 0, s)
	return tmp.slice(1)


static func progress_from(b: PackedByteArray) -> SnapshotData.ProgressState:
	var tmp := PackedByteArray([1])
	tmp.append_array(b)
	var s := SnapshotData.new()
	if _decode_progress(tmp, 0, s) != tmp.size():
		return null
	return s.progress


## The match block without its clock (sent separately so a ticking clock does
## not resend the block).
static func match_blob(m: SnapshotData.MatchState) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(1 + _MATCH + m.uplinks.size() * _UPLINK)
	var s := SnapshotData.new()
	var clockless := SnapshotData.MatchState.new()
	clockless.phase = m.phase
	clockless.next_phase_s = m.next_phase_s
	clockless.winner = m.winner
	clockless.end_reason = m.end_reason
	clockless.uplinks = m.uplinks
	s.match_state = clockless
	_encode_match(tmp, 0, s)
	return tmp.slice(1)


static func match_from(b: PackedByteArray) -> SnapshotData.MatchState:
	var tmp := PackedByteArray([1])
	tmp.append_array(b)
	var s := SnapshotData.new()
	if not _decode_match(tmp, 0, s):
		return null
	return s.match_state


# --- encode --------------------------------------------------------------------

## Encodes `s` against `base` (null = full state). With `budget` > 0, Wardling
## updates that do not fit are deferred (the client keeps the baseline value,
## marked stale) and bolts are trimmed. `ward_order` (null = every changed
## Wardling by key) lists the Wardling keys eligible this tick, in send order;
## changed Wardlings not listed are deferred.
## `cache` (optional, cleared by the caller every tick) maps state objects
## shared between clients to their records, so each is built once per tick.
static func encode_delta(s: SnapshotData, base: View, budget: int, ward_order: Variant = null,
		cache: Dictionary = {}) -> Encoded:
	var out := Encoded.new()
	var v := View.new()
	v.tick = s.tick
	out.view = v
	out.is_delta = base != null
	var bv := base if base != null else View.new()
	var w := StreamPeerBuffer.new()
	var has_own := s.own_state != null
	w.put_u8(MsgType.SNAPSHOT)
	w.put_u32(s.tick & 0xFFFFFFFF)
	w.put_u32((base.tick if base != null else 0) & 0xFFFFFFFF)
	w.put_u32(s.last_processed_seq & 0xFFFFFFFF)
	w.put_u16(s.own_net_id & 0xFFFF)
	w.put_u8((FLAG_HAS_OWN if has_own else 0) | (FLAG_DELTA if base != null else 0))
	if has_own:
		_put_own_motor(w, s.own_state)
	var oc: Variant = null
	if has_own:
		oc = own_combat_blob(s.own_combat if s.own_combat != null else SnapshotData.OwnCombat.new())
	_put_blob(w, oc, bv.blobs[BLOB_OWN_COMBAT], v, BLOB_OWN_COMBAT)
	var heroes := {}
	for e in s.entities:
		var hr: Variant = cache.get(e)
		if hr == null:
			hr = hero_record(e)
			cache[e] = hr
		heroes[e.net_id & 0xFFFF] = hr
	_put_keyed(w, SEC_HERO, heroes, bv, v)
	var fx := {}
	for f in s.fx:
		var fr: Variant = cache.get(f)
		if fr == null:
			fr = fx_record(f, s.tick)
			cache[f] = fr
		fx[f.id & 0xFFFF] = fr
	_put_keyed(w, SEC_FX, fx, bv, v)
	var hps := {}
	for i in s.hardpoints.size():
		var pr: Variant = cache.get(s.hardpoints[i])
		if pr == null:
			pr = hardpoint_record(s.hardpoints[i])
			cache[s.hardpoints[i]] = pr
		hps[i] = pr
	_put_keyed(w, SEC_HP, hps, bv, v)
	_put_blob(w, fronts_blob(s.fronts) if not s.hardpoints.is_empty() or not s.fronts.is_empty() else null,
		bv.blobs[BLOB_FRONTS], v, BLOB_FRONTS)
	_put_blob(w, progress_blob(s.progress) if s.progress != null else null, bv.blobs[BLOB_PROGRESS], v, BLOB_PROGRESS)
	_put_blob(w, match_blob(s.match_state) if s.match_state != null else null, bv.blobs[BLOB_MATCH], v, BLOB_MATCH)
	if s.match_state != null:
		w.put_float(s.match_state.time_s)
	# Wardlings: what must go (removals) and what changed.
	var cur := {}
	for wd in s.wardlings:
		var wr: Variant = cache.get(wd)
		if wr == null:
			wr = wardling_record(wd)
			cache[wd] = wr
		cur[wd.net_id & 0xFFFF] = wr
	var base_w: Dictionary = bv.sections[SEC_WARD]
	var removed: Array[int] = []
	for k in base_w:
		if not cur.has(k):
			removed.append(k)
	var changed := {}  # key -> mask (full mask for keys the baseline lacks)
	var full_mask := (1 << GROUPS[SEC_WARD].size()) - 1
	for k in cur:
		if base_w.has(k):
			if cur[k] == base_w[k]:
				out.fresh.append(k)
				continue
			changed[k] = diff_mask(cur[k], base_w[k], GROUPS[SEC_WARD])
		else:
			changed[k] = full_mask
	# Worst-case Wardling tail: counts, removals, stale bitmask.
	var view_max := base_w.size() - removed.size() + changed.size()
	var tail := 2 + removed.size() * 2 + 2 + 1 + (view_max + 7) / 8
	var bolts: Array = s.bolts
	var room := (budget - w.get_size() - 2 - tail) if budget > 0 else 1 << 30
	var nb := mini(bolts.size(), maxi(room / _BOLT, 0)) if budget > 0 else bolts.size()
	nb = mini(nb, 65535)
	out.bolts_dropped = bolts.size() - nb
	w.put_u16(nb)
	var qb := PackedByteArray()
	qb.resize(_BOLT)
	for i in nb:
		_put_q3(qb, 0, bolts[i][0])
		_put_q3(qb, 6, bolts[i][1])
		w.put_data(qb)
	room -= nb * _BOLT
	var order: Array = changed.keys() if ward_order == null else ward_order
	if ward_order == null:
		order.sort()
	var send := {}
	for k in order:
		if not changed.has(k) or send.has(k):
			continue
		var cost := 3 + group_bytes(changed[k], GROUPS[SEC_WARD])
		if cost > room:
			continue  # smaller ones may still fit
		room -= cost
		send[k] = true
	# Resulting view.
	var vw := {}
	for k in cur:
		if not changed.has(k) or send.has(k):
			vw[k] = cur[k]
		elif base_w.has(k):
			vw[k] = base_w[k]
			v.stale[k] = true
	v.sections[SEC_WARD] = vw
	out.deferred = changed.size() - send.size()
	w.put_u16(removed.size())
	for k in removed:
		w.put_u16(k)
	var sk := send.keys()
	sk.sort()
	w.put_u16(sk.size())
	for k in sk:
		w.put_u16(k)
		var m: int = changed[k]
		w.put_u8(m)
		_put_groups(w, cur[k], m, GROUPS[SEC_WARD])
		out.sent.append(k)
		out.fresh.append(k)
	_put_stale(w, vw, v.stale)
	out.bytes = w.data_array
	return out


static func _put_own_motor(w: StreamPeerBuffer, m: MotorState) -> void:
	for x in [m.position.x, m.position.y, m.position.z, m.velocity.x, m.velocity.y, m.velocity.z]:
		w.put_float(x)
	w.put_u8((_F_GROUNDED if m.grounded else 0) | (_F_CROUCH if m.crouching else 0)
		| (_F_JUMP_HELD if m.jump_held else 0) | (_F_DASH_LAUNCH if m.dash_launch else 0))
	w.put_u8(clampi(m.coyote_ticks, 0, 255))
	w.put_u8(clampi(m.jump_buffer_ticks, 0, 255))
	w.put_float(m.speed_scale)
	w.put_u8(clampi(m.dash_ticks, 0, 255))
	w.put_float(m.dash_velocity.x)
	w.put_float(m.dash_velocity.y)
	w.put_float(m.dash_velocity.z)


static func _put_blob(w: StreamPeerBuffer, cur: Variant, base: Variant, v: View, slot: int) -> void:
	v.blobs[slot] = cur
	if cur == null:
		w.put_u8(BLOB_ABSENT)
	elif base != null and cur == base:
		w.put_u8(BLOB_SAME)
	else:
		w.put_u8(BLOB_NEW)
		w.put_u16((cur as PackedByteArray).size())
		w.put_data(cur)


static func _put_groups(w: StreamPeerBuffer, rec: PackedByteArray, mask: int, groups: Array) -> void:
	for gi in groups.size():
		if mask & (1 << gi):
			w.put_data(rec.slice(groups[gi][0], groups[gi][0] + groups[gi][1]))


## A keyed section with no deferral (every change is sent).
static func _put_keyed(w: StreamPeerBuffer, sec: int, cur: Dictionary, bv: View, v: View) -> void:
	var base: Dictionary = bv.sections[sec]
	var groups: Array = GROUPS[sec]
	var full := (1 << groups.size()) - 1
	var removed: Array = []
	for k in base:
		if not cur.has(k):
			removed.append(k)
	removed.sort()
	w.put_u16(removed.size())
	for k in removed:
		w.put_u16(k)
	var keys := cur.keys()
	keys.sort()
	var ups: Array = []
	for k in keys:
		var m := full
		if base.has(k):
			m = 0 if cur[k] == base[k] else diff_mask(cur[k], base[k], groups)
		if m != 0:
			ups.append([k, m])
	w.put_u16(ups.size())
	for u in ups:
		w.put_u16(u[0])
		w.put_u8(u[1])
		_put_groups(w, cur[u[0]], u[1], groups)
	w.put_u8(0)
	v.sections[sec] = cur


static func _put_stale(w: StreamPeerBuffer, view: Dictionary, stale: Dictionary) -> void:
	if stale.is_empty():
		w.put_u8(0)
		return
	w.put_u8(1)
	var keys := view.keys()
	keys.sort()
	var bits := PackedByteArray()
	bits.resize((keys.size() + 7) / 8)
	bits.fill(0)
	for i in keys.size():
		if stale.has(keys[i]):
			bits[i / 8] |= 1 << (i % 8)
	w.put_data(bits)


# --- decode --------------------------------------------------------------------

## Bounds-checked reader: any read past the end sets `bad`.
class Reader:
	var b: PackedByteArray
	var off: int = 0
	var bad: bool = false

	func _init(data: PackedByteArray, start: int = 0) -> void:
		b = data
		off = start

	func need(n: int) -> bool:
		if bad or off + n > b.size():
			bad = true
			return false
		return true

	func u8() -> int:
		if not need(1):
			return 0
		off += 1
		return b.decode_u8(off - 1)

	func u16() -> int:
		if not need(2):
			return 0
		off += 2
		return b.decode_u16(off - 2)

	func u32() -> int:
		if not need(4):
			return 0
		off += 4
		return b.decode_u32(off - 4)

	func f32() -> float:
		if not need(4):
			return 0.0
		off += 4
		return b.decode_float(off - 4)

	func bytes(n: int) -> PackedByteArray:
		if not need(n):
			return PackedByteArray()
		off += n
		return b.slice(off - n, off)


## Peeks [tick, base_tick, is_delta] from a snapshot header ([] if not one).
static func peek_header(b: PackedByteArray) -> Array:
	if b.size() < HEADER_SIZE or b.decode_u8(0) != MsgType.SNAPSHOT:
		return []
	return [b.decode_u32(1), b.decode_u32(5), (b.decode_u8(15) & FLAG_DELTA) != 0]


## Decodes against the client's baselines (`baselines`: tick -> View).
## Returns [SnapshotData, error, View]: error OK, ERR_INVALID_DATA (malformed)
## or ERR_DOES_NOT_EXIST (the delta's baseline is not in `baselines`).
static func decode_delta(b: PackedByteArray, baselines: Dictionary) -> Array:
	var head := peek_header(b)
	if head.is_empty():
		return [null, ERR_INVALID_DATA, null]
	var bv: View = null
	if head[2]:
		bv = baselines.get(head[1])
		if bv == null:
			return [null, ERR_DOES_NOT_EXIST, null]
	else:
		bv = View.new()
	var r := Reader.new(b, 1)
	var s := SnapshotData.new()
	var v := View.new()
	s.tick = r.u32()
	v.tick = s.tick
	s.base_tick = r.u32()
	s.is_delta = head[2]
	s.last_processed_seq = r.u32()
	s.own_net_id = r.u16()
	var flags := r.u8()
	if flags & ~(FLAG_HAS_OWN | FLAG_DELTA):
		return [null, ERR_INVALID_DATA, null]
	if flags & FLAG_HAS_OWN:
		s.own_state = _read_own_motor(r)
	if not _read_blob(r, bv, v, BLOB_OWN_COMBAT):
		return [null, ERR_INVALID_DATA, null]
	for sec in [SEC_HERO, SEC_FX, SEC_HP]:
		if not _read_keyed(r, sec, bv, v):
			return [null, ERR_INVALID_DATA, null]
	for slot in [BLOB_FRONTS, BLOB_PROGRESS, BLOB_MATCH]:
		if not _read_blob(r, bv, v, slot):
			return [null, ERR_INVALID_DATA, null]
	var clock := r.f32() if v.blobs[BLOB_MATCH] != null else 0.0
	var nb := r.u16()
	if not r.need(nb * _BOLT):
		return [null, ERR_INVALID_DATA, null]
	for i in nb:
		s.bolts.append([_get_q3(b, r.off), _get_q3(b, r.off + 6)])
		r.off += _BOLT
	if not _read_keyed(r, SEC_WARD, bv, v):
		return [null, ERR_INVALID_DATA, null]
	if r.bad or r.off != b.size():
		return [null, ERR_INVALID_DATA, null]
	# Blob payloads -> state.
	if v.blobs[BLOB_OWN_COMBAT] != null:
		s.own_combat = own_combat_from(v.blobs[BLOB_OWN_COMBAT])
		if s.own_combat == null:
			return [null, ERR_INVALID_DATA, null]
	if (s.own_state != null) != (s.own_combat != null):
		return [null, ERR_INVALID_DATA, null]
	if v.blobs[BLOB_FRONTS] != null:
		var fr: Variant = fronts_from(v.blobs[BLOB_FRONTS])
		if fr == null:
			return [null, ERR_INVALID_DATA, null]
		s.fronts = fr
	if v.blobs[BLOB_PROGRESS] != null:
		s.progress = progress_from(v.blobs[BLOB_PROGRESS])
		if s.progress == null:
			return [null, ERR_INVALID_DATA, null]
	if v.blobs[BLOB_MATCH] != null:
		s.match_state = match_from(v.blobs[BLOB_MATCH])
		if s.match_state == null:
			return [null, ERR_INVALID_DATA, null]
		s.match_state.time_s = clock
	var keys: Array = v.sections[SEC_HERO].keys()
	keys.sort()
	for k in keys:
		s.entities.append(hero_from(k, v.sections[SEC_HERO][k]))
	keys = v.sections[SEC_FX].keys()
	keys.sort()
	for k in keys:
		s.fx.append(fx_from(k, v.sections[SEC_FX][k], s.tick))
	keys = v.sections[SEC_HP].keys()
	keys.sort()
	for i in keys.size():
		if keys[i] != i:
			return [null, ERR_INVALID_DATA, null]  # hardpoints are indices 0..n-1
		s.hardpoints.append(hardpoint_from(v.sections[SEC_HP][i]))
	keys = v.sections[SEC_WARD].keys()
	keys.sort()
	for k in keys:
		var wd := wardling_from(k, v.sections[SEC_WARD][k])
		wd.stale = v.stale.has(k)
		s.wardlings.append(wd)
	s.wardlings_removed = v.removed_wardlings
	return [s, OK, v]


static func _read_own_motor(r: Reader) -> MotorState:
	var m := MotorState.new()
	m.position = Vector3(r.f32(), r.f32(), r.f32())
	m.velocity = Vector3(r.f32(), r.f32(), r.f32())
	var f := r.u8()
	m.grounded = (f & _F_GROUNDED) != 0
	m.crouching = (f & _F_CROUCH) != 0
	m.jump_held = (f & _F_JUMP_HELD) != 0
	m.dash_launch = (f & _F_DASH_LAUNCH) != 0
	m.coyote_ticks = r.u8()
	m.jump_buffer_ticks = r.u8()
	m.speed_scale = r.f32()
	m.dash_ticks = r.u8()
	m.dash_velocity = Vector3(r.f32(), r.f32(), r.f32())
	return m


static func _read_blob(r: Reader, bv: View, v: View, slot: int) -> bool:
	match r.u8():
		BLOB_ABSENT:
			v.blobs[slot] = null
		BLOB_SAME:
			if bv.blobs[slot] == null:
				return false
			v.blobs[slot] = bv.blobs[slot]
		BLOB_NEW:
			var n := r.u16()
			v.blobs[slot] = r.bytes(n)
		_:
			return false
	return not r.bad


static func _read_keyed(r: Reader, sec: int, bv: View, v: View) -> bool:
	var base: Dictionary = bv.sections[sec]
	var groups: Array = GROUPS[sec]
	var full := (1 << groups.size()) - 1
	var size: int = RECORD_SIZE[sec]
	var cur := base.duplicate()
	var nr := r.u16()
	if not r.need(nr * 2):
		return false
	for i in nr:
		var k := r.u16()
		if not cur.has(k):
			return false  # removing what the baseline does not hold
		cur.erase(k)
		if sec == SEC_WARD:
			v.removed_wardlings.append(k)
	var nu := r.u16()
	var seen := {}
	for i in nu:
		var k := r.u16()
		var m := r.u8()
		if r.bad or seen.has(k) or m == 0 or (m & ~full) != 0:
			return false
		seen[k] = true
		var rec: PackedByteArray
		if cur.has(k):
			rec = (cur[k] as PackedByteArray).duplicate()
		else:
			if m != full:
				return false  # a new key must carry every group
			rec = PackedByteArray()
			rec.resize(size)
		if not r.need(group_bytes(m, groups)):
			return false
		for gi in groups.size():
			if m & (1 << gi):
				var g: Array = groups[gi]
				for j in g[1]:
					rec[g[0] + j] = r.b[r.off + j]
				r.off += g[1]
		cur[k] = rec
	var stale_flag := r.u8()
	if stale_flag > 1:
		return false
	if stale_flag == 1:
		var keys := cur.keys()
		keys.sort()
		var bits := r.bytes((keys.size() + 7) / 8)
		if r.bad:
			return false
		for i in keys.size():
			if bits[i / 8] & (1 << (i % 8)):
				if seen.has(keys[i]):
					return false  # refreshed and stale at once
				v.stale[keys[i]] = true
	v.sections[sec] = cur
	return not r.bad


# --- v15 block helpers reused for the PROGRESS / MATCH blobs --------------------

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


static func _encode_progress(b: PackedByteArray, off: int, s: SnapshotData) -> int:
	var p := s.progress
	b.encode_u8(off, 1 if p != null else 0)
	if p == null:
		return off + 1
	off += 1
	b.encode_u8(off, clampi(p.level, 0, 255))
	b.encode_u32(off + 1, clampi(p.exp, 0, 0x7FFFFFFF))
	b.encode_u8(off + 5, clampi(p.skill_points, 0, 255))
	b.encode_u32(off + 6, clampi(p.lumen, 0, 0x7FFFFFFF))
	b.encode_u8(off + 10, clampi(p.medpacks, 0, 255))
	b.encode_u8(off + 11, p.flags & 0xFF)
	b.encode_u32(off + 12, p.owned_bits & 0xFFFFFFFF)
	b.encode_u8(off + 16, p.shop_seq & 0xFF)
	b.encode_u8(off + 17, clampi(p.shop_result, 0, 255))
	b.encode_u32(off + 18, p.visit_owned_bits & 0xFFFFFFFF)
	b.encode_u8(off + 22, clampi(p.visit_medpacks, 0, 255))
	b.encode_u8(off + 23, p.signals & 0xFF)
	off += 24
	for i in SnapshotData.ProgressState.MOUNT_SOCKETS.size():
		b.encode_s8(off, clampi(p.mount_item[i], -1, 127))
		b.encode_u8(off + 1, clampi(p.mount_tier[i], 0, 255))
		b.encode_u16(off + 2, clampi(p.mount_paid[i], 0, 65535))
		b.encode_u16(off + 4, clampi(p.mount_paid_visit[i], 0, 65535))
		off += 6
	for i in SnapshotData.ProgressState.INV_LOCS.size():
		b.encode_s8(off + i, clampi(p.inv_items[i], -1, 127))
	off += SnapshotData.ProgressState.INV_LOCS.size()
	b.encode_u16(off, p.inv_undo_bits & 0xFFFF)
	b.encode_u8(off + 2, clampi(p.inv_txns, 0, 255))
	off += 3
	var n := mini(p.motes.size(), 255)
	b.encode_u8(off, n)
	off += 1
	for i in n:
		_put_q3(b, off, p.motes[i])
		off += _MOTE
	return off


## Decodes the progress block at `off`; returns the end offset or -1.
static func _decode_progress(b: PackedByteArray, off: int, s: SnapshotData) -> int:
	if b.size() < off + 1:
		return -1
	if b.decode_u8(off) == 0:
		return off + 1
	if b.size() < off + 1 + _PROGRESS:
		return -1
	off += 1
	var p := SnapshotData.ProgressState.new()
	p.level = b.decode_u8(off)
	p.exp = b.decode_u32(off + 1)
	p.skill_points = b.decode_u8(off + 5)
	p.lumen = b.decode_u32(off + 6)
	p.medpacks = b.decode_u8(off + 10)
	p.flags = b.decode_u8(off + 11)
	p.owned_bits = b.decode_u32(off + 12)
	p.shop_seq = b.decode_u8(off + 16)
	p.shop_result = b.decode_u8(off + 17)
	p.visit_owned_bits = b.decode_u32(off + 18)
	p.visit_medpacks = b.decode_u8(off + 22)
	p.signals = b.decode_u8(off + 23)
	off += 24
	for i in SnapshotData.ProgressState.MOUNT_SOCKETS.size():
		p.mount_item[i] = b.decode_s8(off)
		p.mount_tier[i] = b.decode_u8(off + 1)
		p.mount_paid[i] = b.decode_u16(off + 2)
		p.mount_paid_visit[i] = b.decode_u16(off + 4)
		off += 6
	for i in SnapshotData.ProgressState.INV_LOCS.size():
		p.inv_items[i] = b.decode_s8(off + i)
	off += SnapshotData.ProgressState.INV_LOCS.size()
	p.inv_undo_bits = b.decode_u16(off)
	p.inv_txns = b.decode_u8(off + 2)
	off += 3
	var n := b.decode_u8(off)
	off += 1
	if b.size() < off + n * _MOTE:
		return -1
	for i in n:
		p.motes.append(_get_q3(b, off))
		off += _MOTE
	s.progress = p
	return off


## Decodes the match block at `off`; false if malformed or not ending the packet.
static func _decode_match(b: PackedByteArray, off: int, s: SnapshotData) -> bool:
	if off < 0 or b.size() < off + 1:
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
