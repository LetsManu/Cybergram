extends GdUnitTestSuite
## W10-T1: Fork A / Fork B / Mastery of every hero on a real ServerWorld
## (design/gdd/heroes.md §4). Nodes are learned straight on the SkillInstance
## (the spend path and its gating are tested in skill_tree_forks_test.gd); the
## skills are cast through AbilityRunner.try_activate like the skill buttons.

const HZ: int = 30
const RYKER := "res://assets/data/heroes/hero_ryker_vance.tres"
const SABLE := "res://assets/data/heroes/hero_sable.tres"
const LIORA := "res://assets/data/heroes/hero_liora_vale.tres"

var _server: ServerWorld
var _link: LoopbackLink


## Scripted hero: holds `buttons` for ticks [from, to) with a fixed aim.
class Holder extends ScriptedInputSource:
	var from_tick: int = 0
	var to_tick: int = 0
	var buttons: int = 0
	var yaw: float = 0.0
	var pitch: float = 0.0

	func _init(def: ScriptedInputDef) -> void:
		super(def)

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		out.yaw = yaw
		out.pitch = pitch
		if seq >= from_tick and seq < to_tick:
			out.buttons |= buttons
		out.quantize()


func _world() -> void:
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(NetFixtures.net_config(), MovementDef.new(), CombatFixtures.range_scene(false), _link.create_endpoint(1),
		CombatFixtures.brannoc(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	_server.abilities.grant_ult = true


func _hero(path: String, at: Vector3, team: int, yaw_deg: float = 0.0) -> HeroBody:
	var def := ScriptedInputDef.new()
	def.segments = PackedVector2Array([Vector2.ZERO])
	def.start_yaw_deg = yaw_deg
	var holder := Holder.new(def)
	holder.yaw = deg_to_rad(yaw_deg)
	var h := _server.hero(_server.add_scripted_hero(holder, at, load(path) as HeroDef, team))
	h.combat.abilities.debug_grant_ult = true
	return h


func _holder(h: HeroBody) -> Holder:
	for d in _server._dummies:
		if d[0] == h:
			return d[1] as Holder
	return null


func _cast(h: HeroBody, slot: int, pitch: float = 0.0, yaw: float = 0.0) -> bool:
	var cmd := InputCommand.new()
	cmd.yaw = yaw
	cmd.pitch = pitch
	return h.combat.abilities.try_activate(slot, h, cmd, _server.tick, _server.abilities)


func _run(n: int) -> void:
	for i in n:
		_server.step()


func _start(spawn_marker: String = "PlayerSpawn") -> Vector3:
	await get_tree().physics_frame
	return _server.spawn_point(spawn_marker)



const VESPER := "res://assets/data/heroes/hero_vesper_loom.tres"


## Learns Boost, then `fork` (SkillNodeDef.Kind.FORK_A / FORK_B), then Mastery
## when `mastery`, on slot `slot` of `h`.
func _learn(h: HeroBody, slot: int, fork: int, mastery: bool = false) -> SkillInstance:
	var s := h.combat.abilities.skill(slot)
	for k in [SkillNodeDef.Kind.UNLOCK, SkillNodeDef.Kind.BOOST, fork]:
		var n := s.node_of(k)
		if n != null and not s.has_node(k):
			s.learn(n, h.combat.stats)
	if mastery:
		s.learn(s.node_of(SkillNodeDef.Kind.MASTERY), h.combat.stats)
	return s


func _ready_again(h: HeroBody, slot: int) -> void:
	var s := h.combat.abilities.skill(slot)
	s.cooldown_end_tick = 0
	s.charges_left = -1
	s.active = false
	h.combat.abilities.lockout_until_tick = 0


## Runs the skill's node effects on `target` (casts that need a Wardling / gadget).
func _node_ctx(h: HeroBody, slot: int, target: Node3D = null) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.world = _server.abilities
	ctx.caster = h
	ctx.skill = h.combat.abilities.skill(slot)
	ctx.team = h.combat.team
	ctx.tick = _server.tick
	ctx.origin = h.state.position + Vector3(0, 1.6, 0)
	ctx.point = h.state.position
	ctx.target = target
	return ctx


# ------------------------------------------------------------------ Vesper Loom

func test_vesper_thread_fork_a_hits_harder_fork_b_slows_mastery_chains() -> void:
	_world()
	var v := _hero(VESPER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero(VESPER, Vector3(0.0, 0.05, -10.0), ServerWorld.TEAM_DUMMIES)
	var other := _hero(VESPER, Vector3(4.0, 0.05, -10.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var s := _learn(v, 0, SkillNodeDef.Kind.FORK_B)
	assert_int(s.fork()).is_equal(2)
	assert_bool(_cast(v, 0)).is_true()
	_run(20)
	assert_float(foe.combat.health.hp).is_less(250.0)
	assert_bool(foe.combat.status.has(StatusComponent.Kind.SLOW)).is_true()  # Puppet String
	assert_float(other.combat.health.hp).is_equal(250.0)  # no Mastery: no chain
	var a := SkillInstance.new(s.def, 0)
	var base := a.param(&"damage")
	a.learn(a.node_of(SkillNodeDef.Kind.FORK_A))
	assert_float(a.param(&"damage")).is_equal_approx(base * 1.25, 1e-3)  # Pounce +25%
	# Mastery: the thread chains to a second enemy within 8 m.
	s.learn(s.node_of(SkillNodeDef.Kind.MASTERY), v.combat.stats)
	_ready_again(v, 0)
	_run(2)
	assert_bool(_cast(v, 0)).is_true()
	_run(20)
	assert_float(other.combat.health.hp).is_less(250.0)


func test_vesper_beacon_fork_a_heals_heroes_mastery_allows_two() -> void:
	_world()
	var v := _hero(VESPER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero(VESPER, Vector3(0.0, 0.05, -17.0), ServerWorld.TEAM_PLAYERS)  # under the beacon (pitch 0.5)
	await get_tree().physics_frame
	var s := _learn(v, 1, SkillNodeDef.Kind.FORK_A)
	ally.combat.health.hp = 100.0
	assert_bool(_cast(v, 1, 0.5)).is_true()
	assert_int(_server.abilities.deployables.size()).is_equal(1)
	var d := _server.abilities.deployables[0]
	assert_float(d.hero_heal_per_s).is_equal(10.0)
	_run(2 * HZ)
	assert_float(ally.combat.health.hp).is_greater(100.0)
	# Mastery: a second beacon does not retire the first.
	s.learn(s.node_of(SkillNodeDef.Kind.MASTERY), v.combat.stats)
	_ready_again(v, 1)
	_run(2)
	assert_bool(_cast(v, 1, 0.5)).is_true()
	var alive := 0
	for e in _server.abilities.deployables:
		if e.alive:
			alive += 1
	assert_int(alive).is_equal(2)
	_ready_again(v, 1)
	_run(2)
	assert_bool(_cast(v, 1, 0.5)).is_true()
	alive = 0
	for e in _server.abilities.deployables:
		if e.alive:
			alive += 1
	assert_int(alive).is_equal(2)  # the oldest was retired


func test_vesper_threadstep_forks_decoy_shield_and_two_charges() -> void:
	_world()
	var v := _hero(VESPER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero(VESPER, Vector3(0.0, 0.05, -2.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var s := _learn(v, 2, SkillNodeDef.Kind.FORK_B)
	_node_ctx(v, 2).run(s.node_of(SkillNodeDef.Kind.FORK_B).added_effects)
	assert_bool(v.combat.status.has(StatusComponent.Kind.SHIELD)).is_true()  # Cloak of Strings
	var a := SkillInstance.new(s.def, 2)
	a.learn(a.node_of(SkillNodeDef.Kind.FORK_A))
	assert_float(a.param(&"damage")).is_equal(80.0)
	var ctx := _node_ctx(v, 2)
	ctx.skill = a
	ctx.run(a.node_of(SkillNodeDef.Kind.FORK_A).added_effects)  # Decoy: 80 in 4 m after 1.5 s
	_run(2 * HZ)
	assert_float(foe.combat.health.hp).is_less(250.0)
	s.learn(s.node_of(SkillNodeDef.Kind.MASTERY), v.combat.stats)
	assert_int(s.max_charges()).is_equal(2)


# ------------------------------------------------------------------ Brannoc

const BRANNOC := "res://assets/data/heroes/hero_brannoc.tres"


func test_brannoc_wall_forks_and_mastery_heal() -> void:
	_world()
	var b := _hero(BRANNOC, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero(BRANNOC, Vector3(3.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := _learn(b, 0, SkillNodeDef.Kind.FORK_B, true)
	ally.combat.health.hp = 100.0
	var wall_hp := s.param(&"hp")
	assert_bool(_cast(b, 0, 0.3)).is_true()
	assert_bool(b.combat.status.has(StatusComponent.Kind.SHIELD)).is_true()  # Mirror approximation
	# Mastery heals allies near the wall: ally at the wall point.
	var ctx := _node_ctx(b, 0)
	ctx.point = ally.state.position
	ctx.run(s.node_of(SkillNodeDef.Kind.MASTERY).added_effects)
	assert_float(ally.combat.health.hp).is_greater_equal(200.0 - 1e-3)
	var a := SkillInstance.new(s.def, 0)
	a.learn(a.node_of(SkillNodeDef.Kind.FORK_A))
	assert_float(a.param(&"hp")).is_greater(1200.0)


func test_brannoc_fortify_forks_and_mastery_dr() -> void:
	_world()
	var b := _hero(BRANNOC, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero(BRANNOC, Vector3(3.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero(BRANNOC, Vector3(0.0, 0.05, -5.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	_learn(b, 2, SkillNodeDef.Kind.FORK_A, true)
	assert_bool(_cast(b, 2)).is_true()
	assert_bool(foe.combat.status.has(StatusComponent.Kind.SLOW)).is_true()  # Challenge approximation
	assert_bool(ally.combat.status.has(StatusComponent.Kind.DR)).is_true()  # Mastery: allies in 6 m
	# Lifeblood heals the caster.
	var b2 := _hero(BRANNOC, Vector3(30.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var s2 := _learn(b2, 2, SkillNodeDef.Kind.FORK_B)
	b2.combat.health.hp = 100.0
	_node_ctx(b2, 2).run(s2.node_of(SkillNodeDef.Kind.FORK_B).added_effects)
	assert_float(b2.combat.health.hp).is_equal_approx(150.0, 1e-3)


func test_brannoc_ram_forks_stun_shield_and_refund_data() -> void:
	_world()
	var b := _hero(BRANNOC, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := _learn(b, 1, SkillNodeDef.Kind.FORK_A)
	assert_float(s.param(&"stun")).is_equal_approx(1.5, 1e-4)  # Bulldozer stun 1.0 -> 1.5
	var s2 := SkillInstance.new(s.def, 1)
	s2.learn(s2.node_of(SkillNodeDef.Kind.FORK_B))
	var rc := _node_ctx(b, 1)
	rc.skill = s2
	rc.run(s2.node_of(SkillNodeDef.Kind.FORK_B).added_effects)
	assert_bool(b.combat.status.has(StatusComponent.Kind.SHIELD)).is_true()  # Interceptor shield
	s.learn(s.node_of(SkillNodeDef.Kind.MASTERY), b.combat.stats)
	assert_float(s.param(&"extra_b")).is_equal(0.5)  # pin refund fraction


# ------------------------------------------------------------------ Ryker Vance

func test_ryker_frag_cluster_hits_harder_breacher_arms_faster_mastery_three_charges() -> void:
	_world()
	var r := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero(VESPER, Vector3(10.0, 0.05, 0.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var s := _learn(r, 0, SkillNodeDef.Kind.FORK_A)
	var det := (s.def.effects[0] as ThrownEffectDef).on_detonate
	var ctx := _node_ctx(r, 0)
	ctx.point = foe.state.position
	ctx.run(det)
	var cluster := 250.0 - foe.combat.health.hp
	foe.combat.health.hp = 250.0
	var b := SkillInstance.new(s.def, 0)
	b.learn(b.node_of(SkillNodeDef.Kind.FORK_B))
	ctx.skill = b
	ctx.run(det)
	var plain := 250.0 - foe.combat.health.hp
	assert_float(cluster).is_greater(plain)
	assert_float(b.param(&"duration")).is_less(0.5)  # Breacher: near-instant fuse
	b.learn(b.node_of(SkillNodeDef.Kind.MASTERY))
	assert_int(b.max_charges()).is_equal(3)


func test_ryker_stim_forks_adrenal_overdrive_and_mastery_extension() -> void:
	_world()
	var r := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var r2 := _hero(RYKER, Vector3(20.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	_learn(r, 1, SkillNodeDef.Kind.FORK_A)
	r.combat.health.hp = 100.0
	assert_bool(_cast(r, 1)).is_true()
	assert_float(r.combat.health.hp).is_equal_approx(160.0, 1e-3)  # Adrenal: net +60, no HP cost
	_learn(r2, 1, SkillNodeDef.Kind.FORK_B, true)
	var f := r2.combat.weapon.feed as MagazineFeed
	f.rounds = 3
	r2.combat.health.hp = 200.0
	assert_bool(_cast(r2, 1)).is_true()
	assert_int(f.rounds).is_equal(f.def.magazine)  # instant full reload
	assert_float(r2.combat.health.hp).is_equal_approx(160.0, 1e-3)  # HP cost 40
	var buff = _server.abilities.extras.buffs.get(r2)
	assert_bool(buff != null and buff.extend_ticks > 0).is_true()  # Mastery: kills extend


func test_ryker_slide_forks_momentum_rebound_and_mastery_dr() -> void:
	_world()
	var r := _hero(RYKER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var r2 := _hero(RYKER, Vector3(20.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := _learn(r, 2, SkillNodeDef.Kind.FORK_A, true)
	assert_bool(_cast(r, 2)).is_true()
	assert_bool(_server.abilities.extras.buffs.has(r)).is_true()  # Momentum: +20% weapon damage window
	assert_bool(r.combat.status.has(StatusComponent.Kind.DR)).is_true()  # Mastery: 30% DR while sliding
	var s2 := _learn(r2, 2, SkillNodeDef.Kind.FORK_B)
	assert_int(s2.max_charges()).is_equal(2)  # Rebound: a second slide
	assert_float(s.param(&"dr")).is_equal_approx(0.3, 1e-4)


# ------------------------------------------------------------------ Liora Vale

func test_liora_drone_swarm_cleanse_and_hover_pulse() -> void:
	_world()
	var l := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var a1 := _hero(VESPER, Vector3(0.0, 0.05, -10.0), ServerWorld.TEAM_PLAYERS)
	var a2 := _hero(VESPER, Vector3(2.0, 0.05, -10.0), ServerWorld.TEAM_PLAYERS)
	var a3 := _hero(VESPER, Vector3(4.0, 0.05, -10.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := _learn(l, 0, SkillNodeDef.Kind.FORK_A, true)
	a1.combat.health.hp = 50.0
	a2.combat.health.hp = 60.0
	a3.combat.health.hp = 100.0
	var ctx := _node_ctx(l, 0)
	ctx.point = Vector3(0.0, 0.05, -10.0)
	ctx.run(s.effects())
	assert_int(_server.abilities.extras.drones.size()).is_equal(2)  # Swarm: 2 drones
	_run(60)
	var targets := {}
	for d in _server.abilities.extras.drones:
		if d.target != null:
			targets[d.target] = true
	assert_int(targets.size()).is_equal(2)  # different allies
	_run(6 * HZ)
	assert_float(a1.combat.health.hp).is_greater(50.0)
	assert_float(a2.combat.health.hp).is_greater(60.0)
	assert_float(a3.combat.health.hp).is_greater(100.0)  # Mastery hover pulse reached the third ally
	# Cleanse fork: Slow and Root are removed from the healed ally.
	var l2 := _hero(LIORA, Vector3(30.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero(VESPER, Vector3(30.0, 0.05, -10.0), ServerWorld.TEAM_PLAYERS)
	var s2 := _learn(l2, 0, SkillNodeDef.Kind.FORK_B)
	ally.combat.health.hp = 80.0
	ally.combat.status.apply(StatusComponent.Kind.SLOW, 300, 0.3, 77, _server.tick)
	var c2 := _node_ctx(l2, 0)
	c2.point = ally.state.position
	c2.run(s2.effects())
	_run(HZ)
	assert_bool(ally.combat.status.has(StatusComponent.Kind.SLOW)).is_false()


func test_liora_prism_ward_haste_overcharge_and_flash_bloom_sanctuary() -> void:
	_world()
	var l := _hero(LIORA, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero(VESPER, Vector3(3.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := _learn(l, 1, SkillNodeDef.Kind.FORK_A)
	var base := l.combat.stats.get_value(StatCatalog.MOVE_SPEED)
	_node_ctx(l, 1).run(s.effects())  # no ally in the cone: the caster is picked
	assert_float(l.combat.stats.get_value(StatCatalog.MOVE_SPEED)).is_greater(base * 1.2)  # Haste +25%
	assert_bool(l.combat.status.has(StatusComponent.Kind.SHIELD)).is_true()
	var l2 := _hero(LIORA, Vector3(40.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var s2 := _learn(l2, 1, SkillNodeDef.Kind.FORK_B)
	_node_ctx(l2, 1).run(s2.effects())
	assert_float(l2.combat.stats.get_value(StatCatalog.WEAPON_DAMAGE)).is_equal_approx(1.15, 1e-3)  # Overcharge
	var l3 := _hero(LIORA, Vector3(60.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var s3 := _learn(l3, 2, SkillNodeDef.Kind.FORK_A)
	ally.combat.health.hp = 100.0
	var c := _node_ctx(l3, 2)
	c.point = ally.state.position
	c.run(s3.node_of(SkillNodeDef.Kind.FORK_A).added_effects)
	assert_float(ally.combat.health.hp).is_equal_approx(160.0, 1e-3)  # Sanctuary +60 within 10 m


# ------------------------------------------------------------------ Sable

func test_sable_veilwalk_ambush_and_mastery_keeps_stealth_on_damage() -> void:
	_world()
	var sa := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero(VESPER, Vector3(0.0, 0.05, -30.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var s := _learn(sa, 0, SkillNodeDef.Kind.FORK_A, true)
	assert_bool(_cast(sa, 0)).is_true()
	assert_bool(_server.abilities.extras.stealth.has(sa)).is_true()
	var info := DamageInfo.make(10.0, foe.net_id, foe.combat.team, 0, DamageInfo.Type.SKILL)
	_server.damage_hero(sa, info)
	assert_bool(_server.abilities.extras.stealth.has(sa)).is_true()  # Mastery: damage does not break it
	var s2 := SkillInstance.new(s.def, 0)
	s2.learn(s2.node_of(SkillNodeDef.Kind.FORK_B))
	assert_float(s2.param(&"radius")).is_equal_approx(5.0, 1e-4)  # Ghost Lane shimmer 5 m
	_run(250)  # 8 s with the Boost, then the Ambush window
	assert_float(sa.combat.stats.get_value(StatCatalog.WEAPON_DAMAGE)).is_equal_approx(1.4, 1e-3)


func test_sable_phase_shift_forks_and_sabotage_cascade_and_snare() -> void:
	_world()
	var sa := _hero(SABLE, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero(VESPER, Vector3(2.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var f1 := _hero(VESPER, Vector3(10.0, 0.05, 0.0), ServerWorld.TEAM_DUMMIES)
	var f2 := _hero(VESPER, Vector3(18.0, 0.05, 0.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ps := _learn(sa, 1, SkillNodeDef.Kind.FORK_B, true)
	_node_ctx(sa, 1).run(ps.node_of(SkillNodeDef.Kind.FORK_B).added_effects)
	assert_float(ally.combat.stats.get_value(StatCatalog.MOVE_SPEED)).is_greater(6.0 * 1.2)  # Slipstream speed
	assert_int(ps.max_charges()).is_equal(2)  # Mastery
	var sb := _learn(sa, 2, SkillNodeDef.Kind.FORK_B, true)
	for p in [f1.state.position, f2.state.position]:
		var c := _node_ctx(sa, 2)
		c.point = p
		c.run(sb.effects())
	assert_int(_server.abilities.extras.charges.size()).is_equal(2)
	_run(2 * HZ)  # armed; the foes stand on the charges
	assert_int(_server.abilities.extras.charges.size()).is_equal(0)  # Cascade: both detonated
	assert_float(f2.combat.health.hp).is_less(250.0)
	assert_bool(f1.combat.status.has(StatusComponent.Kind.ROOT)).is_true()  # Snare Charge
