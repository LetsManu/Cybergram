class_name AbilityWorld
extends RefCounted
## Server-side ability executor (ADR-0004 EffectExecutor + architecture.md §7.2
## SpawnEntity/Motion): owns the live skill entities (deployables, skill
## projectiles, charges, leaps) and the replicated skill FX list, and is the
## only place effects touch the world. Owned by ServerWorld:
##   per hero: pre_move (stats/status expiry, move-speed scale) -> HeroMotor ->
##             post_move (charge contact, AbilityRunner.process)
##   per tick: step (deployables, projectiles, leaps, zone passives, FX expiry)
## Implements the M1 kits of design/gdd/heroes.md §4.1 (Vesper Loom) and §4.5
## (Brannoc) at Unlock level.

## Replicated FX kinds (SnapshotData.FxState.kind).
const FX_WALL: int = 1
const FX_BEACON: int = 2
const FX_BASTION: int = 3
const FX_THREAD: int = 4
const FX_CIRCLE: int = 5    # cast / landing telegraph (radius in pos2.x)
const FX_TRAIL: int = 6     # line pos -> pos2 (Threadstep trail)
const FX_BURST: int = 7     # one-shot ring (slam, Rewrite)
const FX_ARROW: int = 8     # charge wind-up / path pos -> pos2

## PLACEHOLDER. Beacon hit capsule (m).
const BEACON_RADIUS_M: float = 0.45
const BEACON_HEIGHT_M: float = 1.6
## PLACEHOLDER. FX lifetime of one-shot bursts (s).
const BURST_S: float = 0.6


class Deployable:
	var id: int = 0
	var kind: int = 0
	var team: int = 0
	var owner_id: int = 0
	var skill: SkillInstance
	var ends_active: bool = false
	var pos: Vector3
	var yaw: float = 0.0
	var width: float = 0.0
	var height: float = 0.0
	var thickness: float = 0.4
	var radius: float = 0.0
	var hp: float = 0.0
	var max_hp: float = 0.0
	var expires_tick: int = 0
	var heal_per_s: float = 0.0
	var hero_heal_per_s: float = 0.0
	var dr: float = 0.0
	var alive: bool = true
	var fx: Fx
	var source_id: int = 0
	var absorbed: float = 0.0


class Projectile:
	var pos: Vector3
	var dir: Vector3
	var speed: float
	var left: float
	var team: int
	var hit_radius: float
	var ctx: EffectContext
	var on_hit: Array
	var fx: Fx


class Fx:
	var id: int = 0
	var kind: int = 0
	var team: int = 0
	var pos: Vector3
	var pos2: Vector3
	var yaw: float = 0.0
	## 0..1 (deployable HP fraction, cast progress...).
	var param: float = 1.0
	var start_tick: int = 0
	var expires_tick: int = 0
	## Follows this hero's feet while alive (cast telegraphs).
	var follow: HeroBody


class Charge:
	var hero: HeroBody
	var ctx: EffectContext
	var dir: Vector3
	var speed: float
	var ticks_left: int
	var total: int
	var damage: float
	var bonus: float
	var stun_ticks: int
	var knock_speed: float
	var knock_ticks: int
	var half_width: float
	var carried: HeroBody
	var knocked: Dictionary = {}
	var last_pos: Vector3
	var mask: int
	var pinned: bool = false
	var fx: Fx


class Leap:
	var hero: HeroBody
	var ctx: EffectContext
	var land: Vector3
	var land_tick: int
	var on_land: Array
	var fx: Fx


var server: ServerWorld
var tick_hz: int
var dt: float
var deployables: Array[Deployable] = []
var projectiles: Array[Projectile] = []
var fx: Array[Fx] = []
var charges: Array[Charge] = []
var leaps: Array[Leap] = []
## Wave-9 kits (Ryker / Liora / Sable): grenades, drones, stealth... (SkillEntities).
var extras: SkillEntities
## Debug (--grant-ult): heroes spawned from now on may cast their ultimate.
var grant_ult: bool = false
## Diagnostics / tests.
var blocked_shots: int = 0
var pins: int = 0

var _next_id: int = 1
var _ray := PhysicsRayQueryParameters3D.new()
var _cast_fx: Dictionary = {}  # HeroCombat -> Fx
var _blocker_set: bool = false
## W9-H2: traps, fields, hacks (Juniper Quill / Hex); stepped from step().
var traps: TrapWorld
## W11-M1: heroes revealed to a team through walls.
var reveals := RevealSet.new()
## Hero whose hitscan was just clipped by a deployable (Hex gadget bonus).
var _shooter: HeroBody


func _init(world: ServerWorld) -> void:
	server = world
	tick_hz = world.net.tick_rate_hz
	dt = world.dt
	_ray.collision_mask = HeroBody.LAYER_WORLD
	traps = TrapWorld.new(self)
	extras = SkillEntities.new(world)


func tick() -> int:
	return server.tick


# --- Per hero ------------------------------------------------------------------

