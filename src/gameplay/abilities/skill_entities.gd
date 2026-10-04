class_name SkillEntities
extends RefCounted
## Server-side state of the wave-9 hero kits (Ryker Vance, Liora Vale, Sable;
## design/gdd/heroes.md §4.2 / §4.4 / §4.6): thrown grenades and blooms, the
## Med-Pack drone and Aurora dome, Sable's stealth, Sabotage Charges and shadow
## dart, timed weapon buffs, Silence / Blind flags, the hero passives
## (HeroPassiveDef) and Liora's heal beam. Owned by AbilityWorld (`extras`),
## which calls step() once per tick and post_move() per hero; the effect
## resources in src/gameplay/abilities/effects/ call the public methods below
## through ctx.world.extras. Server only: clients see AbilityWorld FX entries
## (FX_* here) and the SkillStatusBits in the replicated status.
##
## Holds `server` only (not AbilityWorld) so there is no RefCounted cycle.

## Replicated FX kinds (SnapshotData.FxState.kind), above AbilityWorld.FX_*.
const FX_THROWN: int = 20   # grenade / bloom orb (pos)
const FX_DRONE: int = 21    # Med-Pack drone (pos, param = heal progress)
const FX_DOME: int = 22     # Aurora dome (radius in pos2.x)
const FX_BEAM: int = 23     # heal beam pos -> pos2
const FX_CHARGE: int = 24   # Sabotage Charge (param 0 = arming, 1 = armed)
const FX_DART: int = 25     # Eclipse dart (pos tail pos2)

## PLACEHOLDER. Bounds / feel constants (not in the GDD).
const MIN_HP: float = 1.0
const GRENADE_RADIUS_M: float = 0.15
const DART_HIT_PAD_M: float = 0.0
const CHARGE_FX_S: float = 600.0

class Thrown:
	var pos: Vector3
	var vel: Vector3
	var ctx: EffectContext
	var explode_tick: int = 0
	var def: ThrownEffectDef
	var fx: AbilityWorld.Fx


class Delayed:
	var tick: int = 0
	var ctx: EffectContext
	var effects: Array
	var fx: AbilityWorld.Fx


class Drone:
	var pos: Vector3
	var ctx: EffectContext
	var def: DroneEffectDef
	var target: Node3D
	var wait_until: int = 0
	var heal_until: int = 0
	var per_tick: float = 0.0
	var hover_until: int = -1  # W10-T1 Mastery: pulses after the heal
	var fx: AbilityWorld.Fx


class Aura:
	var pos: Vector3
	var ctx: EffectContext
	var def: AuraEffectDef
	var team: int = 0
	var radius: float = 0.0
	var end_tick: int = 0
	var floor_until: int = 0
	var heal_per_tick: float = 0.0
	var dr: float = 0.0
	var fx: AbilityWorld.Fx
	var src: int = 0


class SabCharge:
	var pos: Vector3
	var ctx: EffectContext
	var def: SabotageEffectDef
	var armed_tick: int = 0
	var fx: AbilityWorld.Fx


class Dart:
	var pos: Vector3
	var dir: Vector3
	var left: float = 0.0
	var terrain: bool = false
	var ctx: EffectContext
	var def: DartEffectDef
	var fx: AbilityWorld.Fx


class Teleport:
	var tick: int = 0
	var caster: HeroBody
	var victim: HeroBody
	var behind: float = 1.5


class Mark:
	var caster: HeroBody
	var until: int = 0
	var bonus: float = 0.0
	var skill: SkillInstance
	var rider: bool = false
	var refund: float = 0.0


class Buff:
	var hero: HeroBody
	var rate_until: int = -1
	var bottomless_until: int = -1
	var extend_ticks: int = 0
	var extended: int = 0
	var max_extend: int = 0
	var skill: SkillInstance
	var od_src: int = 0
	var od_bonus: float = 0.0


class Stealth:
	var skill: SkillInstance
	var until: int = 0
	var shots: int = 0
	var src: int = 0


class Phase:
	var hero: HeroBody
	var mask: int = 0
	var until: int = 0


var server: ServerWorld
var tick_hz: int
var dt: float

var thrown: Array[Thrown] = []
var delayed: Array[Delayed] = []
var drones: Array[Drone] = []
var auras: Array[Aura] = []
var charges: Array[SabCharge] = []
var darts: Array[Dart] = []
var teleports: Array[Teleport] = []
var phases: Array[Phase] = []
## HeroBody -> Mark / Buff / Stealth / until tick.
var marks: Dictionary = {}
var buffs: Dictionary = {}
var stealth: Dictionary = {}
var silenced: Dictionary = {}
var blinded: Dictionary = {}
## HeroBody -> {fx, target} live heal beam.
var beams: Dictionary = {}
## HeroBody -> refund fraction (Eclipse Step rank-3 rider armed).
var riders: Dictionary = {}
## HeroBody -> next free Med-Pack tick.
var _triage: Dictionary = {}
## Diagnostics / tests.
var kills_extended: int = 0
var healed_total: float = 0.0

var _ray := PhysicsRayQueryParameters3D.new()
var _floored: Array[HeroBody] = []
var _next_src: int = 1


func _init(world: ServerWorld) -> void:
	server = world
	tick_hz = world.net.tick_rate_hz
	dt = world.dt
	_ray.collision_mask = HeroBody.LAYER_WORLD
	server.hero_died.connect(_on_hero_died)
	server.hero_damaged.connect(_on_hero_damaged)


# --- Hooks from AbilityWorld ----------------------------------------------------

