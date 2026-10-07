class_name TrapWorld
extends RefCounted
## Server-side state for the gadget skills of design/gdd/heroes.md §3.7:
## Juniper Quill's traps (Snare Coil, Tripwire Lattice, Pressure Mine, Killbox;
## §4.3) and Hex's hacks (Breach Spike, Static Field, Relay Hop, Zero Day;
## §4.7, §5.4). Owned by AbilityWorld (`traps`), which calls step() every tick
## and routes shots, projectiles and expiry here through small hooks.
##
## Traps, the Killbox emitter and Static Fields are real AbilityWorld
## Deployables (so shots, expiry and HP work as for walls) with a kind >=
## KIND_BASE and a side record (Data). Malfunction ("hack") is a timed flag on
## any gadget (Deployable or Wardling) with post-hack immunity (§3.7).

## Deployable kinds owned by this class (DeployableEffectDef.Kind uses 0..2).
const KIND_BASE: int = 100
const KIND_SNARE: int = 100
const KIND_WIRE: int = 101
const KIND_MINE: int = 102
const KIND_KILLBOX: int = 103
const KIND_FIELD: int = 104
## Replicated FX kinds (AbilityWorld.FX_* use 1..8; H2 owns 40..49).
const FX_FIRST: int = 40
const FX_SNARE: int = 40
const FX_WIRE: int = 41
const FX_MINE: int = 42
const FX_DOME: int = 43
const FX_FIELD: int = 44
const FX_HACK: int = 45
const FX_PULSE: int = 46
## FX param encoding for trap kinds: bit "down" (Malfunction) + HP fraction.
const DOWN_THRESHOLD: float = 0.52
## PLACEHOLDER. Pending Tripwire anchor window (s), wire hit width (m).
const ANCHOR_WINDOW_S: float = 8.0
const WIRE_HIT_M: float = 0.6
const WIRE_HEIGHT_M: float = 0.9
## PLACEHOLDER. Shoot / block capsule of a trap (m).
const TRAP_RADIUS_M: float = 0.35
const TRAP_HEIGHT_M: float = 0.6
## PLACEHOLDER. A hero re-crossing the fence within this window is not hit twice (s).
const FENCE_REHIT_S: float = 0.8
## PLACEHOLDER. Hex's Static Field keeps gadgets down this long after they leave (s).
const FIELD_LINGER_S: float = 1.0


## Side record of one trap-kind Deployable.
class Data:
	var d: AbilityWorld.Deployable
	var def: TrapEffectDef
	var ctx: EffectContext
	var kind: int = 0
	var pos_b: Vector3 = Vector3.ZERO
	var arm_tick: int = 0
	var chain_tick: int = -1
	var orphan_capped: bool = false
	var inside: Dictionary = {}      # hero net id -> bool (Killbox)
	var last_cross: Dictionary = {}  # hero net id -> tick
	var born_tick: int = 0
	var hits: int = 0  # W10-T1: triggers so far (Razor / re-arm survive `count` of them)


var world: AbilityWorld
## Deployable -> Data.
var data: Dictionary = {}
## gadget (Deployable or WardlingSim) -> [malfunction_until, immune_until, Fx].
var hacks: Dictionary = {}
## W11-M1 Hijack: trap Deployable -> [until_tick, original team, original owner id, original ctx].
var hijacks: Dictionary = {}
## hero -> tick until which it is Scrambled (server state; HUD is a client concern).
var scramble_until: Dictionary = {}
## hero net id -> [Vector3 anchor A, expires tick, Fx]: Tripwire anchor waiting for B.
var pending: Dictionary = {}
## Diagnostics / tests.
var triggers: int = 0
var chains: int = 0


func _init(w: AbilityWorld) -> void:
	world = w


# --- Placement -------------------------------------------------------------------