## Before HeroMotor: expire timed stats / statuses, write the move-speed scale.
func pre_move(h: HeroBody) -> void:
	var c := h.combat
	if grant_ult:
		c.abilities.debug_grant_ult = true
	c.stats.expire(server.tick)
	c.status.step(server.tick)
	_tick_bleed(h)
	_zone_passive(h)
	# Ratio against the block's own base (f32), so an unmodified hero is exactly 1.
	var base := maxf(0.01, c.stats.get_base(StatCatalog.MOVE_SPEED))
	h.state.speed_scale = c.stats.get_value(StatCatalog.MOVE_SPEED) / base


## After HeroMotor: charge contact, then skill activation from `cmd`.
func post_move(h: HeroBody, cmd: InputCommand) -> void:
	for ch in charges:
		if ch.hero == h:
			_step_charge(ch)
			break
	extras.post_move(h, cmd)
	h.combat.abilities.process(h, cmd, server.tick, self)


# --- Per tick ------------------------------------------------------------------

func step() -> void:
	var t := server.tick
	_shooter = null
	_ensure_bolt_blocker()
	for i in range(deployables.size() - 1, -1, -1):
		var d := deployables[i]
		if not d.alive or t >= d.expires_tick or d.hp <= 0.0 and d.max_hp > 0.0:
			_end_deployable(d)
			deployables.remove_at(i)
			continue
		_tick_deployable(d, t)
	traps.step()
	reveals.step(t)
	_step_projectiles()
	extras.step()
	for i in range(leaps.size() - 1, -1, -1):
		var lp := leaps[i]
		if lp.hero.combat.dead:
			_remove_fx(lp.fx)
			leaps.remove_at(i)
		elif t >= lp.land_tick:
			leaps.remove_at(i)
			_land(lp)
	for i in range(charges.size() - 1, -1, -1):
		if charges[i].hero.combat.dead:
			_end_charge(charges[i])
	for i in range(fx.size() - 1, -1, -1):
		var f := fx[i]
		if f.follow != null and is_instance_valid(f.follow):
			f.pos = f.follow.state.position
		if t >= f.expires_tick:
			fx.remove_at(i)


# --- Queries --------------------------------------------------------------------

## Floor point aimed at from `origin` along `dir`, at most `range_m` away.
func ground_point(origin: Vector3, dir: Vector3, range_m: float) -> Vector3:
	var space := server.get_world_3d().direct_space_state
	_ray.from = origin
	_ray.to = origin + dir * range_m
	var r := space.intersect_ray(_ray)
	var p: Vector3 = r.position - dir * 0.3 if not r.is_empty() else _ray.to
	_ray.from = p + Vector3.UP * 0.5
	_ray.to = p + Vector3.DOWN * 40.0
	var down := space.intersect_ray(_ray)
	return down.position if not down.is_empty() else Vector3(p.x, origin.y - 1.6, p.z)


## Live heroes and Wardlings within `radius` (flat, ±4 m vertical) of `center`.
func entities_in_radius(center: Vector3, radius: float, team: int, enemies: bool, allies: bool,
		heroes: bool, wardlings: bool) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var r2 := radius * radius
	if heroes:
		for id in server.registry.ids():
			var h := server.registry.get_node_by_id(id) as HeroBody
			if h == null or h.combat == null or h.combat.dead:
				continue
			var mine := h.combat.team == team
			if (mine and allies) or (not mine and enemies):
				if _flat2(h.state.position, center) <= r2 and absf(h.state.position.y - center.y) <= 4.0:
					out.append(h)
	if wardlings and server.wardlings != null:
		for w in server.wardlings.wardlings:
			if w.dead:
				continue
			var mine := w.team == team
			if (mine and allies) or (not mine and enemies):
				if _flat2(w.global_position, center) <= r2 and absf(w.global_position.y - center.y) <= 4.0:
					out.append(w)
	return out


## The caster's own (or conducted) Wardling closest to the crosshair, within
## `range_m` and the cone, with line of sight. Null if none.
func aimed_ally_wardling(h: HeroBody, origin: Vector3, dir: Vector3, range_m: float, cone: float) -> WardlingSim:
	var ww := server.wardlings
	if ww == null:
		return null
	var cands: Array[WardlingSim] = []
	var sq := ww.squad_of(h.net_id)
	if sq != null:
		cands.append_array(sq.members)
	for wave in MinionmancerHooks.conducted_waves(ww, h):
		cands.append_array(wave.members)
	var best: WardlingSim = null
	var best_a := cone
	for w in cands:
		if w.dead:
			continue
		var to := w.chest() - origin
		var d := to.length()
		if d > range_m or d < 0.01:
			continue
		var a := dir.angle_to(to / d)
		if a <= best_a and ww.has_los(origin, w.chest()):
			best_a = a
			best = w
	return best