## Per hero after movement (before the skill gate): passives, heal beam.
func post_move(h: HeroBody, cmd: InputCommand) -> void:
	var c := h.combat
	if c.dead:
		_clear_hero(h)
		return
	for p in c.def.passives:
		match p.kind:
			HeroPassiveDef.Kind.HEAL_BEAM:
				_beam(h, cmd, p)
			HeroPassiveDef.Kind.TRIAGE_KIT:
				_triage_tick(h, p)


## Once per server tick (after the heroes): entities, buffs, timers.
func step() -> void:
	var t := server.tick
	_step_thrown(t)
	_step_delayed(t)
	_step_drones(t)
	_step_auras(t)
	_step_charges(t)
	_step_darts()
	_step_teleports(t)
	_step_buffs(t)
	_step_stealth(t)
	_step_phases(t)
	_expire_flags(t)


## Extra replicated status bits of `h`.
func status_bits(h: HeroBody) -> int:
	var b := 0
	if stealth.has(h):
		b |= SkillStatusBits.STEALTH
	if is_silenced(h):
		b |= SkillStatusBits.SILENCE
	if is_blinded(h):
		b |= SkillStatusBits.BLIND
	return b


func is_silenced(h: HeroBody) -> bool:
	return silenced.has(h) and server.tick < int(silenced[h])


func is_blinded(h: HeroBody) -> bool:
	return blinded.has(h) and server.tick < int(blinded[h])


func silence(h: HeroBody, ticks: int) -> void:
	silenced[h] = maxi(int(silenced.get(h, 0)), server.tick + ticks)


func blind(h: HeroBody, ticks: int) -> void:
	blinded[h] = maxi(int(blinded.get(h, 0)), server.tick + ticks)


## Per-shot weapon damage multiplier of `h` against `target` (Shadowgraph,
## Eclipse Step mark). 1 = none. Called by ServerWorld._fire for each hero hit.
func shot_mult(h: HeroBody, target: HeroBody) -> float:
	var m := 1.0
	for p in h.combat.def.passives:
		if p.kind == HeroPassiveDef.Kind.SHADOWGRAPH:
			var to := h.state.position - target.state.position
			var fwd := Basis(Vector3.UP, target.look_yaw) * Vector3.FORWARD
			if fwd.dot(Vector3(to.x, 0.0, to.z)) < 0.0:
				m += p.damage_bonus
	var mk: Mark = marks.get(target)
	if mk != null and mk.caster == h and server.tick < mk.until:
		m += mk.bonus
	return m


# --- Frag Grenade / thrown bodies -------------------------------------------------

func launch_thrown(ctx: EffectContext, def: ThrownEffectDef) -> void:
	var t := Thrown.new()
	t.ctx = ctx
	t.def = def
	t.pos = ctx.origin + ctx.dir * 0.6
	t.vel = (ctx.dir + Vector3.UP * def.lift).normalized() * ctx.param(def.speed_param)
	var fuse := maxi(1, ctx.ticks(def.fuse_param))
	t.explode_tick = server.tick + fuse
	t.fx = server.abilities.add_fx(FX_THROWN, ctx.team, t.pos, t.pos, ctx.yaw, fuse + 1)
	thrown.append(t)


func _step_thrown(tick: int) -> void:
	var i := thrown.size() - 1
	while i >= 0:
		var g := thrown[i]
		var boom := tick >= g.explode_tick or not _alive(g.ctx.caster)
		if not boom:
			g.vel.y -= g.def.gravity * dt
			var to := g.pos + g.vel * dt
			var hit := _cast(g.pos, to)
			if hit.is_empty():
				g.pos = to
			else:
				var n: Vector3 = hit.normal
				g.pos = (hit.position as Vector3) + n * 0.06
				if g.def.on_impact:
					boom = true
				else:
					g.vel = g.vel.bounce(n) * g.def.bounce
			if g.fx != null:
				g.fx.pos = g.pos
				g.fx.pos2 = g.pos
		if boom:
			thrown.remove_at(i)
			server.abilities._remove_fx(g.fx)
			if _alive(g.ctx.caster):
				g.ctx.with_target(null, g.pos).run(g.def.on_detonate)
		i -= 1


## Explosion at ctx.point (BlastEffectDef).
func blast(ctx: EffectContext, def: BlastEffectDef) -> void:
	var r := ctx.param(def.radius_param)
	var base := ctx.power_param(def.damage_param)
	var at := ctx.point
	server.abilities.add_fx(AbilityWorld.FX_BURST, ctx.team, at, Vector3(r, 0.0, 0.0), 0.0,
		roundi(AbilityWorld.BURST_S * tick_hz))
	for e in server.abilities.entities_in_radius(at, r, ctx.team, true, false, true, true):
		var chest := _chest(e)
		var d := at.distance_to(chest)
		if d > r + 1.0 or not _los(at + Vector3(0.0, 0.3, 0.0), chest):
			continue
		var f := lerpf(1.0, def.min_falloff, clampf(d / maxf(r, 0.01), 0.0, 1.0))
		var dmg := base * f * (def.wardling_mult if e is WardlingSim else 1.0)
		server.abilities.skill_damage(ctx, e, dmg)


# --- Flash Bloom ---------------------------------------------------------------------

func schedule(ctx: EffectContext, ticks: int, effects: Array) -> void:
	var d := Delayed.new()
	d.tick = server.tick + maxi(ticks, 1)
	d.ctx = ctx
	d.effects = effects
	d.fx = server.abilities.add_fx(FX_THROWN, ctx.team, ctx.point + Vector3(0.0, 0.3, 0.0),
		ctx.point + Vector3(0.0, 0.3, 0.0), ctx.yaw, maxi(ticks, 1) + 1)
	delayed.append(d)


