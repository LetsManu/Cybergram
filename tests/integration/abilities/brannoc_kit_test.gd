extends GdUnitTestSuite
## Brannoc's kit on a real ServerWorld (design/gdd/heroes.md §4.5), casting
## through InputCommand skill buttons (the server-authoritative path):
## Aegis Wall blocks an enemy's hitscan; Ram Charge moves 12 m, damages and
## carries the first hero, and pins into a wall (+damage, stun); Earthbreaker
## (via the --grant-ult debug flag) leaps, slams and stuns.

const HZ: int = 30

var _server: ServerWorld
var _link: LoopbackLink
var _net: NetConfig


## Scripted hero that presses `button` on tick `press_tick` with a fixed aim.
class Caster extends ScriptedInputSource:
	var press_tick: int = 0
	var button: int = 0
	var yaw: float = 0.0
	var pitch: float = 0.0

	func _init() -> void:
		super(CombatFixtures.idle_input())

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		out.yaw = yaw
		out.pitch = pitch
		if seq == press_tick:
			out.buttons |= button
		out.quantize()


func _world(scene: PackedScene) -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(_net, MovementDef.new(), scene, _link.create_endpoint(1), CombatFixtures.brannoc(),
		load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)


func _caster(button: int, tick: int, pitch: float, at: Vector3) -> HeroBody:
	var c := Caster.new()
	c.button = button
	c.press_tick = tick
	c.pitch = pitch
	return _server.hero(_server.add_scripted_hero(c, at, CombatFixtures.brannoc(), ServerWorld.TEAM_PLAYERS))


func _run(n: int) -> void:
	for i in n:
		_server.step()


func test_aegis_wall_blocks_enemy_hitscan() -> void:
	_world(CombatFixtures.range_scene(false))
	# Brannoc at the origin facing -Z places the wall 4 m ahead at tick 25.
	var brannoc := _caster(InputCommand.BTN_SKILL1, 25, -atan2(1.62, 4.0), _server.spawn_point("PlayerSpawn"))
	# An enemy Vesper 8 m ahead fires at his chest every 2 ticks from tick 0.
	var aim := CombatFixtures.shooter_input(8.0, 2)
	aim.start_yaw_deg = 180.0
	var shooter := _server.hero(_server.add_scripted_hero(ScriptedInputSource.new(aim),
		_server.spawn_point("DummySpawn1"), CombatFixtures.vesper(), ServerWorld.TEAM_DUMMIES))
	await get_tree().physics_frame
	_run(25)  # ticks 0..24
	var hp_before_wall := brannoc.combat.health.hp
	assert_float(hp_before_wall).is_less(550.0)  # control: shots land without the wall
	_run(1)  # tick 25: the wall goes up before the shooter's next shot
	var wall: AbilityWorld.Deployable = _server.abilities.deployables[0] if not _server.abilities.deployables.is_empty() else null
	assert_object(wall).is_not_null()
	assert_float(wall.pos.z).is_equal_approx(-4.0, 0.5)
	assert_float(wall.width).is_equal(6.0)
	assert_float(wall.max_hp).is_equal(1200.0)
	var shots := shooter.combat.weapon.shots_fired
	_run(90)
	var fired := shooter.combat.weapon.shots_fired - shots
	assert_int(fired).is_greater_equal(8)
	assert_float(brannoc.combat.health.hp).is_equal(hp_before_wall)
	assert_int(_server.abilities.blocked_shots).is_equal(fired)  # every shot stopped by the wall
	assert_float(wall.hp).is_less(1200.0)
	assert_float(1200.0 - wall.hp).is_equal_approx(wall.absorbed, 1e-3)
	# The wall is ACTIVE for its 10 s; its 18 s cooldown starts when it ends.
	var s1 := brannoc.combat.abilities.skill(0)
	assert_bool(s1.active).is_true()
	assert_bool(s1.on_cooldown(_server.tick)).is_false()
	_run(300 - 90)
	assert_bool(_server.abilities.deployables.is_empty()).is_true()
	assert_bool(s1.active).is_false()
	assert_int(s1.cooldown_ticks_left(_server.tick)).is_between(18 * HZ - 2, 18 * HZ)
	# Allies shoot through it: Brannoc's own pellets were never clipped (no friendly blocking).
	assert_int(_server.abilities.block_distance(Vector3(0, 1.6, 0), Vector3.FORWARD, 20.0, ServerWorld.TEAM_PLAYERS).size()).is_equal(0)