## True when `point` lies inside a Static Field of a team other than `team`.
func field_blocks(team: int, point: Vector3) -> bool:
	for dd in data:
		var rec: Data = data[dd]
		if rec.kind == KIND_FIELD and rec.d.alive and rec.d.team != team \
				and _flat(rec.d.pos, point) <= rec.d.radius:
			return true
	return false


## Places a Snare Coil / Pressure Mine (single point) or a finished Tripwire
## (`pos_b` != ZERO). Enforces the Linkwork budget and the skill's own cap.
func spawn_trap(ctx: EffectContext, def: TrapEffectDef, pos: Vector3, pos_b: Vector3 = Vector3.ZERO) -> Data:
	if field_blocks(ctx.team, pos):
		return null
	_enforce_caps(ctx, def)
	var t := world.tick()
	var rec := Data.new()
	rec.def = def
	rec.ctx = ctx
	rec.kind = KIND_SNARE + int(def.kind)
	rec.pos_b = pos_b
	rec.born_tick = t
	rec.arm_tick = t + ctx.ticks(def.arm_param)
	var d := _new_deployable(ctx, rec.kind, pos, roundi(def.life_s * world.tick_hz))
	d.max_hp = ctx.param(def.hp_param)
	d.hp = d.max_hp
	d.radius = def.trigger_radius_m
	rec.d = d
	var fx_kind := [FX_SNARE, FX_WIRE, FX_MINE][int(def.kind)] as int
	d.fx = world.add_fx(fx_kind, d.team, pos, pos_b if def.kind == TrapEffectDef.Kind.WIRE else pos, ctx.yaw,
		maxi(d.expires_tick - t, 1))
	data[d] = rec
	world.deployables.append(d)
	return rec


## Tripwire press 1: anchor A (replaces a pending one). Press 2 (close=true):
## anchor B within `distance` m of A completes the wire.
func tripwire_press(ctx: EffectContext, def: TrapEffectDef, close: bool) -> void:
	var id := ctx.caster.net_id
	var p := world.ground_point(ctx.origin, ctx.dir, ctx.param(&"range"))
	if not close:
		_drop_pending(id)
		if field_blocks(ctx.team, p):
			return
		var f := world.add_fx(FX_WIRE, ctx.team, p, p, ctx.yaw, roundi(ANCHOR_WINDOW_S * world.tick_hz))
		pending[id] = [p, world.tick() + roundi(ANCHOR_WINDOW_S * world.tick_hz), f]
		return
	if not pending.has(id):
		return
	var a: Vector3 = pending[id][0]
	_drop_pending(id)
	var off := p - a
	off.y = 0.0
	var length := ctx.param(&"distance")
	if off.length() > length:
		off = off.normalized() * length
	if off.length() < 1.0:
		return  # anchors too close: no wire
	var b := a + off
	b.y = world.ground_point(b + Vector3.UP * 3.0, Vector3.DOWN, 8.0).y
	spawn_trap(ctx, def, a, b)


## Killbox emitter / Static Field: a zone Deployable of `kind` living `life_s`.
func spawn_zone(ctx: EffectContext, kind: int, life_s: float, hp: float, fx_kind: int, radius: float) -> Data:
	if field_blocks(ctx.team, ctx.point):
		return null
	var rec := Data.new()
	rec.kind = kind
	rec.ctx = ctx
	rec.born_tick = world.tick()
	var d := _new_deployable(ctx, kind, ctx.point, roundi(life_s * world.tick_hz))
	d.max_hp = hp
	d.hp = hp
	d.radius = radius
	rec.d = d
	d.fx = world.add_fx(fx_kind, d.team, d.pos, Vector3(radius, 0.0, 0.0), ctx.yaw, maxi(d.expires_tick - world.tick(), 1))
	data[d] = rec
	world.deployables.append(d)
	return rec


# --- Per tick --------------------------------------------------------------------