func _step_delayed(tick: int) -> void:
	var i := delayed.size() - 1
	while i >= 0:
		var d := delayed[i]
		if tick >= d.tick:
			delayed.remove_at(i)
			server.abilities._remove_fx(d.fx)
			if _alive(d.ctx.caster):
				d.ctx.run(d.effects)
		i -= 1


func bloom(ctx: EffectContext, def: BloomEffectDef) -> void:
	var r := ctx.param(def.radius_param)
	var at := ctx.point
	server.abilities.add_fx(AbilityWorld.FX_BURST, ctx.team, at, Vector3(r, 0.0, 0.0), 0.0,
		roundi(AbilityWorld.BURST_S * tick_hz))
	var blind_ticks := ctx.ticks(def.blind_param)
	var knock := ctx.param(def.knock_param)
	for e in server.abilities.entities_in_radius(at, r, ctx.team, true, false, true, false):
		var h := e as HeroBody
		var to := Vector3(at.x - h.state.position.x, 0.0, at.z - h.state.position.z)
		var fwd := Basis(Vector3.UP, h.look_yaw) * Vector3.FORWARD
		if to.length() > 0.1 and fwd.angle_to(to.normalized()) > deg_to_rad(def.facing_deg):
			continue
		if not _los(at + Vector3(0.0, 0.5, 0.0), h.state.position + Vector3(0.0, 1.4, 0.0)):
			continue
		blind(h, blind_ticks)
		var away := -to
		away.y = 0.0
		if away.length() < 0.05:
			away = -Vector3(ctx.dir.x, 0.0, ctx.dir.z)
		away = away.normalized()
		var n := maxi(1, roundi(def.knock_s * tick_hz))
		var applied := h.combat.status.apply(StatusComponent.Kind.KNOCKBACK, n, 0.0,
			Modifier.source(Modifier.SRC_STATUS, (ctx.caster.net_id << 3) | 5), server.tick)
		if applied > 0:
			h.state.dash_velocity = away * (knock / (n * dt))
			h.state.dash_ticks = n
			h.state.dash_launch = false


# --- Med-Pack Drone ---------------------------------------------------------------------

func spawn_drone(ctx: EffectContext, def: DroneEffectDef) -> void:
	var d := Drone.new()
	d.ctx = ctx
	d.def = def
	d.pos = ctx.point + Vector3(0.0, 1.0, 0.0)
	d.wait_until = server.tick + roundi(def.wait_s * tick_hz)
	d.per_tick = ctx.power_param(def.heal_param) * dt
	d.fx = server.abilities.add_fx(FX_DRONE, ctx.team, d.pos, d.pos, ctx.yaw,
		roundi((def.wait_s + ctx.param(def.duration_param) + 2.0) * tick_hz))
	drones.append(d)


func _step_drones(tick: int) -> void:
	var i := drones.size() - 1
	while i >= 0:
		var d := drones[i]
		var done := false
		if d.target == null:
			d.target = _most_injured(d.ctx, d.def)
			if d.target != null:
				d.heal_until = tick + d.ctx.ticks(d.def.duration_param)
			elif tick >= d.wait_until:
				done = true
		elif d.hover_until >= 0:
			_hover_pulse(d, tick)
			done = tick >= d.hover_until
		else:
			if not _entity_alive(d.target):
				done = true
			else:
				var goal := _chest(d.target) + Vector3(0.0, 0.5, 0.0)
				d.pos = d.pos.move_toward(goal, d.def.fly_speed * dt)
				healed_total += _heal(d.target, d.per_tick)
				if d.ctx.param(&"extra") > 0.0 and d.target is HeroBody:  # Cleanse fork
					cleanse(d.target as HeroBody)
				if tick >= d.heal_until:
					var hover := d.ctx.ticks(&"secondary_duration")  # Mastery: hover and pulse
					if hover > 0:
						d.hover_until = tick + hover
					else:
						done = true
		if d.fx != null:
			d.fx.pos = d.pos
			d.fx.pos2 = d.pos
			d.fx.param = 1.0 if d.target != null else 0.0
		if done:
			drones.remove_at(i)
			server.abilities._remove_fx(d.fx)
		i -= 1


## W10-T1 Cleanse fork: removes Slow, Root, Silence and Scramble from `h`.
func cleanse(h: HeroBody) -> void:
	h.combat.status.remove_kinds([StatusComponent.Kind.SLOW, StatusComponent.Kind.ROOT])
	silenced.erase(h)
	server.abilities.traps.scramble_until.erase(h)


## W10-T1 Mastery: the hovering drone pulses `extra_b` HP/s to allies and
## Wardlings within `width` m.
func _hover_pulse(d: Drone, _tick: int) -> void:
	var amount := d.ctx.power_param(&"extra_b") * dt
	for e in server.abilities.entities_in_radius(d.pos, d.ctx.param(&"width"), d.ctx.team, false, true, true, true):
		healed_total += _heal(e, amount)


func _most_injured(ctx: EffectContext, def: DroneEffectDef) -> Node3D:
	var best: Node3D = null
	var best_frac := 0.999
	var at := drones_landing(ctx)
	for e in server.abilities.entities_in_radius(at, ctx.param(def.radius_param), ctx.team, false, true, true, true):
		var taken := false  # W10-T1 Swarm fork: drones of one caster pick different allies
		for o in drones:
			if o.target == e and o.ctx.caster == ctx.caster:
				taken = true
		if taken:
			continue
		var hp := _hp_frac(e)
		if hp < best_frac:
			best_frac = hp
			best = e
	return best


func drones_landing(ctx: EffectContext) -> Vector3:
	return ctx.point


