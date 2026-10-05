extends GdUnitTestSuite
## W11-M1: Reveal, Bleed / Healing reduction, Hijack, movement-blocking wall,
## expiry hooks and recast mechanics on a real ServerWorld.

const HZ: int = 30
const VESPER := "res://assets/data/heroes/hero_vesper_loom.tres"
const JUNIPER := "res://assets/data/heroes/hero_juniper_quill.tres"
const HEX := "res://assets/data/heroes/hero_hex.tres"
const BRANNOC := "res://assets/data/heroes/hero_brannoc.tres"

var _server: ServerWorld
var _link: LoopbackLink
var _walker: HeroBody


class Holder extends ScriptedInputSource:
	var yaw: float = 0.0
	var move_forward: bool = false

	func _init(def: ScriptedInputDef) -> void:
		super(def)

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		out.yaw = yaw
		if move_forward:
			out.move = Vector2(0.0, -1.0)
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


func _hero(path: String, at: Vector3, team: int, walk: bool = false) -> HeroBody:
	var def := ScriptedInputDef.new()
	def.segments = PackedVector2Array([Vector2.ZERO])
	var holder := Holder.new(def)
	holder.move_forward = walk
	return _server.hero(_server.add_scripted_hero(holder, at, load(path) as HeroDef, team))


func _cast(h: HeroBody, slot: int) -> bool:
	var cmd := InputCommand.new()
	return h.combat.abilities.try_activate(slot, h, cmd, _server.tick, _server.abilities)


func _learn_fork(h: HeroBody, slot: int, fork: int) -> SkillInstance:
	var s := h.combat.abilities.skill(slot)
	for k in [SkillNodeDef.Kind.UNLOCK, SkillNodeDef.Kind.BOOST, fork]:
		var n := s.node_of(k)
		if n != null and not s.has_node(k):
			s.learn(n, h.combat.stats)
	return s


func _run(n: int) -> void:
	for i in n:
		_server.step()


func _fake_skill(params: Dictionary) -> SkillInstance:
	var sd := SkillDef.new()
	sd.id = &"w11_fake"
	sd.params = params
	return SkillInstance.new(sd, 0)


func _ctx(h: HeroBody, target: Node3D = null, slot: int = 0) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.world = _server.abilities
	ctx.caster = h
	ctx.skill = h.combat.abilities.skill(slot)
	ctx.team = h.combat.team
	ctx.tick = _server.tick
	ctx.target = target
	ctx.point = h.state.position
	return ctx


# ------------------------------------------------------------------ Reveal