func step() -> void:
	var t := world.tick()
	_step_pending(t)
	_step_hacks(t)
	_step_hijacks(t)
	for dd in data.keys():
		var rec: Data = data[dd]
		var d := rec.d
		if not d.alive:
			continue
		if rec.ctx.caster == null or not is_instance_valid(rec.ctx.caster) or rec.ctx.caster.combat == null:
			d.alive = false
			continue
		_cap_orphan(rec, t)
		var down := is_down(d, t)
		_encode(d, down)
		if down:
			continue
		match rec.kind:
			KIND_SNARE, KIND_WIRE, KIND_MINE:
				_step_trap(rec, t)
			KIND_KILLBOX:
				_step_dome(rec, t)
			KIND_FIELD:
				_step_field(rec, t)


func on_end(d: AbilityWorld.Deployable) -> void:
	data.erase(d)
	hijacks.erase(d)
	_clear_hack(d)


## Ray test against a trap-kind deployable: t or -1 (killbox emitter and traps
## are shootable; fields are not).
func ray(o: Vector3, dir: Vector3, d: AbilityWorld.Deployable) -> float:
	var rec: Data = data.get(d)
	if rec == null or rec.kind == KIND_FIELD:
		return -1.0
	var best := HitscanTracer.ray_vertical_capsule(o, dir, d.pos.y + TRAP_RADIUS_M, d.pos.y + TRAP_HEIGHT_M,
		Vector2(d.pos.x, d.pos.z), TRAP_RADIUS_M)
	if rec.kind == KIND_WIRE:
		var tb := HitscanTracer.ray_vertical_capsule(o, dir, rec.pos_b.y + TRAP_RADIUS_M, rec.pos_b.y + TRAP_HEIGHT_M,
			Vector2(rec.pos_b.x, rec.pos_b.z), TRAP_RADIUS_M)
		if tb >= 0.0 and (best < 0.0 or tb < best):
			best = tb
	elif rec.kind == KIND_KILLBOX:
		best = HitscanTracer.ray_vertical_capsule(o, dir, d.pos.y + 0.5, d.pos.y + 1.4, Vector2(d.pos.x, d.pos.z), 0.5)
	return best


# --- Hacks (heroes.md §3.7, §5.4) --------------------------------------------------

## True while `gadget` is Malfunctioning.
func is_down(gadget: Object, tick: int = -1) -> bool:
	var rec: Array = hacks.get(gadget, [])
	if rec.is_empty():
		return false
	return (world.tick() if tick < 0 else tick) < int(rec[0])


## Malfunction `gadget` for `ticks`. Basic skills respect post-hack immunity
## (`immune_ticks` after the Malfunction ends); the ultimate and Static Field
## pass `ignore_immunity`. Returns false when immune. Wardlings stall.
func hack(gadget: Object, ticks: int, immune_ticks: int, ignore_immunity: bool = false) -> bool:
	var t := world.tick()
	var rec: Array = hacks.get(gadget, [0, 0, null])
	var until := int(rec[0])
	if t >= until and t < int(rec[1]) and not ignore_immunity:
		return false
	until = maxi(until if t < until else 0, t + ticks)
	rec[0] = until
	rec[1] = until + immune_ticks
	var fx: AbilityWorld.Fx = rec[2]
	if fx == null or not world.fx.has(fx):
		fx = world.add_fx(FX_HACK, _team_of(gadget), _pos_of(gadget), Vector3(_size_of(gadget), 0.0, 0.0), 0.0, until - t)
		rec[2] = fx
	fx.expires_tick = until
	hacks[gadget] = rec
	if gadget is WardlingSim:
		MinionmancerHooks.stun(gadget as WardlingSim, until)
	return true


## Gadget category duration for a Breach Spike (§3.7 table, scaled by the skill's
## `duration` multiplier = 1 + 0.25 per Boost).
func category_ticks(gadget: Object, def: HackEffectDef, scale: float) -> int:
	var s := def.deployable_s
	if gadget is WardlingSim:
		s = def.wardling_s
	elif gadget is AbilityWorld.Deployable:
		var k := (gadget as AbilityWorld.Deployable).kind
		if k >= KIND_SNARE and k <= KIND_KILLBOX:
			s = def.trap_s
	return roundi(s * scale * world.tick_hz)