## Nearest enemy deployable (wall or beacon) on the ray within `limit`:
## [distance, Deployable], or [] if none. Allies' deployables never block.
func block_distance(origin: Vector3, dir: Vector3, limit: float, shooter_team: int) -> Array:
	var best: Deployable = null
	var best_t := limit
	for d in deployables:
		if not d.alive or d.team == shooter_team:
			continue
		var t := -1.0
		if d.kind >= TrapWorld.KIND_BASE:
			t = traps.ray(origin, dir, d)
		elif traps.is_down(d):
			continue  # W9-H2: a hacked wall / beacon does not block
		elif d.kind == DeployableEffectDef.Kind.WALL:
			t = _ray_wall(origin, dir, d)
		elif d.kind == DeployableEffectDef.Kind.BEACON:
			t = HitscanTracer.ray_vertical_capsule(origin, dir, d.pos.y + BEACON_RADIUS_M,
				d.pos.y + BEACON_HEIGHT_M - BEACON_RADIUS_M, Vector2(d.pos.x, d.pos.z), BEACON_RADIUS_M)
		if t >= 0.0 and t <= best_t:
			best_t = t
			best = d
	return [best_t, best] if best != null else []


## Damage to a deployable (blocked shots, skills). Returns the HP removed.
func damage_deployable(d: Deployable, amount: float, src: HeroBody = null) -> float:
	var who := src if src != null else _shooter
	_shooter = null
	if not d.alive or d.max_hp <= 0.0:
		return 0.0
	if who != null and who.combat != null and who.combat.def != null:
		amount *= who.combat.def.gadget_damage_mult  # Hex Signal Sight (+50% vs gadgets)
	var a := minf(maxf(amount, 0.0), d.hp)
	d.hp -= a
	d.absorbed += a
	return a


## Hitscan pellet helper for ServerWorld._fire: the pellet's range clipped by
## an enemy deployable. Returns [limit, Deployable or null].
func clip_shot(origin: Vector3, dir: Vector3, range_m: float, shooter_team: int) -> Array:
	var b := block_distance(origin, dir, range_m, shooter_team)
	_shooter = null
	if b.is_empty():
		return [range_m, null]
	_shooter = _hero_at_eye(origin, shooter_team)
	return [b[0], b[1]]


## The hero of `team` whose eye is at `origin` (identifies a hitscan shooter).
func _hero_at_eye(origin: Vector3, team: int) -> HeroBody:
	for id in server.registry.ids():
		var h := server.registry.get_node_by_id(id) as HeroBody
		if h != null and h.combat != null and h.combat.team == team \
				and h.state.position.distance_squared_to(origin - Vector3(0.0, h.eye_height(), 0.0)) < 0.0025:
			return h
	return null


func deployable_of(skill: SkillInstance) -> Deployable:
	for d in deployables:
		if d.alive and d.skill == skill:
			return d
	return null


## Replicated status bits of a hero (StatusComponent.BIT_*).
func status_bits(h: HeroBody) -> int:
	var c := h.combat
	var b := c.status.visual_bits()
	if c.abilities.is_casting():
		b |= StatusComponent.BIT_CASTING
	if c.abilities.is_dashing():
		b |= StatusComponent.BIT_DASHING
	return b | extras.status_bits(h)


# --- Effect execution --------------------------------------------------------------

## Skill damage (SKILL type; 100% vs Wardlings, heroes.md §3.8). Returns HP removed.
func skill_damage(ctx: EffectContext, target: Node3D, amount: float) -> float:
	var c := ctx.caster.combat
	var info := DamageInfo.make(amount * c.stats.get_value(StatCatalog.DAMAGE_DEALT), ctx.caster.net_id, ctx.team,
		0, DamageInfo.Type.SKILL)
	var applied := 0.0
	var killed := false
	var at := WardlingWorld.feet_of(target) + Vector3(0.0, 1.2, 0.0)
	if target is HeroBody:
		var h := target as HeroBody
		if h.combat.team == ctx.team or h.combat.dead:
			return 0.0
		applied = server.damage_hero(h, info)
		killed = h.combat.dead
	elif target is WardlingSim and server.wardlings != null:
		var w := target as WardlingSim
		if w.team == ctx.team:
			return 0.0
		applied = server.wardlings.damage_wardling(w, info)
		killed = w.dead
	server.skill_hit_feedback(ctx.caster, int(target.get("net_id")), applied, killed, at)
	return applied


func apply_status(ctx: EffectContext, target: Node3D, kind: int, ticks: int, magnitude: float) -> int:
	var src := Modifier.source(Modifier.SRC_STATUS, (ctx.caster.net_id << 3) | (ctx.skill.slot if ctx.skill != null else 7))
	if target is HeroBody:
		var h := target as HeroBody
		if h.combat.dead:
			return 0
		if h != ctx.caster and h.combat.team == ctx.team and StatusComponent.is_hard_cc(kind):
			return 0
		return h.combat.status.apply(kind, ticks, magnitude, src, server.tick, ctx.caster.net_id)
	if target is WardlingSim and kind == StatusComponent.Kind.STUN and server.wardlings != null:
		MinionmancerHooks.stun(target as WardlingSim, server.tick + ticks)
		return ticks
	return 0