func test_ram_charge_moves_12_m_and_carries_the_first_hero() -> void:
	_world(CombatFixtures.range_scene(false))
	var brannoc := _caster(InputCommand.BTN_SKILL2, 5, 0.0, _server.spawn_point("PlayerSpawn"))
	var target := _server.hero(_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		Vector3(0.0, 0.05, -4.0), CombatFixtures.vesper(), ServerWorld.TEAM_DUMMIES))
	await get_tree().physics_frame
	var start := brannoc.state.position
	var target_start := target.state.position
	_run(5 + 6 + 30)  # press, 0.2 s wind-up, 0.8 s charge and a margin
	var moved := start.z - brannoc.state.position.z
	assert_float(moved).is_between(11.0, 12.6)
	assert_float(target.combat.health.hp).is_equal_approx(250.0 - 60.0, 1e-3)
	assert_float(target_start.z - target.state.position.z).is_greater(6.0)  # carried along
	assert_int(_server.abilities.pins).is_equal(0)
	assert_bool(brannoc.combat.abilities.skill(1).on_cooldown(_server.tick)).is_true()
	assert_bool(brannoc.combat.abilities.is_dashing()).is_false()


func test_ram_charge_pins_into_a_wall_for_bonus_damage_and_a_stun() -> void:
	_world(CombatFixtures.range_scene(true))  # 4 x 3 m wall centred at z = -4
	var brannoc := _caster(InputCommand.BTN_SKILL2, 5, 0.0, _server.spawn_point("PlayerSpawn"))
	var target := _server.hero(_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		Vector3(0.0, 0.05, -2.2), CombatFixtures.vesper(), ServerWorld.TEAM_DUMMIES))
	await get_tree().physics_frame
	var stunned := false
	for i in 30:
		_server.step()
		stunned = stunned or target.combat.status.is_stunned()
	assert_int(_server.abilities.pins).is_equal(1)
	assert_float(target.combat.health.hp).is_equal_approx(250.0 - 60.0 - 60.0, 1e-3)
	assert_bool(stunned).is_true()
	assert_float(brannoc.state.position.z).is_greater(-3.75)  # stopped at the wall


func test_earthbreaker_leaps_slams_and_stuns_with_grant_ult() -> void:
	_world(CombatFixtures.range_scene(false))
	_server.abilities.grant_ult = true
	var brannoc := _caster(InputCommand.BTN_SKILL4, 5, -atan2(1.62, 10.0), _server.spawn_point("PlayerSpawn"))
	var target := _server.hero(_server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		Vector3(0.0, 0.05, -12.0), CombatFixtures.vesper(), ServerWorld.TEAM_DUMMIES))
	await get_tree().physics_frame
	var stunned := false
	var max_y := 0.0
	for i in 5 + 18 + 4:
		_server.step()
		stunned = stunned or target.combat.status.is_stunned()
		max_y = maxf(max_y, brannoc.state.position.y)
	assert_float(brannoc.state.position.z).is_equal_approx(-10.0, 1.0)
	assert_float(max_y).is_greater(0.6)  # a leap (apex g·T²/8 = 0.9 m), not a walk
	assert_float(target.combat.health.hp).is_equal_approx(250.0 - 120.0, 1e-3)
	assert_bool(stunned).is_true()
	assert_bool(brannoc.combat.abilities.skill(3).on_cooldown(_server.tick)).is_true()
	# Bastion zone: Brannoc stands in it and takes 25% less damage.
	_server.step()
	assert_bool(brannoc.combat.status.has(StatusComponent.Kind.DR)).is_true()