# --- Aurora ---------------------------------------------------------------------------------

func spawn_aura(ctx: EffectContext, def: AuraEffectDef) -> void:
	var a := Aura.new()
	a.ctx = ctx
	a.def = def
	a.team = ctx.team
	a.pos = ctx.caster.state.position
	a.radius = ctx.param(def.radius_param)
	a.end_tick = server.tick + ctx.ticks(def.duration_param)
	a.floor_until = server.tick + roundi(def.floor_s * tick_hz)
	a.heal_per_tick = ctx.power_param(def.heal_param) * dt
	a.dr = ctx.param(def.dr_param)
	a.src = Modifier.source(Modifier.SRC_ZONE, 0xA00000 | (_next_src & 0xFFFF))
	_next_src += 1
	a.fx = server.abilities.add_fx(FX_DOME, ctx.team, a.pos, Vector3(a.radius, 0.0, 0.0), ctx.yaw,
		a.end_tick - server.tick + 1)
	auras.append(a)


func _step_auras(tick: int) -> void:
	var inside: Array[HeroBody] = []
	var i := auras.size() - 1
	while i >= 0:
		var a := auras[i]
		if tick >= a.end_tick:
			auras.remove_at(i)
			server.abilities._remove_fx(a.fx)
			i -= 1
			continue
		for e in server.abilities.entities_in_radius(a.pos, a.radius, a.team, false, true, true, true):
			if e is HeroBody:
				var h := e as HeroBody
				healed_total += _heal(h, a.heal_per_tick)
				if a.dr > 0.0:
					h.combat.status.apply(StatusComponent.Kind.DR, 2, a.dr, a.src, tick)
				if tick < a.floor_until:
					h.combat.health.floor_hp = MIN_HP
					inside.append(h)
			else:
				healed_total += _heal(e, a.heal_per_tick * a.def.wardling_mult)
		i -= 1
	for h in _floored:
		if is_instance_valid(h) and not inside.has(h):
			h.combat.health.floor_hp = 0.0
	_floored = inside


# --- Prism Ward (soft target) ------------------------------------------------------------------

## The allied hero (not the caster) nearest the crosshair within the cone and
## range with line of sight, or null.
func pick_ally_hero(h: HeroBody, origin: Vector3, dir: Vector3, range_m: float, cone_deg: float) -> HeroBody:
	var best: HeroBody = null
	var best_a := deg_to_rad(cone_deg)
	for id in server.registry.ids():
		var o := server.registry.get_node_by_id(id) as HeroBody
		if o == null or o == h or o.combat == null or o.combat.dead or o.combat.team != h.combat.team:
			continue
		var chest := o.state.position + Vector3(0.0, 1.2, 0.0)
		var to := chest - origin
		var d := to.length()
		if d > range_m or d < 0.01:
			continue
		var a := dir.angle_to(to / d)
		if a <= best_a and _los(origin, chest):
			best_a = a
			best = o
	return best


# --- Buffs: Combat Stim, Overdrive Protocol, Battle Rhythm ---------------------------------------

func stim(ctx: EffectContext, def: StimEffectDef) -> void:
	var h := ctx.caster
	var c := h.combat
	c.health.hp = maxf(MIN_HP, c.health.hp - def.hp_cost)
	var until := server.tick + ctx.ticks(def.duration_param)
	var b := _buff(h)
	b.rate_until = until
	if c.weapon != null:
		c.weapon.rate_mult = 1.0 + def.fire_rate_bonus
	_speed_buff(h, def.speed_bonus, until, 0x100)


func overdrive(ctx: EffectContext, def: OverdriveEffectDef) -> void:
	var h := ctx.caster
	var b := _buff(h)
	var ticks := ctx.ticks(def.duration_param)
	b.bottomless_until = server.tick + ticks
	b.skill = ctx.skill
	b.extend_ticks = roundi(ctx.param(def.extend_param) * tick_hz)
	b.max_extend = roundi(def.max_extension_s * tick_hz)
	b.extended = 0
	b.od_bonus = ctx.param(def.bonus_param)
	b.od_src = Modifier.source(Modifier.SRC_PASSIVE, 0x500000 | (h.net_id & 0xFFF))
	_od_modifier(h, b)


func _od_modifier(h: HeroBody, b: Buff) -> void:
	h.combat.stats.remove_by_source(b.od_src)
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.WEAPON_DAMAGE, Modifier.Op.MUL, 1.0 + b.od_bonus,
		b.od_src, b.bottomless_until))


func _speed_buff(h: HeroBody, bonus: float, until: int, salt: int) -> void:
	var src := Modifier.source(Modifier.SRC_PASSIVE, 0x600000 | salt | (h.net_id & 0xFF))
	h.combat.stats.remove_by_source(src)
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.MOVE_SPEED, Modifier.Op.PCT, bonus, src, until))


func _buff(h: HeroBody) -> Buff:
	var b: Buff = buffs.get(h)
	if b == null:
		b = Buff.new()
		b.hero = h
		buffs[h] = b
	return b


func _step_buffs(tick: int) -> void:
	for key in buffs.keys():
		var h := key as HeroBody
		var b: Buff = buffs[key]
		if not _alive(h) or h.combat.dead:
			if _alive(h):
				_end_buffs(b)
			buffs.erase(h)
			continue
		var w := h.combat.weapon
		if b.rate_until >= 0 and tick >= b.rate_until:
			b.rate_until = -1
			if w != null:
				w.rate_mult = 1.0
		if b.bottomless_until >= 0:
			if tick >= b.bottomless_until:
				b.bottomless_until = -1
			elif w != null and w.feed is MagazineFeed:
				var f := w.feed as MagazineFeed
				f.rounds = f.def.magazine
				f.reload_end_tick = -1
		if b.rate_until < 0 and b.bottomless_until < 0:
			buffs.erase(h)