## W11-M1: the skill's damage-over-time and healing-reduction params applied to
## `target` (Barbed Coil: `bleed` total HP over `bleed_time`, `heal_cut` fraction
## for `heal_cut_time`). No-ops when the params are 0.
func apply_skill_dots(ctx: EffectContext, target: Node3D) -> void:
	var bt := ctx.ticks(&"bleed_time")
	var total := ctx.power_param(&"bleed")
	if total > 0.0 and bt > 0:
		apply_status(ctx, target, StatusComponent.Kind.BLEED, bt, total / (bt / float(tick_hz)))
	var ct := ctx.ticks(&"heal_cut_time")
	var cut := ctx.param(&"heal_cut")
	if cut > 0.0 and ct > 0:
		apply_status(ctx, target, StatusComponent.Kind.HEAL_CUT, ct, cut)


## Deals this tick's bleed of `h` (true damage; whole HP chunks so the feed is not spammed).
func _tick_bleed(h: HeroBody) -> void:
	var c := h.combat
	if c.dead:
		return
	for e in c.status.entries:
		if e.kind != StatusComponent.Kind.BLEED:
			continue
		e.carry += e.magnitude * dt
		var last := server.tick + 1 >= e.expires_tick
		if e.carry >= 1.0 or (last and e.carry > 0.0):
			var amount := e.carry
			e.carry = 0.0
			server.damage_hero(h, DamageInfo.make(amount, e.attacker_id, 1 - c.team, 0, DamageInfo.Type.TRUE))
			if c.dead:
				return


func spawn_deployable(ctx: EffectContext, def: DeployableEffectDef) -> Deployable:
	if traps.field_blocks(ctx.team, ctx.point):
		return null  # W9-H2: enemy Static Field forbids placing
	var t := server.tick
	if def.kind == DeployableEffectDef.Kind.BEACON:
		# heroes.md: one beacon (two with Mastery: `max_placed` param, W10-T1).
		var cap := maxi(1, roundi(ctx.param(&"max_placed")))
		var mine: Array[Deployable] = []
		for e in deployables:
			if e.alive and e.skill == ctx.skill and e.kind == DeployableEffectDef.Kind.BEACON:
				mine.append(e)
		if mine.size() >= cap:
			mine[0].alive = false
	var d := Deployable.new()
	d.id = _next_id
	_next_id += 1
	d.kind = def.kind
	d.team = ctx.team
	d.owner_id = ctx.caster.net_id
	d.skill = ctx.skill
	d.ends_active = def.ends_active
	d.pos = ctx.point
	d.yaw = ctx.yaw
	d.width = ctx.param(def.width_param)
	d.height = ctx.param(def.height_param)
	d.thickness = def.thickness_m
	d.radius = ctx.param(def.radius_param)
	d.max_hp = ctx.param(def.hp_param) if def.kind != DeployableEffectDef.Kind.BASTION else 0.0
	d.hp = d.max_hp
	d.heal_per_s = ctx.power_param(def.heal_param)
	d.hero_heal_per_s = ctx.power_param(&"ally_heal")
	d.dr = ctx.param(def.dr_param)
	d.expires_tick = t + ctx.ticks(def.duration_param)
	d.source_id = Modifier.source(Modifier.SRC_ZONE, 0x800000 | d.id)
	var kind := FX_WALL
	var size := Vector3(d.width, d.height, d.thickness)
	if def.kind == DeployableEffectDef.Kind.BEACON:
		kind = FX_BEACON
		size = Vector3(d.radius, 0.0, 0.0)
	elif def.kind == DeployableEffectDef.Kind.BASTION:
		kind = FX_BASTION
		size = Vector3(d.radius, 0.0, 0.0)
	d.fx = add_fx(kind, d.team, d.pos, size, d.yaw, d.expires_tick - t)
	deployables.append(d)
	return d


func launch_projectile(ctx: EffectContext, speed: float, range_m: float, hit_radius: float, on_hit: Array) -> void:
	var p := Projectile.new()
	p.pos = ctx.origin
	p.dir = ctx.dir.normalized()
	p.speed = speed
	p.team = ctx.team
	p.hit_radius = hit_radius
	p.ctx = ctx
	p.on_hit = on_hit
	var space := server.get_world_3d().direct_space_state
	_ray.from = p.pos
	_ray.to = p.pos + p.dir * range_m
	var r := space.intersect_ray(_ray)
	p.left = p.pos.distance_to(r.position) if not r.is_empty() else range_m
	p.fx = add_fx(FX_THREAD, p.team, p.pos, p.pos, ctx.yaw, ceili(p.left / maxf(speed, 1.0) * tick_hz) + 2)
	projectiles.append(p)