## Every enemy gadget of `team` within `radius` of `center`: live enemy
## Deployables (not their own hacked ones filtered) and Wardlings.
func gadgets_in_radius(center: Vector3, radius: float, team: int) -> Array[Object]:
	var out: Array[Object] = []
	for d in world.deployables:
		if d.alive and d.team != team and _flat(d.pos, center) <= radius:
			out.append(d)
	for e in world.entities_in_radius(center, radius, team, true, false, false, true):
		out.append(e)
	return out


## Breach Spike met a deployable: hack it. Returns true when `on_hit` held a
## HackEffectDef (the projectile is consumed instead of damaging the gadget).
func projectile_hit_deployable(ctx: EffectContext, d: AbilityWorld.Deployable, on_hit: Array) -> bool:
	var handled := false
	for e in on_hit:
		if e is HackEffectDef:
			(e as HackEffectDef).hack_gadget(ctx, d)
			handled = true
	return handled


## Scramble (§3.6): server-side timer; clients lose HUD info (presentation TBD).
func scramble(h: HeroBody, ticks: int) -> void:
	scramble_until[h] = maxi(int(scramble_until.get(h, 0)), world.tick() + ticks)


func is_scrambled(h: HeroBody) -> bool:
	return world.tick() < int(scramble_until.get(h, 0))


## Lag (Zero Day): every READY basic skill of `h` goes on a `ticks` cooldown.
func lag(h: HeroBody, ticks: int) -> int:
	var n := 0
	var t := world.tick()
	for s in h.combat.abilities.skills:
		if s.def.ultimate or s.active or s.is_multi() or s.on_cooldown(t):
			continue
		s.cooldown_total_ticks = ticks
		s.cooldown_end_tick = t + ticks
		n += 1
	return n


# --- Relay Hop targeting ----------------------------------------------------------

## GADGET targeting: the allied gadget (Wardling / deployable) or Malfunctioning
## enemy gadget closest to the crosshair. Sets ctx.target (Wardling) or ctx.point.
func aim_gadget(ctx: EffectContext, range_m: float, cone: float) -> bool:
	var best_a := cone
	var best_t: Node3D = null
	var best_p := Vector3.ZERO
	var found := false
	var ww := world.server.wardlings
	var t := world.tick()
	if ww != null:
		for w in ww.wardlings:
			if w.dead or w.team != ctx.team:
				continue
			var a := _angle(ctx, w.chest(), range_m)
			if a >= 0.0 and a <= best_a and ww.has_los(ctx.origin, w.chest()):
				best_a = a
				best_t = w
				found = true
	for d in world.deployables:
		if not d.alive or d.kind == KIND_FIELD:
			continue
		if d.team != ctx.team and not is_down(d, t):
			continue
		var c := d.pos + Vector3(0.0, 0.5, 0.0)
		var a2 := _angle(ctx, c, range_m)
		if a2 >= 0.0 and a2 <= best_a:
			best_a = a2
			best_t = null
			best_p = d.pos
			found = true
	if found:
		ctx.target = best_t
		ctx.point = best_t.global_position if best_t != null else best_p
	return found


# --- Hijack (heroes.md §4.7 Breach Spike Fork A, §3.7) -------------------------

## True when `d` is a trap-kind gadget that can be hijacked (not Static Fields,
## Wardlings, walls or beacons).
func can_hijack(d: Object) -> bool:
	if not d is AbilityWorld.Deployable:
		return false
	var rec: Data = data.get(d)
	return rec != null and rec.kind != KIND_FIELD and (d as AbilityWorld.Deployable).alive


func is_hijacked(d: Object) -> bool:
	return hijacks.has(d)