func _end_buffs(b: Buff) -> void:
	if b.hero.combat.weapon != null:
		b.hero.combat.weapon.rate_mult = 1.0
	b.hero.combat.stats.remove_by_source(b.od_src)


# --- Slide / Phase --------------------------------------------------------------------------------

func slide(ctx: EffectContext, def: SlideEffectDef) -> void:
	var h := ctx.caster
	var dir := Vector3(ctx.dir.x, 0.0, ctx.dir.z)
	dir = dir.normalized() if dir.length() > 0.01 else -h.global_transform.basis.z
	var n := maxi(1, roundi(def.time_s * tick_hz))
	h.state.dash_velocity = dir * (ctx.param(def.distance_param) / (n * dt))
	h.state.dash_ticks = n
	h.state.dash_launch = false
	if def.locks_actions:
		h.combat.abilities.dash_until_tick = server.tick + n + 1
	server.abilities.add_fx(AbilityWorld.FX_ARROW, ctx.team, h.state.position,
		h.state.position + dir * ctx.param(def.distance_param), ctx.yaw, n + 1)
	var w := h.combat.weapon
	if def.reload_frac > 0.0 and w != null and w.feed is MagazineFeed:
		var f := w.feed as MagazineFeed
		var add := mini(ceili(def.reload_frac * f.def.magazine), mini(f.reserve, f.def.magazine - f.rounds))
		if add > 0:
			f.rounds += add
			f.reserve -= add
			f.reload_end_tick = -1
	if def.intangible_s > 0.0:
		var until := server.tick + maxi(1, roundi(def.intangible_s * tick_hz))
		var src := Modifier.source(Modifier.SRC_PASSIVE, 0x700000 | (h.net_id & 0xFF))
		h.combat.stats.remove_by_source(src)
		h.combat.stats.add_modifier(Modifier.make(StatCatalog.DAMAGE_TAKEN, Modifier.Op.OVERRIDE, 0.0, src, until))
		var p := Phase.new()
		p.hero = h
		p.mask = h.collision_mask
		p.until = until
		h.collision_mask = HeroBody.LAYER_WORLD | HeroBody.LAYER_EDGE_BLOCK
		phases.append(p)


func _step_phases(tick: int) -> void:
	var i := phases.size() - 1
	while i >= 0:
		var p := phases[i]
		if not _alive(p.hero) or tick >= p.until:
			if _alive(p.hero):
				p.hero.collision_mask = p.mask
			phases.remove_at(i)
		i -= 1


# --- Veilwalk --------------------------------------------------------------------------------------

func stealth_start(h: HeroBody, skill: SkillInstance, ticks: int, speed_bonus: float) -> void:
	var s := Stealth.new()
	s.skill = skill
	s.until = server.tick + ticks
	s.shots = h.combat.weapon.shots_fired if h.combat.weapon != null else 0
	s.src = Modifier.source(Modifier.SRC_PASSIVE, 0x800000 | (h.net_id & 0xFF))
	h.combat.stats.remove_by_source(s.src)
	h.combat.stats.add_modifier(Modifier.make(StatCatalog.MOVE_SPEED, Modifier.Op.PCT, speed_bonus, s.src, s.until))
	stealth[h] = s
	var cb := _on_skill_cast.bind(h)
	if not h.combat.abilities.skill_activated.is_connected(cb):
		h.combat.abilities.skill_activated.connect(cb)


## Ends stealth early (fired, cast, hit): the skill's cooldown starts now.
func break_stealth(h: HeroBody) -> void:
	var s: Stealth = stealth.get(h)
	if s == null:
		return
	_drop_stealth(h, s)
	h.combat.abilities.end_active(s.skill, server.tick)


func _drop_stealth(h: HeroBody, s: Stealth) -> void:
	stealth.erase(h)
	h.combat.stats.remove_by_source(s.src)
	var ambush := s.skill.param(&"extra")  # W10-T1 Ambush fork: weapon bonus after leaving stealth
	if ambush > 0.0 and not h.combat.dead:
		h.combat.stats.add_modifier(Modifier.make(StatCatalog.WEAPON_DAMAGE, Modifier.Op.MUL, 1.0 + ambush,
			Modifier.source(Modifier.SRC_PASSIVE, 0xA00000 | (h.net_id & 0xFF)),
			server.tick + roundi(s.skill.param(&"extra_b") * tick_hz)))
	var cb := _on_skill_cast.bind(h)
	if h.combat.abilities.skill_activated.is_connected(cb):
		h.combat.abilities.skill_activated.disconnect(cb)


func _on_skill_cast(slot: int, _tick: int, h: HeroBody) -> void:
	var s: Stealth = stealth.get(h)
	if s != null and slot != s.skill.slot:
		break_stealth(h)


func _step_stealth(tick: int) -> void:
	for key in stealth.keys():
		var h := key as HeroBody
		var s: Stealth = stealth[key]
		if not _alive(h):
			stealth.erase(h)
			continue
		var w := h.combat.weapon
		if h.combat.dead:
			_drop_stealth(h, s)
		elif tick >= s.until:
			_drop_stealth(h, s)  # the runner starts the cooldown at the window end
		elif w != null and w.shots_fired != s.shots:
			break_stealth(h)