func start_charge(ctx: EffectContext, def: ChargeEffectDef) -> void:
	var h := ctx.caster
	var n := maxi(1, roundi(ctx.param(def.duration_param) * tick_hz))
	var ch := Charge.new()
	ch.hero = h
	ch.ctx = ctx
	ch.dir = Vector3(ctx.dir.x, 0.0, ctx.dir.z).normalized()
	ch.speed = ctx.param(def.distance_param) / (n * dt)
	ch.ticks_left = n
	ch.total = n
	ch.damage = ctx.power_param(def.damage_param)
	ch.bonus = ctx.power_param(def.bonus_param)
	ch.stun_ticks = ctx.ticks(def.stun_param)
	ch.knock_speed = def.knock_speed
	ch.knock_ticks = maxi(1, roundi(def.knock_s * tick_hz))
	ch.half_width = def.path_half_width_m
	ch.last_pos = h.state.position
	ch.mask = h.collision_mask
	# Charges pass through bodies; contact is resolved by _step_charge.
	h.collision_mask = HeroBody.LAYER_WORLD | HeroBody.LAYER_EDGE_BLOCK
	h.state.dash_velocity = ch.dir * ch.speed
	h.state.dash_ticks = n
	h.state.dash_launch = false
	h.combat.abilities.dash_until_tick = server.tick + n + 1
	ch.fx = add_fx(FX_ARROW, ctx.team, h.state.position, h.state.position + ch.dir * ctx.param(def.distance_param),
		ctx.yaw, n + 1)
	charges.append(ch)


func start_leap(ctx: EffectContext, def: LeapEffectDef) -> void:
	var h := ctx.caster
	var n := maxi(1, roundi(ctx.param(def.time_param) * tick_hz))
	var from := h.state.position
	var flat := Vector3(ctx.point.x - from.x, 0.0, ctx.point.z - from.z)
	var g := h.movement_def().gravity
	var vy := ((ctx.point.y - from.y) + g * dt * dt * n * (n - 1) / 2.0) / (n * dt)
	h.state.dash_velocity = Vector3(flat.x / (n * dt), vy, flat.z / (n * dt))
	h.state.dash_ticks = n
	h.state.dash_launch = true
	h.combat.abilities.dash_until_tick = server.tick + n + 1
	var lp := Leap.new()
	lp.hero = h
	lp.ctx = ctx
	lp.land = ctx.point
	lp.land_tick = server.tick + n
	lp.on_land = def.on_land
	# heroes.md: the landing marker is visible to enemies for the whole leap.
	lp.fx = add_fx(FX_CIRCLE, ctx.team, ctx.point, Vector3(ctx.param(def.marker_radius_param), 0.0, 0.0), 0.0, n + 1)
	leaps.append(lp)


## Marionette Thread focus: own squad (issue_command) and conducted waves
## (command_vanguard) attack `target` for `ticks`.
func wardling_focus(ctx: EffectContext, target: Node3D, ticks: int) -> void:
	var ww := server.wardlings
	if ww == null:
		return
	var id := int(target.get("net_id"))
	MinionmancerHooks.skill_attack(ww, ctx.caster, id, ticks)
	for wave in MinionmancerHooks.conducted_waves(ww, ctx.caster):
		MinionmancerHooks.command_vanguard_attack(ww, wave, id, ticks)


func swap_with(ctx: EffectContext, w: Node3D, trail_s: float) -> void:
	var h := ctx.caster
	var a := h.state.position
	var b := WardlingWorld.feet_of(w)
	teleport(h, b + Vector3(0.0, 0.05, 0.0))
	if w is WardlingSim and server.wardlings != null:
		var ws := w as WardlingSim
		ws.global_position = server.wardlings.snap(a)
		ws.path = PackedVector3Array()
	add_fx(FX_TRAIL, ctx.team, a, b, ctx.yaw, roundi(trail_s * tick_hz))


func rewrite(ctx: EffectContext, radius: float, elite_ticks: int, turned_ticks: int) -> void:
	var c := ctx.caster.state.position
	add_fx(FX_BURST, ctx.team, c, Vector3(radius, 0.0, 0.0), 0.0, roundi(BURST_S * 2.0 * tick_hz))
	if server.wardlings != null:
		MinionmancerHooks.rewrite_area(server.wardlings, ctx.caster, c, radius, elite_ticks, turned_ticks)


func order_squad_to_deployable(ctx: EffectContext) -> void:
	var d := deployable_of(ctx.skill)
	if d == null or server.wardlings == null:
		return
	var hp := _hardpoint_at(d.pos)
	MinionmancerHooks.order_at(server.wardlings, ctx.caster, d.pos, hp)


## Cast telegraph (art bible §8.2: shown for the whole cast in the caster's colour).
func cast_started(ctx: EffectContext, ticks: int) -> void:
	var d := ctx.skill.def
	var f: Fx
	if d.targeting == SkillDef.TargetMode.DIRECTION:
		var dir := Basis(Vector3.UP, ctx.yaw) * Vector3.FORWARD
		var dist := maxf(ctx.param(&"distance"), 4.0)
		f = add_fx(FX_ARROW, ctx.team, ctx.caster.state.position, ctx.caster.state.position + dir * dist, ctx.yaw, ticks)
	else:
		var r := maxf(ctx.param(&"radius"), 2.0)
		var at := ctx.point if d.targeting == SkillDef.TargetMode.GROUND else ctx.caster.state.position
		f = add_fx(FX_CIRCLE, ctx.team, at, Vector3(r, 0.0, 0.0), 0.0, ticks)
		if d.targeting == SkillDef.TargetMode.SELF:
			f.follow = ctx.caster
	_cast_fx[ctx.caster.combat] = f