## The trap `d` switches to the hijacker's team for `ticks`: it triggers against its
## owner's team. Returns false when it cannot be hijacked or is already hijacked.
func hijack(d: AbilityWorld.Deployable, by: EffectContext, ticks: int) -> bool:
	if not can_hijack(d) or hijacks.has(d) or d.team == by.team or ticks <= 0:
		return false
	var rec: Data = data[d]
	var t := world.tick()
	hijacks[d] = [t + ticks, d.team, d.owner_id, rec.ctx]
	var c := rec.ctx.with_target(null, d.pos)
	c.caster = by.caster
	c.team = by.team
	rec.ctx = c
	d.team = by.team
	d.owner_id = by.caster.net_id
	if d.fx != null:
		d.fx.team = d.team
	rec.arm_tick = maxi(rec.arm_tick, t + roundi(c.param(&"arm_time") * world.tick_hz))
	return true


func _step_hijacks(t: int) -> void:
	for d in hijacks.keys():
		var h: Array = hijacks[d]
		if t >= int(h[0]) or not d.alive:
			_restore_hijack(d)


func _restore_hijack(d: AbilityWorld.Deployable) -> void:
	var h: Array = hijacks.get(d, [])
	hijacks.erase(d)
	if h.is_empty():
		return
	d.team = int(h[1])
	d.owner_id = int(h[2])
	if d.fx != null:
		d.fx.team = d.team
	var rec: Data = data.get(d)
	if rec != null:
		rec.ctx = h[3]


# --- Internals ---------------------------------------------------------------------

func _angle(ctx: EffectContext, p: Vector3, range_m: float) -> float:
	var to := p - ctx.origin
	var dist := to.length()
	if dist > range_m or dist < 0.01:
		return -1.0
	return ctx.dir.angle_to(to / dist)


func _new_deployable(ctx: EffectContext, kind: int, pos: Vector3, life_ticks: int) -> AbilityWorld.Deployable:
	var d := AbilityWorld.Deployable.new()
	d.id = world._next_id
	world._next_id += 1
	d.kind = kind
	d.team = ctx.team
	d.owner_id = ctx.caster.net_id
	d.skill = ctx.skill
	d.pos = pos
	d.yaw = ctx.yaw
	d.expires_tick = world.tick() + life_ticks
	return d


func _enforce_caps(ctx: EffectContext, def: TrapEffectDef) -> void:
	var mine: Array[Data] = []
	for dd in data:
		var rec: Data = data[dd]
		if rec.d.alive and rec.d.owner_id == ctx.caster.net_id and rec.kind <= KIND_MINE:
			mine.append(rec)
	mine.sort_custom(func(a: Data, b: Data) -> bool: return a.born_tick < b.born_tick)
	# The skill's own cap first (e.g. max 2 mines), then the Linkwork budget.
	var cap := roundi(ctx.param(&"max_placed"))
	if cap > 0:
		var same: Array[Data] = []
		for rec in mine:
			if rec.ctx.skill == ctx.skill:
				same.append(rec)
		while same.size() >= cap:
			var old: Data = same.pop_front()
			old.d.alive = false
			mine.erase(old)
	while mine.size() >= def.budget:
		var old2: Data = mine.pop_front()
		old2.d.alive = false


## Linkwork: traps persist 30 s after their owner dies, then decay.
func _cap_orphan(rec: Data, t: int) -> void:
	if rec.def == null or rec.orphan_capped or not rec.ctx.caster.combat.dead:
		return
	rec.orphan_capped = true
	rec.d.expires_tick = mini(rec.d.expires_tick, t + roundi(rec.def.orphan_life_s * world.tick_hz))


func _encode(d: AbilityWorld.Deployable, down: bool) -> void:
	if d.fx == null:
		return
	var frac := clampf(d.hp / d.max_hp, 0.0, 1.0) if d.max_hp > 0.0 else 1.0
	d.fx.param = (DOWN_THRESHOLD + 0.45 * frac) if down else 0.5 * frac