## True when `viewer_pos` cannot see stealthed hero `h`: beyond the Veilwalk
## shimmer radius (the skill's `radius` param, heroes.md §4.2). Used by bots.
func hidden_from(h: HeroBody, viewer_pos: Vector3) -> bool:
	var s: Stealth = stealth.get(h)
	return s != null and h.state.position.distance_to(viewer_pos) > s.skill.param(&"radius")


# --- Sabotage Charges ---------------------------------------------------------------------------------

func plant_charge(ctx: EffectContext, def: SabotageEffectDef) -> void:
	var mine: Array[SabCharge] = []
	for c in charges:
		if c.ctx.caster == ctx.caster and c.ctx.skill == ctx.skill:
			mine.append(c)
	var cap := maxi(1, roundi(ctx.param(def.max_param)))
	while mine.size() >= cap:
		_remove_charge(mine.pop_front())
	var c := SabCharge.new()
	c.ctx = ctx
	c.def = def
	c.pos = ctx.point + Vector3(0.0, 0.1, 0.0)
	c.armed_tick = server.tick + roundi(def.arm_s * tick_hz)
	c.fx = server.abilities.add_fx(FX_CHARGE, ctx.team, c.pos, c.pos, ctx.yaw, roundi(CHARGE_FX_S * tick_hz))
	c.fx.param = 0.0
	charges.append(c)


func detonate_charges(caster: HeroBody) -> void:
	for c in charges.duplicate():
		if c.ctx.caster == caster and server.tick >= c.armed_tick:
			_explode_charge(c)


func _remove_charge(c: SabCharge) -> void:
	charges.erase(c)
	server.abilities._remove_fx(c.fx)


func _step_charges(tick: int) -> void:
	for c in charges.duplicate():
		if not _alive(c.ctx.caster):
			_remove_charge(c)
			continue
		if tick < c.armed_tick:
			continue
		c.fx.param = 1.0
		for e in server.abilities.entities_in_radius(c.pos, c.def.trigger_radius_m, c.ctx.team, true, false, true, false):
			if e.state.position.distance_to(c.pos) <= c.def.trigger_radius_m:
				_explode_charge(c)
				break


func _explode_charge(c: SabCharge) -> void:
	_remove_charge(c)
	var ctx := c.ctx.with_target(null, c.pos)
	var r := ctx.param(c.def.radius_param)
	var dmg := ctx.power_param(c.def.damage_param)
	server.abilities.add_fx(AbilityWorld.FX_BURST, ctx.team, c.pos, Vector3(r, 0.0, 0.0), 0.0,
		roundi(AbilityWorld.BURST_S * tick_hz))
	for e in server.abilities.entities_in_radius(c.pos, r, ctx.team, true, false, true, true):
		server.abilities.skill_damage(ctx, e, dmg)
	for g in server.generators:
		if g.is_up() and g.attackable_by(ctx.team) and g.global_position.distance_to(c.pos) <= r + g.hit_radius:
			server.damage_generator(g, g.hp_sim.generator_hp() * (c.def.structure_frac + ctx.param(&"extra")),
				ctx.team, c.pos, false)  # `extra`: Demolition fork
	var root := ctx.ticks(&"extra_b")  # Snare Charge fork: heroes hit are rooted
	if root > 0:
		for e in server.abilities.entities_in_radius(c.pos, r, ctx.team, true, false, true, false):
			server.abilities.apply_status(ctx, e, StatusComponent.Kind.ROOT, root, 0.0)
	var chain := ctx.param(&"width")  # Mastery Cascade: the caster's other charges within `width` m go off
	if chain > 0.0:
		for o in charges.duplicate():
			if o.ctx.caster == c.ctx.caster and o.armed_tick <= server.tick and o.pos.distance_to(c.pos) <= chain:
				_explode_charge(o)


# --- Eclipse Step ----------------------------------------------------------------------------------------

func launch_dart(ctx: EffectContext, def: DartEffectDef) -> void:
	var d := Dart.new()
	d.ctx = ctx
	d.def = def
	d.pos = ctx.origin
	d.dir = ctx.dir.normalized()
	var range_m := ctx.param(def.range_param)
	var hit := _cast(d.pos, d.pos + d.dir * range_m)
	d.terrain = not hit.is_empty()
	d.left = d.pos.distance_to(hit.position) if d.terrain else range_m
	var speed := ctx.param(def.speed_param)
	d.fx = server.abilities.add_fx(FX_DART, ctx.team, d.pos, d.pos, ctx.yaw, ceili(d.left / maxf(speed, 1.0) * tick_hz) + 2)
	darts.append(d)


func _step_darts() -> void:
	var i := darts.size() - 1
	while i >= 0:
		var d := darts[i]
		var ctx := d.ctx
		if not _alive(ctx.caster) or ctx.caster.combat.dead:
			darts.remove_at(i)
			server.abilities._remove_fx(d.fx)
			i -= 1
			continue
		var seg := minf(ctx.param(d.def.speed_param) * dt, d.left)
		var best_t := seg
		var best: HeroBody = null
		var wall := server.abilities.block_distance(d.pos, d.dir, seg, ctx.team)
		var blocked := not wall.is_empty()
		if blocked:
			best_t = wall[0]
		for e in server.abilities.entities_in_radius(d.pos + d.dir * seg * 0.5, seg * 0.5 + 2.0, ctx.team, true, false, true, false):
			var t := server.abilities._ray_body(d.pos, d.dir, e, d.def.hit_radius_m)
			if t >= 0.0 and t <= best_t:
				best_t = t
				best = e as HeroBody
				blocked = false
		if best != null:
			_dart_hit(d, best)
			darts.remove_at(i)
			server.abilities._remove_fx(d.fx)
		elif blocked:
			server.abilities.damage_deployable(wall[1], 0.0)
			darts.remove_at(i)
			server.abilities._remove_fx(d.fx)
		else:
			var tail := d.pos
			d.pos += d.dir * seg
			d.left -= seg
			if d.fx != null:
				d.fx.pos = d.pos
				d.fx.pos2 = tail
			if d.left <= 0.001:
				if d.terrain:
					_teleport_to_terrain(d)
				darts.remove_at(i)
				server.abilities._remove_fx(d.fx)
		i -= 1