func clear_cast_fx(c: HeroCombat) -> void:
	var f: Fx = _cast_fx.get(c)
	if f != null:
		_remove_fx(f)
		_cast_fx.erase(c)


func add_fx(kind: int, team: int, pos: Vector3, pos2: Vector3, yaw: float, ticks: int) -> Fx:
	var f := Fx.new()
	f.id = _next_id
	_next_id = (_next_id % 65535) + 1
	f.kind = kind
	f.team = team
	f.pos = pos
	f.pos2 = pos2
	f.yaw = yaw
	f.start_tick = server.tick
	f.expires_tick = server.tick + maxi(ticks, 1)
	fx.append(f)
	return f


## Moves a hero instantly (swaps, carries); rebuilds the body contact state.
func teleport(h: HeroBody, pos: Vector3) -> void:
	h.state.position = pos
	h.state.velocity = Vector3.ZERO
	h.motor.restore(h.state)


# --- Snapshot ---------------------------------------------------------------------

func write_snapshot(s: SnapshotData) -> void:
	var t := server.tick
	for f in fx:
		var e := SnapshotData.FxState.new()
		e.id = f.id
		e.kind = f.kind
		e.team = f.team
		e.position = f.pos
		e.position2 = f.pos2
		e.yaw = f.yaw
		e.param = f.param
		e.ticks_left = maxi(f.expires_tick - t, 0)
		s.fx.append(e)


## Own-hero skill HUD fields (cooldowns, flags, statuses).
func fill_own(o: SnapshotData.OwnCombat, c: HeroCombat) -> void:
	var t := server.tick
	for slot in 4:
		var st := c.abilities.hud_state(slot, t)
		o.skill_cd_left[slot] = st[0]
		o.skill_cd_total[slot] = st[1]
		o.skill_flags[slot] = st[2]
	o.shield = ceili(c.health.shield)
	o.level = c.level


# --- Internals -------------------------------------------------------------------

func _ensure_bolt_blocker() -> void:
	if _blocker_set or server.wardlings == null:
		return
	server.wardlings.projectiles.blocker = _block_bolt
	_blocker_set = true


## ProjectileSystem blocker: a Wardling bolt meets an enemy wall / beacon.
func _block_bolt(from: Vector3, dir: Vector3, seg: float, team: int, damage: float) -> float:
	_shooter = null
	var b := block_distance(from, dir, seg, team)
	if b.is_empty():
		return -1.0
	damage_deployable(b[1], damage)
	blocked_shots += 1
	return b[0]


func _tick_deployable(d: Deployable, t: int) -> void:
	if d.fx != null:
		d.fx.param = d.hp / d.max_hp if d.max_hp > 0.0 else 1.0
	if d.kind >= TrapWorld.KIND_BASE or traps.is_down(d):
		return  # traps are TrapWorld's; hacked beacons / bastions are off
	match d.kind:
		DeployableEffectDef.Kind.BEACON:
			if d.hero_heal_per_s > 0.0:  # W10-T1 Bastion fork: also heals allied heroes
				for e in entities_in_radius(d.pos, d.radius, d.team, false, true, true, false):
					(e as HeroBody).combat.health.heal(d.hero_heal_per_s * dt, d.source_id)
			if server.wardlings != null:
				for e in entities_in_radius(d.pos, d.radius, d.team, false, true, false, true):
					var w := e as WardlingSim
					w.health.heal(d.heal_per_s * dt)
					MinionmancerHooks.apply_squad_modifier(w, &"damage_taken", 1.0 - d.dr, t + 2, d.source_id)
		DeployableEffectDef.Kind.BASTION:
			for e in entities_in_radius(d.pos, d.radius, d.team, false, true, true, false):
				var h := e as HeroBody
				h.combat.status.apply(StatusComponent.Kind.DR, 2, d.dr, d.source_id, t)


func _end_deployable(d: Deployable) -> void:
	d.alive = false
	traps.on_end(d)
	_remove_fx(d.fx)
	if d.ends_active and d.skill != null:
		var owner := server.hero(d.owner_id)
		if owner != null and owner.combat != null:
			owner.combat.abilities.end_active(d.skill, server.tick)


func _step_projectiles() -> void:
	var i := 0
	while i < projectiles.size():
		var p := projectiles[i]
		var seg := minf(p.speed * dt, p.left)
		var best_t := seg
		var best: Node3D = null
		var wall := block_distance(p.pos, p.dir, seg, p.team)
		var blocked := not wall.is_empty()
		if blocked:
			best_t = wall[0]
		for e in entities_in_radius(p.pos + p.dir * seg * 0.5, seg * 0.5 + 2.0, p.team, true, false, true, true):
			var t := _ray_body(p.pos, p.dir, e, p.hit_radius)
			if t >= 0.0 and t <= best_t:
				best_t = t
				best = e
				blocked = false
		if best != null:
			var at := p.pos + p.dir * best_t
			p.ctx.with_target(best, at).run(p.on_hit)
			_remove_fx(p.fx)
			projectiles.remove_at(i)
			continue
		if blocked:
			if traps.projectile_hit_deployable(p.ctx, wall[1], p.on_hit):
				_remove_fx(p.fx)
				projectiles.remove_at(i)
				continue
			damage_deployable(wall[1], p.ctx.power_param(&"damage"))
			_remove_fx(p.fx)
			projectiles.remove_at(i)
			continue
		var tail := p.pos
		p.pos += p.dir * seg
		p.left -= seg
		if p.fx != null:
			p.fx.pos = p.pos
			p.fx.pos2 = tail
		if p.left <= 0.001:
			_remove_fx(p.fx)
			projectiles.remove_at(i)
			continue
		i += 1