func test_reveal_sets_bit_only_for_the_revealing_team() -> void:
	_world()
	var a := _hero(VESPER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero(VESPER, Vector3(0.0, 0.05, -10.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ctx := _ctx(a, foe)
	ctx.skill = _fake_skill({&"reveal": 4.0})
	RevealEffectDef.new().apply(ctx)
	assert_bool(_server.abilities.reveals.is_revealed(foe.net_id, a.combat.team, _server.tick)).is_true()
	var base: Array[SnapshotData.EntityState] = []
	for h in [a, foe]:
		var e := SnapshotData.EntityState.new()
		e.net_id = h.net_id
		e.team = h.combat.team
		base.append(e)
	var mine := _server._entities_for(base, null, a)
	var theirs := _server._entities_for(base, null, foe)
	assert_int(mine[1].status & SkillStatusBits.REVEALED).is_equal(SkillStatusBits.REVEALED)
	assert_int(theirs[0].status & SkillStatusBits.REVEALED).is_equal(0)  # no leak
	assert_int(base[1].status).is_equal(0)  # shared state untouched
	_run(4 * HZ + 2)
	assert_bool(_server.abilities.reveals.is_revealed(foe.net_id, a.combat.team, _server.tick)).is_false()


# ------------------------------------------------------------------ Bleed / Healing reduction

func test_bleed_deals_its_total_over_time_and_heal_cut_reduces_heals() -> void:
	_world()
	var a := _hero(VESPER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero(VESPER, Vector3(0.0, 0.05, -10.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ctx := _ctx(a, foe)
	ctx.skill = _fake_skill({&"bleed": 40.0, &"bleed_time": 3.0, &"heal_cut": 0.3, &"heal_cut_time": 3.0})
	_server.abilities.apply_skill_dots(ctx, foe)
	var before := foe.combat.health.hp
	foe.combat.health.hp -= 100.0
	before = foe.combat.health.hp
	_run(3 * HZ + 3)
	var lost := before - foe.combat.health.hp
	assert_float(lost).is_between(36.0, 41.0)  # ~40 true damage over 3 s (power scaled)
	assert_bool(foe.combat.status.has(StatusComponent.Kind.BLEED)).is_false()
	# While cut, heals are 30% weaker.
	_server.abilities.apply_skill_dots(ctx, foe)
	var hp := foe.combat.health.hp
	foe.combat.health.heal(100.0)
	assert_float(foe.combat.health.hp - hp).is_equal_approx(70.0, 0.5)


func test_bleed_kill_credits_the_attacker() -> void:
	_world()
	var a := _hero(VESPER, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var foe := _hero(VESPER, Vector3(0.0, 0.05, -10.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var ctx := _ctx(a, foe)
	ctx.skill = _fake_skill({&"bleed": 40.0, &"bleed_time": 3.0})
	foe.combat.health.hp = 5.0
	_server.abilities.apply_skill_dots(ctx, foe)
	_run(HZ)
	assert_bool(foe.combat.dead).is_true()
	assert_int(a.combat.kills).is_equal(1)


# ------------------------------------------------------------------ Hijack

func test_hijacked_trap_triggers_on_its_old_owners_team_then_reverts() -> void:
	_world()
	var j := _hero(JUNIPER, Vector3(30.0, 0.05, 0.0), ServerWorld.TEAM_DUMMIES)
	var hx := _hero(HEX, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var victim := _hero(VESPER, Vector3(30.0, 0.05, -10.0), ServerWorld.TEAM_DUMMIES)
	await get_tree().physics_frame
	var js := j.combat.abilities.skill(0)
	var tc := _ctx(j, null, 0)
	tc.point = victim.state.position + Vector3(0.0, 0.0, 6.0)
	tc.run(js.effects())
	var trap := _server.abilities.deployables[0]
	assert_int(trap.team).is_equal(ServerWorld.TEAM_DUMMIES)
	var spike := hx.combat.abilities.skill(0)
	spike.learn(spike.node_of(SkillNodeDef.Kind.FORK_A))
	var hc := _ctx(hx, null, 0)
	assert_bool((spike.def.effects[0].on_hit[0] as HackEffectDef).hack_gadget(hc, trap)).is_true()
	assert_int(trap.team).is_equal(ServerWorld.TEAM_PLAYERS)
	assert_int(trap.owner_id).is_equal(hx.net_id)
	assert_bool(_server.abilities.traps.is_hijacked(trap)).is_true()
	assert_bool(_server.abilities.traps.is_down(trap)).is_false()  # hijacked, not malfunctioning
	# Walk the old owner's ally into it: it fires against him.
	_server.abilities.teleport(victim, trap.pos + Vector3(0.0, 0.0, 0.3))
	var hp := victim.combat.health.hp
	_run(4 * HZ)
	assert_float(victim.combat.health.hp).is_less(hp)
	# The window ends: back to the owner.
	_run(8 * HZ)
	if trap.alive:
		assert_int(trap.team).is_equal(ServerWorld.TEAM_DUMMIES)
		assert_int(trap.owner_id).is_equal(j.net_id)


func test_hijack_reverts_when_the_window_ends() -> void:
	_world()
	var j := _hero(JUNIPER, Vector3(30.0, 0.05, 0.0), ServerWorld.TEAM_DUMMIES)
	var hx := _hero(HEX, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var tc := _ctx(j, null, 0)
	tc.point = Vector3(30.0, 0.05, -10.0)
	tc.run(j.combat.abilities.skill(0).effects())
	var trap := _server.abilities.deployables[0]
	var spike := hx.combat.abilities.skill(0)
	spike.learn(spike.node_of(SkillNodeDef.Kind.FORK_A))
	(spike.def.effects[0].on_hit[0] as HackEffectDef).hack_gadget(_ctx(hx, null, 0), trap)
	assert_int(trap.team).is_equal(ServerWorld.TEAM_PLAYERS)
	_run(10 * HZ)  # category 6 s x duration scale
	assert_bool(trap.alive).is_true()
	assert_int(trap.team).is_equal(ServerWorld.TEAM_DUMMIES)
	assert_int(trap.owner_id).is_equal(j.net_id)


# ------------------------------------------------------------------ Movement-blocking wall

func _wall_walk(fork: bool, walker_team: int) -> void:
	_world()
	var b := _hero(BRANNOC, Vector3(0.0, 0.05, -12.0), ServerWorld.TEAM_PLAYERS)
	var walker := _hero(VESPER, Vector3(0.0, 0.05, -5.0), walker_team, true)
	await get_tree().physics_frame
	var s := b.combat.abilities.skill(0)
	if fork:
		s.learn(s.node_of(SkillNodeDef.Kind.FORK_A))
	var c := _ctx(b, null, 0)
	c.point = Vector3(0.0, 0.05, 0.0)
	c.yaw = 0.0
	c.run(s.effects())
	_walker = walker


func test_rampart_wall_blocks_enemy_movement_but_not_allies() -> void:
	await _wall_walk(true, ServerWorld.TEAM_DUMMIES)
	var walker := _walker
	assert_int(_server.abilities.deployables.size()).is_equal(1)
	assert_object(_server.abilities.deployables[0].body).is_not_null()
	_run(3 * HZ)
	assert_float(walker.state.position.z).is_less(-0.2)  # stopped at the wall (z 0)


func test_wall_without_rampart_does_not_block_and_ally_passes() -> void:
	await _wall_walk(false, ServerWorld.TEAM_DUMMIES)
	var walker := _walker
	assert_object(_server.abilities.deployables[0].body).is_null()
	_run(3 * HZ)
	assert_float(walker.state.position.z).is_greater(2.0)  # walked through (shots only wall)
	await _wall_walk(true, ServerWorld.TEAM_PLAYERS)
	var ally := _walker
	_run(3 * HZ)
	assert_float(ally.state.position.z).is_greater(2.0)  # the owner's team walks through


func test_rampart_body_is_freed_when_the_wall_ends() -> void:
	await _wall_walk(true, ServerWorld.TEAM_DUMMIES)
	var d := _server.abilities.deployables[0]
	var body := d.body
	d.hp = 0.0  # destroyed
	_run(2)
	assert_bool(d.alive).is_false()
	assert_object(d.body).is_null()
	assert_bool(not is_instance_valid(body) or body.is_queued_for_deletion()).is_true()


# ------------------------------------------------------------------ Expiry hooks

func test_expiry_hook_runs_on_expiry_and_not_before() -> void:
	_world()
	var b := _hero(BRANNOC, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero(BRANNOC, Vector3(0.0, 0.05, -4.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := b.combat.abilities.skill(0)
	s.learn(s.node_of(SkillNodeDef.Kind.MASTERY))
	ally.combat.health.hp = 50.0
	var c := _ctx(b, null, 0)
	c.point = Vector3(0.0, 0.05, -4.0)
	c.run(s.effects())
	c.run(s.node_of(SkillNodeDef.Kind.MASTERY).added_effects)  # registers the hook
	_run(HZ)
	assert_float(ally.combat.health.hp).is_equal(50.0)
	_run(11 * HZ)  # 10 s wall expires
	assert_float(ally.combat.health.hp).is_greater(100.0)


# ------------------------------------------------------------------ Recast (Echo / Rebound)

func test_rebound_second_press_inside_window_slides_again_once() -> void:
	_world()
	var r := _hero("res://assets/data/heroes/hero_ryker_vance.tres", Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := _learn_fork(r, 2, SkillNodeDef.Kind.FORK_B)
	assert_bool(_cast(r, 2)).is_true()
	assert_bool(_cast(r, 2)).is_false()  # still sliding / on cooldown
	_run(20)
	var casts := s.casts
	assert_bool(_cast(r, 2)).is_true()  # second slide, cooldown ignored
	assert_int(s.casts).is_equal(casts)  # not a new cast
	assert_int(s.recast_until_tick).is_equal(-1)  # one use
	_run(20)
	assert_bool(_cast(r, 2)).is_false()


func test_rebound_window_expires() -> void:
	_world()
	var r := _hero("res://assets/data/heroes/hero_ryker_vance.tres", Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	_learn_fork(r, 2, SkillNodeDef.Kind.FORK_B)
	assert_bool(_cast(r, 2)).is_true()
	_run(3 * HZ)  # window is 2 s
	assert_bool(_cast(r, 2)).is_false()


func test_echo_second_press_snaps_back_to_the_start_point() -> void:
	_world()
	var sa := _hero("res://assets/data/heroes/hero_sable.tres", Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	var s := _learn_fork(sa, 1, SkillNodeDef.Kind.FORK_A)
	var start := sa.state.position
	assert_bool(_cast(sa, 1)).is_true()
	_run(HZ)
	assert_float(sa.state.position.distance_to(start)).is_greater(3.0)  # she phased away
	assert_bool(_cast(sa, 1)).is_true()  # Echo
	assert_float(sa.state.position.distance_to(start)).is_less(0.1)
	assert_bool(_cast(sa, 1)).is_false()  # once
	assert_int(s.casts).is_equal(1)


# ------------------------------------------------------------------ Interceptor (ally charge)

func test_interceptor_charges_an_aimed_ally_and_shields_both() -> void:
	_world()
	var b := _hero(BRANNOC, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	var ally := _hero(VESPER, Vector3(0.0, 0.05, -9.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	_learn_fork(b, 1, SkillNodeDef.Kind.FORK_B)
	assert_bool(_cast(b, 1)).is_true()
	_run(HZ)
	assert_bool(b.combat.status.has(StatusComponent.Kind.SHIELD)).is_true()
	assert_bool(ally.combat.status.has(StatusComponent.Kind.SHIELD)).is_true()
	assert_float(ally.combat.health.shield).is_greater(100.0)
	assert_float(b.state.position.distance_to(ally.state.position)).is_less(3.0)


func test_interceptor_without_an_ally_is_a_plain_charge_without_shield() -> void:
	_world()
	var b := _hero(BRANNOC, Vector3(0.0, 0.05, 0.0), ServerWorld.TEAM_PLAYERS)
	await get_tree().physics_frame
	_learn_fork(b, 1, SkillNodeDef.Kind.FORK_B)
	assert_bool(_cast(b, 1)).is_true()
	_run(HZ)
	assert_bool(b.combat.status.has(StatusComponent.Kind.SHIELD)).is_false()