func _dart_hit(d: Dart, victim: HeroBody) -> void:
	var ctx := d.ctx
	silence(victim, ctx.ticks(d.def.silence_param))
	var mk := Mark.new()
	mk.caster = ctx.caster
	mk.until = server.tick + ctx.ticks(d.def.window_param)
	mk.bonus = ctx.param(d.def.mark_param)
	mk.skill = ctx.skill
	if riders.has(ctx.caster):
		mk.rider = true
		mk.refund = float(riders[ctx.caster])
	marks[victim] = mk
	var tp := Teleport.new()
	tp.tick = server.tick + roundi(d.def.delay_s * tick_hz)
	tp.caster = ctx.caster
	tp.victim = victim
	tp.behind = d.def.behind_m
	teleports.append(tp)
	server.skill_hit_feedback(ctx.caster, victim.net_id, 0.0, false, victim.state.position + Vector3(0.0, 1.2, 0.0))


func _teleport_to_terrain(d: Dart) -> void:
	var at := d.pos - d.dir * 0.4
	var floor_p := server.abilities.ground_point(at + Vector3.UP * 0.2, Vector3.DOWN, 6.0)
	server.abilities.teleport(d.ctx.caster, floor_p + Vector3(0.0, 0.05, 0.0))


func _step_teleports(tick: int) -> void:
	var i := teleports.size() - 1
	while i >= 0:
		var tp := teleports[i]
		if tick >= tp.tick:
			teleports.remove_at(i)
			if _alive(tp.caster) and _alive(tp.victim) and not tp.caster.combat.dead and not tp.victim.combat.dead:
				var fwd := Basis(Vector3.UP, tp.victim.look_yaw) * Vector3.FORWARD
				var from := tp.victim.state.position + Vector3(0.0, 1.0, 0.0)
				var want := from - fwd * tp.behind
				var hit := _cast(from, want)
				if not hit.is_empty():
					want = (hit.position as Vector3) + (hit.normal as Vector3) * 0.4
				want.y = tp.victim.state.position.y + 0.05
				server.abilities.teleport(tp.caster, want)
		i -= 1


func arm_rider(caster: HeroBody, refund: float) -> void:
	riders[caster] = refund


# --- Passives -------------------------------------------------------------------------------------------