func _ray_body(o: Vector3, d: Vector3, e: Node3D, pad: float) -> float:
	if e is HeroBody:
		var h := e as HeroBody
		var hd := h.combat.def
		var r := hd.body_radius * hd.hitbox_scale + pad
		var f := h.state.position
		return HitscanTracer.ray_vertical_capsule(o, d, f.y + r, f.y + maxf(hd.head_center_m * hd.hitbox_scale, r),
			Vector2(f.x, f.z), r)
	var w := e as WardlingSim
	var p := w.global_position
	var wr := w.def.radius + pad
	return HitscanTracer.ray_vertical_capsule(o, d, p.y + wr, p.y + maxf(w.def.height - wr, wr), Vector2(p.x, p.z), wr)


func _step_charge(ch: Charge) -> void:
	var h := ch.hero
	if h.combat.dead or ch.pinned:
		_end_charge(ch)
		return
	ch.ticks_left -= 1
	var pos := h.state.position
	var moved := Vector2(pos.x - ch.last_pos.x, pos.z - ch.last_pos.z).length()
	ch.last_pos = pos
	var expected := ch.speed * dt
	var rb := h.combat.def.body_radius * h.combat.def.hitbox_scale
	# The first enemy hero met is carried; once carrying, others in the path
	# are knocked aside (heroes.md §4.5); Wardlings are always shoved aside.
	for e in entities_in_radius(pos, 4.0, ch.ctx.team, true, false, true, true):
		if ch.pinned or not charges.has(ch):
			break
		var rel := WardlingWorld.feet_of(e) - pos
		var along := rel.x * ch.dir.x + rel.z * ch.dir.z
		var lat := Vector2(rel.x - ch.dir.x * along, rel.z - ch.dir.z * along).length()
		if e is HeroBody:
			var t := e as HeroBody
			if t == ch.carried:
				continue
			var rt := t.combat.def.body_radius * t.combat.def.hitbox_scale
			if ch.carried == null:
				if along > -0.3 and along <= rb + rt + 0.5 and lat <= rb + rt:
					_carry(ch, t)
			elif along > 0.0 and along <= 2.5 and lat <= ch.half_width and not ch.knocked.has(t):
				_knock(ch, t, rel, along)
		elif e is WardlingSim and along > 0.0 and along <= 2.0 and lat <= ch.half_width:
			var w := e as WardlingSim
			var side := _side(ch.dir, rel, along)
			w.global_position = server.wardlings.snap(w.global_position + side * 1.5)
	if not charges.has(ch):
		return
	if ch.carried != null and not ch.pinned:
		var t := ch.carried
		var rt := t.combat.def.body_radius * t.combat.def.hitbox_scale
		var gap := rb + rt + 0.1
		var chest := pos + Vector3(0.0, 1.0, 0.0)
		var space := h.get_world_3d().direct_space_state
		_ray.from = chest
		_ray.to = chest + ch.dir * (gap + rt + 0.1)
		var r := space.intersect_ray(_ray)
		var blocked := moved < expected * 0.5 and ch.total - ch.ticks_left > 1
		if not r.is_empty() or blocked:
			var at := pos + ch.dir * gap
			if not r.is_empty():
				var hit: Vector3 = r.position
				at = Vector3(hit.x, pos.y, hit.z) - ch.dir * (rt + 0.05)
			teleport(t, at)
			_pin(ch)
			return
		teleport(t, pos + ch.dir * gap)
	elif moved < expected * 0.3 and ch.total - ch.ticks_left > 1:
		_end_charge(ch)  # ran into a wall with nobody to pin
		return
	if ch.ticks_left <= 0:
		_end_charge(ch)


func _carry(ch: Charge, t: HeroBody) -> void:
	skill_damage(ch.ctx, t, ch.damage)
	if t.combat.dead:
		return
	# Carry = forced movement (knockback type: Anchor / CC immunity resist it).
	var ticks := t.combat.status.apply(StatusComponent.Kind.KNOCKBACK, ch.ticks_left + 1, 0.0,
		Modifier.source(Modifier.SRC_STATUS, ch.hero.net_id << 3 | 1), server.tick)
	if ticks > 0:
		ch.carried = t
	else:
		_end_charge(ch)  # immovable: the charge stops on him