func _in_killbox(rec: Data) -> bool:
	for dd in data:
		var k: Data = data[dd]
		if k.kind == KIND_KILLBOX and k.d.alive and k.d.team == rec.d.team and k.d.owner_id == rec.d.owner_id \
				and not is_down(k.d) and _flat(k.d.pos, rec.d.pos) <= k.ctx.param(&"radius"):
			return true
	return false


func _step_trap(rec: Data, t: int) -> void:
	var boxed := _in_killbox(rec)
	var forced := rec.chain_tick >= 0 and t >= rec.chain_tick
	if t < rec.arm_tick and not boxed and not forced:
		return
	var victims := _victims(rec)
	if victims.is_empty() and not forced:
		return
	_trigger(rec, victims, 1.3 if boxed else 1.0, t)


func _victims(rec: Data) -> Array[Node3D]:
	var d := rec.d
	var out: Array[Node3D] = []
	if rec.kind == KIND_WIRE:
		var a := d.pos + Vector3(0.0, WIRE_HEIGHT_M, 0.0)
		var b := rec.pos_b + Vector3(0.0, WIRE_HEIGHT_M, 0.0)
		var mid := (d.pos + rec.pos_b) * 0.5
		for e in world.entities_in_radius(mid, d.pos.distance_to(rec.pos_b) * 0.5 + 2.0, d.team, true, false, true, false):
			var c := e.global_position + Vector3(0.0, 0.9, 0.0)
			if Geometry3D.get_closest_point_to_segment(c, a, b).distance_to(c) <= WIRE_HIT_M + 0.4:
				out.append(e)
		return out
	var wardlings := rec.def != null and rec.def.hits_wardlings
	return world.entities_in_radius(d.pos, rec.def.trigger_radius_m, d.team, true, false, true, wardlings)


func _trigger(rec: Data, victims: Array[Node3D], dmult: float, t: int) -> void:
	var ctx := rec.ctx
	var dmg := ctx.power_param(&"damage") * dmult
	triggers += 1
	rec.hits += 1
	match rec.kind:
		KIND_SNARE:
			var push := ctx.param(&"distance")  # W10-T1 Spring fork: knockback instead of root
			var root := ctx.ticks(&"duration")
			for v in victims:
				world.skill_damage(ctx, v, dmg)
				world.apply_skill_dots(ctx, v)  # Barbed fork: bleed + healing reduction
				_reveal(ctx, v)  # Mastery: snared enemies are revealed to her team
				if push > 0.0 and v is HeroBody:
					_knock_away(ctx, v as HeroBody, rec.d.pos, push)
				elif root > 0:
					world.apply_status(ctx, v, StatusComponent.Kind.ROOT, root, 0.0)
		KIND_WIRE:
			for v in victims:
				world.skill_damage(ctx, v, dmg)
				_reveal(ctx, v)  # Alarm Net: the trigger reveals the enemy to the team
				world.apply_status(ctx, v, StatusComponent.Kind.SLOW, ctx.ticks(&"secondary_duration"), ctx.param(&"slow"))
		KIND_MINE:
			var pull := ctx.param(&"distance")  # W10-T1 Gravity Mine fork: pull radius
			if pull > 0.0:
				_gravity(rec, pull)
			else:
				_explode(rec, dmg)
	# W10-T1: Razor wire (3 triggers) and Mastery mines (2 detonations) survive.
	if rec.kind != KIND_SNARE and rec.hits < roundi(ctx.param(&"count")):
		rec.arm_tick = t + roundi(maxf(ctx.param(&"arm_time"), 0.5) * world.tick_hz)
		return
	rec.d.alive = false
	_chain(rec, t)


## W11-M1: reveals hero `v` to the caster's team for the skill's `reveal` seconds.
func _reveal(ctx: EffectContext, v: Node3D) -> void:
	var secs := ctx.ticks(&"reveal")
	if secs > 0 and v is HeroBody:
		world.reveals.reveal((v as HeroBody).net_id, ctx.team, secs, world.server.tick)


