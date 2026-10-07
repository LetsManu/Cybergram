extends GdUnitTestSuite
## Signature passives through a real ServerWorld (items-and-armory.md §3.5.3, §5):
## bought through the v22 shop (active item copies), applied on real hits,
## kills and deaths; sold = off; v1 catalog = none.

var _server: ServerWorld
var _link: LoopbackLink
var _net: NetConfig


func _world(catalog_path: String = ArmoryCatalogDef.DEFAULT_PATH) -> void:
	_net = NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(_net, MovementDef.new(), CombatFixtures.range_scene(false), _link.create_endpoint(1),
		CombatFixtures.vesper(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	_server.enable_progression(load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef,
		load(catalog_path) as ArmoryCatalogDef)
	_server.progression.debug_shop_anywhere = true
	_server.progression.armory_log = false


func _tick(n: int) -> void:
	for i in n:
		_link.advance(_net.tick_dt())
		_server.step()


## Vesper with a Threadcaster whose base falloff starts at `falloff_start` m.
func _vesper(falloff_start: float = 25.0) -> HeroDef:
	var d := CombatFixtures.vesper().duplicate() as HeroDef
	d.weapon = d.weapon.duplicate() as WeaponDef
	d.weapon.falloff_start_m = falloff_start
	return d


## [shooter, target]: the shooter fires at the target 8 m ahead every `period` ticks.
func _duel(period: int, falloff_start: float = 25.0) -> Array[HeroBody]:
	_world()
	var target := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("DummySpawn1"), _vesper(), ServerWorld.TEAM_DUMMIES)
	var shooter := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.shooter_input(8.0, period)),
		_server.spawn_point("PlayerSpawn"), _vesper(falloff_start), ServerWorld.TEAM_PLAYERS)
	return [_server.hero(shooter), _server.hero(target)]


func _buy(h: HeroBody, id: StringName) -> void:
	_server.progression.progress_of(h).lumen = 20000.0
	assert_int(_server.buy(h, id)).override_failure_message("buy %s" % id).is_equal(HeroProgress.Result.OK)


func test_bought_lattice_gives_overshield_and_selling_it_clears_it() -> void:
	_world()
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("PlayerSpawn"), _vesper(), ServerWorld.TEAM_PLAYERS)
	var h := _server.hero(id)
	await get_tree().physics_frame
	_buy(h, &"barrier_lattice")
	_tick(1)
	assert_bool(h.combat.passives.has(SignaturePassives.LATTICE)).is_true()
	assert_float(h.combat.health.overshield).is_equal(80.0)
	var p := _server.progression.progress_of(h)
	p.at_armory = true
	var loc := ItemInventory.LOC_SLOT + p.inv.slots.find(p.inv.slots.filter(
		func(e: ItemInventory.Entry) -> bool: return e.index == _server.progression.catalog.index_of(&"barrier_lattice"))[0])
	assert_int(ItemShop.sell(p, h.combat, _server.progression.catalog, loc, _server.progression.rules)).is_equal(HeroProgress.Result.OK)
	_tick(1)
	assert_bool(h.combat.passives.has(SignaturePassives.LATTICE)).is_false()
	assert_float(h.combat.health.overshield).is_equal(0.0)


func test_lattice_soaks_real_gunfire_before_hp() -> void:
	var pair := _duel(1000)
	await get_tree().physics_frame
	_buy(pair[1], &"barrier_lattice")
	var hp := pair[1].combat.health.hp
	_tick(3)  # one Threadcaster body hit: 29, all into the 80-point overshield
	assert_float(pair[1].combat.health.hp).is_equal(hp)
	assert_float(pair[1].combat.health.overshield).is_equal_approx(80.0 - 29.0, 0.01)  # Lattice resist is skill-only


func test_breaker_bore_hits_put_rend_on_the_target() -> void:
	var pair := _duel(6)
	await get_tree().physics_frame
	_buy(pair[0], &"breaker_bore")
	_tick(40)
	assert_bool(pair[1].combat.dead).is_false()
	assert_float(pair[1].combat.health.rend).is_equal_approx(0.08, 1e-6)
	assert_float(pair[1].combat.passives.rend).is_equal_approx(0.08, 1e-6)


func test_long_reach_slows_hits_beyond_base_falloff_start() -> void:
	var pair := _duel(1000, 5.0)
	await get_tree().physics_frame
	_buy(pair[0], &"longsight_lens")
	_tick(3)
	assert_float(pair[1].combat.status.slow_total()).is_equal_approx(0.10, 1e-6)


func test_long_reach_ignores_hits_inside_base_falloff_start() -> void:
	var pair := _duel(1000, 25.0)
	await get_tree().physics_frame
	_buy(pair[0], &"longsight_lens")
	_tick(3)
	assert_float(pair[1].combat.status.slow_total()).is_equal(0.0)


func test_kindle_refills_the_pool_on_a_kill() -> void:
	var pair := _duel(1000)
	await get_tree().physics_frame
	_buy(pair[0], &"ember_heart")
	var f := pair[0].combat.weapon.feed as ManaPoolFeed
	pair[1].combat.health.hp = 1.0
	f.mana = 10.0
	_tick(2)  # the first shot (-6 mana) kills
	assert_bool(pair[1].combat.dead).is_true()
	assert_float(f.mana).is_greater_equal(10.0 - 6.0 + 0.3 * f.max_pool() - 1e-3)


func test_no_kindle_without_the_signature() -> void:
	var pair := _duel(1000)
	await get_tree().physics_frame
	var f := pair[0].combat.weapon.feed as ManaPoolFeed
	pair[1].combat.health.hp = 1.0
	f.mana = 10.0
	_tick(2)
	assert_bool(pair[1].combat.dead).is_true()
	assert_float(f.mana).is_less(10.0)


func test_death_ends_the_victims_passive_state() -> void:
	var pair := _duel(1000)
	await get_tree().physics_frame
	_buy(pair[1], &"barrier_lattice")
	_tick(2)
	var t := pair[1]
	assert_bool(t.combat.passives.has(SignaturePassives.LATTICE)).is_true()
	t.combat.health.overshield = 0.0
	_server.damage_hero(t, DamageInfo.make(10000.0, 0, -1, 0, DamageInfo.Type.TRUE))
	assert_bool(t.combat.dead).is_true()
	assert_float(t.combat.health.overshield).is_equal(0.0)
	assert_int(t.combat.passives.last_damaged_tick).is_equal(SignaturePassives.NEVER)


func test_a_loadout_without_a_signature_turns_no_passive_on() -> void:
	_world()
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		_server.spawn_point("PlayerSpawn"), _vesper(), ServerWorld.TEAM_PLAYERS)
	var h := _server.hero(id)
	await get_tree().physics_frame
	_server.progression.progress_of(h).lumen = 20000.0
	_server.buy(h, &"ember_part")  # a Component, not a Signature
	_tick(5)
	assert_bool(h.combat.passives.active.is_empty()).is_true()