func _knock(ch: Charge, t: HeroBody, rel: Vector3, along: float) -> void:
	ch.knocked[t] = true
	var ticks := t.combat.status.apply(StatusComponent.Kind.KNOCKBACK, ch.knock_ticks, 0.0,
		Modifier.source(Modifier.SRC_STATUS, ch.hero.net_id << 3 | 2), server.tick)
	if ticks <= 0:
		return
	var side := _side(ch.dir, rel, along)
	t.state.dash_velocity = side * ch.knock_speed
	t.state.dash_ticks = ticks
	t.state.dash_launch = false


func _pin(ch: Charge) -> void:
	ch.pinned = true
	pins += 1
	var t := ch.carried
	skill_damage(ch.ctx, t, ch.bonus)
	t.combat.status.remove_source(Modifier.source(Modifier.SRC_STATUS, ch.hero.net_id << 3 | 1))
	if not t.combat.dead:
		apply_status(ch.ctx, t, StatusComponent.Kind.STUN, ch.stun_ticks, 0.0)
	add_fx(FX_BURST, ch.ctx.team, t.state.position, Vector3(1.5, 0.0, 0.0), 0.0, roundi(BURST_S * tick_hz))
	var refund := ch.ctx.param(&"extra_b")  # W10-T1 Ram Charge Mastery: pinning a hero refunds cooldown
	var rs := ch.ctx.skill
	if refund > 0.0 and rs != null:
		rs.cooldown_end_tick -= roundi(rs.cooldown_total_ticks * minf(refund, 1.0))
	_end_charge(ch)


func _end_charge(ch: Charge) -> void:
	var h := ch.hero
	h.collision_mask = ch.mask
	h.state.dash_ticks = 0
	h.state.dash_velocity = Vector3.ZERO
	h.state.velocity = Vector3(0.0, h.state.velocity.y, 0.0)
	h.combat.abilities.dash_until_tick = server.tick
	if ch.carried != null and not ch.pinned:
		ch.carried.combat.status.remove_source(Modifier.source(Modifier.SRC_STATUS, h.net_id << 3 | 1))
	_remove_fx(ch.fx)
	charges.erase(ch)


func _land(lp: Leap) -> void:
	_remove_fx(lp.fx)
	var h := lp.hero
	h.state.dash_ticks = 0
	var ctx := lp.ctx.with_target(null, h.state.position)
	add_fx(FX_BURST, ctx.team, h.state.position, Vector3(ctx.param(&"radius"), 0.0, 0.0), 0.0,
		roundi(BURST_S * tick_hz))
	ctx.run(lp.on_land)


func _zone_passive(h: HeroBody) -> void:
	var mods := h.combat.def.zone_passive_modifiers
	if mods.is_empty():
		return
	var src := Modifier.source(Modifier.SRC_ZONE, h.net_id)
	var inside := _hardpoint_at(h.state.position) >= 0
	var has := h.combat.stats.has_source(src)
	if inside and not has:
		for m in mods:
			if m != null and m.index() >= 0:
				h.combat.stats.add_modifier(m.to_modifier(src))
	elif not inside and has:
		h.combat.stats.remove_by_source(src)


## Index (lane 0) of the hardpoint zone with an active task containing `p`, or -1.
## Slice simplification: every unlocked hardpoint runs a Hold task.
func _hardpoint_at(p: Vector3) -> int:
	if server.objectives == null:
		return -1
	var hps: Array = server.objectives.lanes[0] if not server.objectives.lanes.is_empty() else []
	for i in hps.size():
		var hp: HardpointSim = hps[i]
		var d := hp.def
		if hp.locked_for(0) and hp.locked_for(1):
			continue
		if p.y >= d.position.y - 1.0 and p.y <= d.position.y + d.zone_height \
				and Vector2(p.x - d.position.x, p.z - d.position.z).length() <= d.zone_radius:
			return i
	return -1


func _remove_fx(f: Fx) -> void:
	if f != null:
		fx.erase(f)


## Ray vs the wall's oriented box (width along the caster's right, thickness
## along their facing). Returns t or -1.
static func _ray_wall(o: Vector3, d: Vector3, w: Deployable) -> float:
	var basis := Basis(Vector3.UP, w.yaw)
	var c := w.pos + Vector3(0.0, w.height * 0.5, 0.0)
	var inv := basis.transposed()
	var lo := inv * (o - c)
	var ld := inv * d
	var half := Vector3(w.width * 0.5, w.height * 0.5, w.thickness * 0.5)
	var tmin := -INF
	var tmax := INF
	for k in 3:
		if absf(ld[k]) < 1e-9:
			if lo[k] < -half[k] or lo[k] > half[k]:
				return -1.0
			continue
		var t1 := (-half[k] - lo[k]) / ld[k]
		var t2 := (half[k] - lo[k]) / ld[k]
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return -1.0
	return maxf(tmin, 0.0)


static func _side(dir: Vector3, rel: Vector3, along: float) -> Vector3:
	var lat := Vector3(rel.x - dir.x * along, 0.0, rel.z - dir.z * along)
	if lat.length_squared() < 1e-4:
		lat = Vector3(-dir.z, 0.0, dir.x)
	return lat.normalized()


static func _flat2(a: Vector3, b: Vector3) -> float:
	return (a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)