func _on_hero_damaged(victim_id: int, _attacker: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var v := server.hero(victim_id)
	if v != null and stealth.has(v):
		var st: Stealth = stealth[v]
		if st.skill.param(&"count") > 0.0:
			return  # W10-T1 Veilwalk Mastery: damage no longer breaks stealth
		break_stealth(v)


func _on_hero_died(victim_id: int, killer_id: int) -> void:
	var victim := server.hero(victim_id)
	var killer := server.hero(killer_id)
	var mk: Mark = marks.get(victim) if victim != null else null
	if victim != null:
		_clear_hero(victim)
	if killer == null or killer.combat == null or killer.combat.dead or killer == victim:
		return
	for p in killer.combat.def.passives:
		if p.kind == HeroPassiveDef.Kind.BATTLE_RHYTHM:
			_rhythm(killer, p)
	var b: Buff = buffs.get(killer)
	if b != null and b.bottomless_until >= 0 and b.extend_ticks > 0 and b.extended + b.extend_ticks <= b.max_extend:
		b.extended += b.extend_ticks
		b.bottomless_until += b.extend_ticks
		if b.rate_until >= 0:  # W10-T1 Stim Mastery: the Stim's fire-rate window extends too
			b.rate_until += b.extend_ticks
		_od_modifier(killer, b)
		if b.skill != null and b.skill.active and b.skill.active_until_tick >= 0:
			b.skill.active_until_tick += b.extend_ticks
		kills_extended += 1
	if mk != null and mk.caster == killer and server.tick < mk.until and mk.rider:
		_eclipse_rider(killer, mk)


func _rhythm(h: HeroBody, p: HeroPassiveDef) -> void:
	var w := h.combat.weapon
	if w != null and w.feed is MagazineFeed:
		var f := w.feed as MagazineFeed
		f.rounds = mini(f.def.magazine, f.rounds + ceili(p.magazine_refill_frac * f.def.magazine))
		f.reload_end_tick = -1
	_speed_buff(h, p.speed_bonus, server.tick + roundi(p.duration_s * tick_hz), 0x200)


## Rank-3 rider: free Veilwalk, 30% of the ultimate cooldown refunded.
func _eclipse_rider(h: HeroBody, mk: Mark) -> void:
	var ab := h.combat.abilities
	var ult := mk.skill
	if ult != null and ult.cooldown_total_ticks > 0:
		ult.cooldown_end_tick -= roundi(ult.cooldown_total_ticks * mk.refund)
	for s in ab.skills:
		for e in s.effects():
			if e is StealthEffectDef:
				var ticks := roundi(s.param((e as StealthEffectDef).duration_param) * tick_hz)
				s.active = true
				s.active_until_tick = server.tick + ticks
				stealth_start(h, s, ticks, (e as StealthEffectDef).speed_bonus)
				return


func _triage_tick(h: HeroBody, p: HeroPassiveDef) -> void:
	if server.progression == null:
		return
	var prog := server.progression.progress_of(h)
	var due: int = _triage.get(h, -1)
	if due < 0:
		_triage[h] = server.tick + roundi(p.interval_s * tick_hz)
		return
	if server.tick < due:
		return
	_triage[h] = server.tick + roundi(p.interval_s * tick_hz)
	if prog.medpacks < p.max_free:
		prog.medpacks += 1


# --- Heal beam -------------------------------------------------------------------------------------------

func _beam(h: HeroBody, cmd: InputCommand, p: HeroPassiveDef) -> void:
	var c := h.combat
	var w := c.weapon
	var held := cmd.has(InputCommand.BTN_ALT) and not c.status.is_stunned()
	c.beaming = held
	var rec: Dictionary = beams.get(h, {})
	if not held or w == null or not (w.feed is ManaPoolFeed):
		_end_beam(h)
		return
	var feed := w.feed as ManaPoolFeed
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var dir := Basis(Vector3.UP, h.look_yaw) * Basis(Vector3.RIGHT, h.look_pitch) * Vector3.FORWARD
	var target: Node3D = rec.get("target")
	if target != null and not _beam_valid(h, target, eye, p.leash_m):
		target = null
	if target == null:
		target = _beam_acquire(h, eye, dir, p)
	if target == null:
		_end_beam(h)
		return
	var fx: AbilityWorld.Fx = rec.get("fx")
	if fx == null:
		fx = server.abilities.add_fx(FX_BEAM, c.team, eye, _chest(target), 0.0, 3)
	fx.pos = eye + Vector3(0.0, -0.25, 0.0)
	fx.pos2 = _chest(target)
	fx.expires_tick = server.tick + 2
	beams[h] = {"target": target, "fx": fx}
	if _hp_frac(target) >= 0.999 or feed.mana <= 0.0:
		return  # no drain on a full-HP target (heroes.md §7.8)
	feed.mana = maxf(0.0, feed.mana - p.mana_per_s * dt)
	var delay := feed.regen_delay_s() * (c.weapon.def.burnout_delay_mult if feed.mana <= 0.0 else 1.0)
	feed.burnout = feed.mana <= 0.0
	feed.regen_resume_tick = c.local_tick + feed.ticks(delay)
	var hps := p.hero_heal_per_s if target is HeroBody else p.wardling_heal_per_s
	healed_total += _heal(target, hps * c.stats.get_value(StatCatalog.WEAPON_DAMAGE) * dt)


func _end_beam(h: HeroBody) -> void:
	var rec: Dictionary = beams.get(h, {})
	if rec.is_empty():
		return
	server.abilities._remove_fx(rec.get("fx"))
	beams.erase(h)


func _beam_valid(h: HeroBody, t: Node3D, eye: Vector3, leash: float) -> bool:
	return _entity_alive(t) and _chest(t).distance_to(eye) <= leash and _los(eye, _chest(t))


func _beam_acquire(h: HeroBody, eye: Vector3, dir: Vector3, p: HeroPassiveDef) -> Node3D:
	var best: Node3D = null
	var best_a := deg_to_rad(p.cone_deg)
	for e in server.abilities.entities_in_radius(h.state.position, p.range_m + 1.0, h.combat.team, false, true, true, true):
		if e == h:
			continue
		var chest := _chest(e)
		var to := chest - eye
		var d := to.length()
		if d > p.range_m or d < 0.01:
			continue
		var a := dir.angle_to(to / d)
		if a <= best_a and _los(eye, chest):
			best_a = a
			best = e
	return best


# --- Shared helpers -------------------------------------------------------------------------------------

func _clear_hero(h: HeroBody) -> void:
	if stealth.has(h):
		_drop_stealth(h, stealth[h])
	silenced.erase(h)
	blinded.erase(h)
	marks.erase(h)
	riders.erase(h)
	h.combat.beaming = false
	h.combat.health.floor_hp = 0.0
	_end_beam(h)
	if buffs.has(h):
		_end_buffs(buffs[h])
		buffs.erase(h)


func _expire_flags(t: int) -> void:
	for h in silenced.keys():
		if not is_instance_valid(h) or t >= int(silenced[h]):
			silenced.erase(h)
	for h in blinded.keys():
		if not is_instance_valid(h) or t >= int(blinded[h]):
			blinded.erase(h)
	for h in marks.keys():
		if not is_instance_valid(h) or t >= (marks[h] as Mark).until:
			marks.erase(h)


func _alive(n: Object) -> bool:
	return n != null and is_instance_valid(n)


func _entity_alive(e: Node3D) -> bool:
	if not _alive(e):
		return false
	if e is HeroBody:
		return not (e as HeroBody).combat.dead
	return not (e as WardlingSim).dead


func _chest(e: Node3D) -> Vector3:
	if e is HeroBody:
		return (e as HeroBody).state.position + Vector3(0.0, 1.2, 0.0)
	if e is WardlingSim:
		return (e as WardlingSim).chest()
	return e.global_position


func _hp_frac(e: Node3D) -> float:
	if e is HeroBody:
		var hh := (e as HeroBody).combat.health
		return hh.hp / maxf(hh.max_hp, 1.0)
	var wh := (e as WardlingSim).health
	return wh.hp / maxf(wh.max_hp, 1.0)


func _heal(e: Node3D, amount: float) -> float:
	if e is HeroBody:
		return (e as HeroBody).combat.health.heal(amount)
	if e is WardlingSim:
		return (e as WardlingSim).health.heal(amount)
	return 0.0


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	return server.get_world_3d().direct_space_state.intersect_ray(_ray)


func _los(a: Vector3, b: Vector3) -> bool:
	return _cast(a, b).is_empty()