## Pushes `h` `dist` m away from `from` (Snare Coil Spring fork, Flash Bloom style).
func _knock_away(ctx: EffectContext, h: HeroBody, from: Vector3, dist: float) -> void:
	var away := Vector3(h.state.position.x - from.x, 0.0, h.state.position.z - from.z)
	away = away.normalized() if away.length() > 0.05 else -Vector3(ctx.dir.x, 0.0, ctx.dir.z).normalized()
	var n := 9
	var applied := h.combat.status.apply(StatusComponent.Kind.KNOCKBACK, n, 0.0,
		Modifier.source(Modifier.SRC_STATUS, (ctx.caster.net_id << 3) | 6), world.tick())
	if applied > 0:
		h.state.dash_velocity = away * (dist / (n * world.dt)) * h.combat.status.knockback_mult  # Planted
		h.state.dash_ticks = n
		h.state.dash_launch = false


## Gravity Mine: pulls enemies within `radius` m to the centre, then the
## data-authored `gravity_effects` (the blast) go off `secondary_duration` later.
func _gravity(rec: Data, radius: float) -> void:
	var ctx := rec.ctx
	var d := rec.d
	for e in world.entities_in_radius(d.pos, radius, d.team, true, false, true, false):
		var h := e as HeroBody
		var to := Vector3(d.pos.x - h.state.position.x, 0.0, d.pos.z - h.state.position.z)
		var n := 8
		var applied := h.combat.status.apply(StatusComponent.Kind.KNOCKBACK, n, 0.0,
			Modifier.source(Modifier.SRC_STATUS, (ctx.caster.net_id << 3) | 6), world.tick())
		if applied > 0:
			h.state.dash_velocity = to / (n * world.dt) * h.combat.status.knockback_mult  # Planted: pull
			h.state.dash_ticks = n
			h.state.dash_launch = false
	world.extras.schedule(ctx.with_target(null, d.pos), ctx.ticks(&"secondary_duration"), rec.def.gravity_effects)


## Pressure Mine blast: falloff to 40% at the edge, x1.5 vs Wardlings (§4.3).
func _explode(rec: Data, dmg: float) -> void:
	var ctx := rec.ctx
	var d := rec.d
	var r := ctx.param(&"radius")
	var splits := roundi(ctx.param(&"splits"))  # W10-T1 Cluster fork: bomblets (`extra_b` dmg, `radius` m... see data)
	if splits > 0:
		r = ctx.param(&"extra_b")
		dmg = ctx.power_param(&"extra")
	for k in maxi(splits, 1):
		var c := d.pos
		if splits > 0:
			var ang := TAU * k / splits
			c += Vector3(cos(ang), 0.0, sin(ang)) * ctx.param(&"width")
		world.add_fx(FX_PULSE, d.team, c, Vector3(r, 0.0, 0.0), 0.0, roundi(AbilityWorld.BURST_S * world.tick_hz))
		for e in world.entities_in_radius(c, r, d.team, true, false, true, true):
			var f := lerpf(1.0, rec.def.edge_falloff, clampf(_flat(e.global_position, c) / maxf(r, 0.1), 0.0, 1.0))
			var wm := rec.def.wardling_mult if e is WardlingSim else 1.0
			world.skill_damage(ctx, e, dmg * f * wm)


func _chain(rec: Data, t: int) -> void:
	var delay := roundi(rec.def.chain_delay_s * world.tick_hz)
	for dd in data:
		var o: Data = data[dd]
		if o == rec or not o.d.alive or o.kind > KIND_MINE or o.d.owner_id != rec.d.owner_id or o.chain_tick >= 0:
			continue
		if _flat(o.d.pos, rec.d.pos) <= rec.def.link_radius_m:
			o.chain_tick = t + delay
			chains += 1


