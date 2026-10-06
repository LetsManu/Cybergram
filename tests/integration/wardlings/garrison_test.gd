extends GdUnitTestSuite
## C5 Garrison Sentinels (wardlings-and-economy.md §11, match-flow-and-map.md
## §3.5) on Shardline Front: 2 per held hardpoint from the start, 10 s after a
## capture for the new owner, the old ones dissolve over 2 s with no bounty, a
## dead Sentinel respawns after 45 s, they shoot enemy heroes in range without
## leaving the zone, follow the Surge tier, respect the AI budget, and pay
## 1.5 x the squad bounty with RepeatDecay.

const HZ: int = 30
const MAP := "res://assets/data/match/map_front.tres"
const C := MapDef.TEAM_CONCORD
const SY := MapDef.TEAM_SYNDICATE

var _server: ServerWorld
## Keeps the RefCounted WardlingDirector alive (think_hook does not hold it).
var _built: Array = []


func _build(budget: int = 110) -> ServerWorld:
	var rules := WardlingFixtures.rules()
	rules.ai_agent_budget = budget
	var md := load(MAP) as MapDef
	var built := WardlingFixtures.slice_server(self, rules, false,
		load("res://assets/data/match/match_rules_front.tres") as MatchRulesDef, md)
	auto_free(built[3])
	_built = built
	_server = built[0]
	_server.enable_progression(EconomyRulesDef.new(), ArmoryCatalogDef.new(), md)
	return _server


func _step(seconds: float) -> void:
	for i in roundi(seconds * HZ):
		_server.step()


func _held() -> Array:
	return _server.objectives.all.filter(func(h: HardpointSim) -> bool:
		return h.owner != MapDef.TEAM_NEUTRAL and not h.def.garrison_points.is_empty())


func _sentinels(hp: HardpointSim) -> Array:
	var g: Garrison = _server.wardlings.garrisons.get(hp)
	return [] if g == null else g.members.filter(func(m: Variant) -> bool: return m != null)


func test_every_held_hardpoint_starts_with_two_sentinels() -> void:
	_build()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server, load(MAP))).is_true()
	_step(0.2)
	var held := _held()
	assert_int(held.size()).is_equal(12)
	var n := 0
	for hp: HardpointSim in held:
		assert_int(_sentinels(hp).size()).is_equal(2)
		n += 2
	assert_int(n).is_equal(24)
	var mid := _server.objectives.find(&"c_mid")
	assert_object(_server.wardlings.garrisons.get(mid)).is_null()
	var w: WardlingSim = _sentinels(held[0])[0]
	assert_float(w.health.max_hp).is_equal(450.0)
	assert_float(w.def.range_m).is_equal(26.0)


func test_flip_dissolves_without_bounty_and_settles_after_ten_seconds() -> void:
	_build()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server, load(MAP))).is_true()
	_step(0.2)
	var hp: HardpointSim = _held()[0]
	var old_team := hp.owner
	var old: Array = _sentinels(hp)
	var removed := []
	_server.wardlings.wardling_removed.connect(func(w: WardlingSim, k: int) -> void: removed.append([w, k]))
	_server.objectives.debug_set_owner(hp.def.id, 1 - old_team)
	_step(1.0)
	assert_bool((old[0] as WardlingSim).dead).is_false()  # dissolving over 2 s
	_step(1.2)
	var gone := removed.filter(func(r: Array) -> bool: return old.has(r[0]))
	assert_int(gone.size()).is_equal(2)
	for r: Array in gone:
		assert_int(int(r[1])).is_equal(0)  # no killer: no bounty
	assert_int(_sentinels(hp).size()).is_equal(0)
	_step(7.0)  # 9.2 s after the flip
	assert_int(_sentinels(hp).size()).is_equal(0)
	_step(1.0)
	assert_int(_sentinels(hp).size()).is_equal(2)
	assert_int((_sentinels(hp)[0] as WardlingSim).team).is_equal(1 - old_team)


func test_a_dead_sentinel_respawns_after_forty_five_seconds() -> void:
	_build()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server, load(MAP))).is_true()
	_step(0.2)
	var hp: HardpointSim = _held()[0]
	var w: WardlingSim = _sentinels(hp)[0]
	_server.wardlings.damage_wardling(w, DamageInfo.make(99999.0, 0, 1 - w.team))
	_step(0.2)
	assert_int(_sentinels(hp).size()).is_equal(1)
	_step(44.0)
	assert_int(_sentinels(hp).size()).is_equal(1)
	_step(1.5)
	assert_int(_sentinels(hp).size()).is_equal(2)


func test_sentinels_shoot_an_enemy_hero_and_stay_in_the_zone() -> void:
	_build()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server, load(MAP))).is_true()
	_step(0.2)
	var hp: HardpointSim = _held()[0]
	var foe := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()),
		hp.def.position + Vector3(0.0, 0.05, 4.0), CombatFixtures.brannoc(), 1 - hp.owner)
	var h := _server.hero(foe)
	var hp0 := h.combat.health.hp
	_step(4.0)
	assert_float(h.combat.health.hp).is_less(hp0)
	for w: WardlingSim in _sentinels(hp):
		var d := Vector2(w.global_position.x - hp.def.position.x, w.global_position.z - hp.def.position.z).length()
		assert_float(d).is_less_equal(hp.def.zone_radius + 0.5)


func test_sentinels_follow_the_surge_tier_keeping_their_hp_fraction() -> void:
	_build()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), _server, load(MAP))).is_true()
	_step(0.2)
	var hp: HardpointSim = _held()[0]
	var w: WardlingSim = _sentinels(hp)[0]
	w.health.hp = 225.0  # 50 %
	_server.wardlings.tier = 2
	_step(0.1)
	assert_int(w.tier).is_equal(2)
	assert_float(w.health.max_hp).is_equal(590.0)
	assert_float(w.health.hp).is_equal_approx(295.0, 0.01)


func test_the_ai_budget_caps_garrison_mints() -> void:
	_build(10)
	_step(0.2)
	var n := 0
	for g: Garrison in _server.wardlings.garrisons.values():
		n += g.alive_count()
	assert_int(n).is_equal(10)


func test_sentinel_bounty_is_one_and_a_half_with_repeat_decay() -> void:
	_build()
	var hp: HardpointSim = _held()[0]
	var pr := _server.progression
	assert_float(pr.sentinel_bounty_mult(hp, 100.0)).is_equal(1.5)
	assert_float(pr.sentinel_bounty_mult(hp, 200.0)).is_equal(0.75)  # within 180 s
	assert_float(pr.sentinel_bounty_mult(hp, 400.0)).is_equal(1.5)  # 200 s later
