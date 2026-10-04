extends GdUnitTestSuite
## W11-M1: Reveal, Bleed / Healing reduction, Hijack, movement-blocking wall,
## expiry hooks and recast mechanics on a real ServerWorld.

const HZ: int = 30
const VESPER := "res://assets/data/heroes/hero_vesper_loom.tres"
const BRANNOC := "res://assets/data/heroes/hero_brannoc.tres"

var _server: ServerWorld
var _link: LoopbackLink


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