func _step_dome(rec: Data, t: int) -> void:
	var ctx := rec.ctx
	var d := rec.d
	var r := ctx.param(&"radius")
	var slow := ctx.param(&"slow")
	for e in world.entities_in_radius(d.pos, r + 8.0, d.team, true, false, true, false):
		var h := e as HeroBody
		var id := h.net_id
		var cur := _flat(h.state.position, d.pos) < r
		if rec.inside.has(id) and rec.inside[id] != cur \
				and t - int(rec.last_cross.get(id, -1000)) >= roundi(FENCE_REHIT_S * world.tick_hz):
			rec.last_cross[id] = t
			world.skill_damage(ctx, h, ctx.power_param(&"damage"))
			world.apply_status(ctx, h, StatusComponent.Kind.STUN, ctx.ticks(&"stun"), 0.0)
			world.add_fx(FX_PULSE, d.team, h.state.position, Vector3(1.5, 0.0, 0.0), 0.0, 8)
		rec.inside[id] = cur
		if cur and slow > 0.0:
			world.apply_status(ctx, h, StatusComponent.Kind.SLOW, 3, slow)


func _step_field(rec: Data, t: int) -> void:
	var ctx := rec.ctx
	if ctx.param(&"count") > 0.0 and ctx.caster != null and not ctx.caster.combat.dead:
		rec.d.pos = ctx.caster.state.position  # W10-T1 Mastery: the field moves with Hex
		if rec.d.fx != null:
			rec.d.fx.pos = rec.d.pos
	if ctx.param(&"scramble") > 0.0:  # Blackout fork: enemy heroes inside are Scrambled
		for e in world.entities_in_radius(rec.d.pos, rec.d.radius, rec.d.team, true, false, true, false):
			scramble(e as HeroBody, 3)
	if ctx.param(&"dr") > 0.0:  # Firewall fork: allied Wardlings inside take less damage
		for e in world.entities_in_radius(rec.d.pos, rec.d.radius, rec.d.team, false, true, false, true):
			MinionmancerHooks.apply_squad_modifier(e as WardlingSim, &"damage_taken", 1.0 - ctx.param(&"dr"), t + 2, rec.d.source_id)
	var linger := roundi(FIELD_LINGER_S * world.tick_hz)
	for g in gadgets_in_radius(rec.d.pos, rec.d.radius, rec.d.team):
		hack(g, linger, 0, true)


func _step_pending(t: int) -> void:
	for id in pending.keys():
		if t >= int(pending[id][1]):
			_drop_pending(id)


func _drop_pending(id: int) -> void:
	if pending.has(id):
		world._remove_fx(pending[id][2])
		pending.erase(id)


func _step_hacks(t: int) -> void:
	for g in hacks.keys():
		var rec: Array = hacks[g]
		if not is_instance_valid(g) or (g is AbilityWorld.Deployable and not (g as AbilityWorld.Deployable).alive) \
				or (g is WardlingSim and (g as WardlingSim).dead) or t >= int(rec[1]):
			_clear_hack(g)
			continue
		var fx: AbilityWorld.Fx = rec[2]
		if fx != null:
			fx.pos = _pos_of(g)
			if t >= int(rec[0]):
				world._remove_fx(fx)
				rec[2] = null
	for s in scramble_until.keys():
		if not is_instance_valid(s) or world.tick() >= int(scramble_until[s]):
			scramble_until.erase(s)


func _clear_hack(g: Object) -> void:
	var rec: Array = hacks.get(g, [])
	if not rec.is_empty() and rec[2] != null:
		world._remove_fx(rec[2])
	hacks.erase(g)


func _team_of(g: Object) -> int:
	if g is AbilityWorld.Deployable:
		return (g as AbilityWorld.Deployable).team
	return int((g as WardlingSim).team)


func _pos_of(g: Object) -> Vector3:
	if g is AbilityWorld.Deployable:
		return (g as AbilityWorld.Deployable).pos + Vector3(0.0, 2.2, 0.0)
	return (g as WardlingSim).global_position + Vector3(0.0, 2.4, 0.0)


func _size_of(g: Object) -> float:
	return 1.0 if g is AbilityWorld.Deployable else 0.8


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
