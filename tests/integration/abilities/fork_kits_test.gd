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
