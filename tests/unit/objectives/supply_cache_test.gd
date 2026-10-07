extends GdUnitTestSuite
## C5 Supply Cache (match-flow-and-map.md §3.5, weapons-and-mods.md §3.5):
## switches 10 s after a flip, refills Mechanical reserve 25 %/s within 3 m,
## cuts the Mana regen delay 50 % for 10 s on touch with an 8 s cooldown,
## serves only the owner and only living heroes.

const HZ := 30
const DT := 1.0 / HZ
const C := MapDef.TEAM_CONCORD
const SY := MapDef.TEAM_SYNDICATE

var _bodies: Array[HeroBody] = []
var _obj: ObjectiveSystem
var _sys: SupplyCacheSystem
var _hp: HardpointSim
## The cache under test: a Mid's (starts neutral).
var _i := 0
var _t := 0.0
var _tick := 0


func before_test() -> void:
	var md := load("res://assets/data/match/map_front.tres") as MapDef
	_obj = ObjectiveSystem.new(md, MatchRulesDef.new())
	_sys = SupplyCacheSystem.new(_obj, MatchRulesDef.new())
	_i = _sys.caches.find_custom(func(c: Dictionary) -> bool: return (c.hp as HardpointSim).owner == MapDef.TEAM_NEUTRAL)
	_hp = _sys.caches[_i].hp
	_t = 100.0
	_tick = 0


func after_test() -> void:
	for b in _bodies:
		b.free()
	_bodies.clear()


func _hero(team: int, weapon: WeaponDef, at: Vector3) -> HeroBody:
	var def := CombatFixtures.brannoc().duplicate() as HeroDef
	def.weapon = weapon
	var h := HeroBody.new()
	h.setup(MovementDef.new(), at, false)
	h.combat = HeroCombat.new(def, team, HZ, 1)
	h.net_id = 10 + _bodies.size()
	_bodies.append(h)
	return h


func _run(seconds: float, heroes: Array) -> void:
	for i in roundi(seconds * HZ):
		_t += DT
		_tick += 1
		_sys.step(DT, _t, _tick, HZ, heroes)
		for h: HeroBody in heroes:
			h.combat.stats.expire(_tick)


func _cache_at() -> Vector3:
	return _sys.caches[_i].at


func test_every_map_hardpoint_with_a_spot_has_a_cache() -> void:
	assert_int(_sys.caches.size()).is_equal(15)


func test_switch_waits_for_the_delay_after_a_flip() -> void:
	assert_int(SupplyCacheSystem.owner_at(MapDef.TEAM_NEUTRAL, 0.0, 99.0, 10.0)).is_equal(MapDef.TEAM_NEUTRAL)
	assert_int(SupplyCacheSystem.owner_at(C, 50.0, 59.9, 10.0)).is_equal(MapDef.TEAM_NEUTRAL)
	assert_int(SupplyCacheSystem.owner_at(C, 50.0, 60.0, 10.0)).is_equal(C)
	_obj.debug_set_owner(_hp.def.id, C)
	_run(9.0, [])
	assert_int(int(_sys.caches[_i].owner)).is_equal(MapDef.TEAM_NEUTRAL)
	_run(1.5, [])
	assert_int(int(_sys.caches[_i].owner)).is_equal(C)


func test_mechanical_refill_is_a_quarter_of_max_reserve_per_second() -> void:
	_obj.debug_set_owner(_hp.def.id, C)
	_run(11.0, [])
	var h := _hero(C, CombatFixtures.rifle_mag(), _cache_at() + Vector3(2.0, 0, 0))
	var feed := h.combat.weapon.feed as MagazineFeed
	feed.reserve = 0
	_run(1.0, [h])
	assert_int(feed.reserve_count()).is_between(36, 38)  # 25 % of 150
	_run(3.5, [h])
	assert_int(feed.reserve_count()).is_equal(150)


## Deep Reserve (Reservoir Frame, items-and-armory.md §3.5.3): Mech refills +50%.
func test_deep_reserve_refills_half_again_as_fast() -> void:
	_obj.debug_set_owner(_hp.def.id, C)
	_run(11.0, [])
	var h := _hero(C, CombatFixtures.rifle_mag(), _cache_at() + Vector3(2.0, 0, 0))
	h.combat.passives.set_active([SignaturePassives.DEEP_RESERVE], _tick)
	var feed := h.combat.weapon.feed as MagazineFeed
	feed.reserve = 0
	_run(1.0, [h])
	assert_int(feed.reserve_count()).is_between(55, 57)  # 37.5 %/s of 150


func test_no_refill_outside_the_radius_for_enemies_or_the_dead() -> void:
	_obj.debug_set_owner(_hp.def.id, C)
	_run(11.0, [])
	var far := _hero(C, CombatFixtures.rifle_mag(), _cache_at() + Vector3(3.5, 0, 0))
	var foe := _hero(SY, CombatFixtures.rifle_mag(), _cache_at())
	var dead := _hero(C, CombatFixtures.rifle_mag(), _cache_at())
	dead.combat.dead = true
	for h in [far, foe, dead]:
		(h.combat.weapon.feed as MagazineFeed).reserve = 0
	_run(2.0, [far, foe, dead])
	for h in [far, foe, dead]:
		assert_int((h.combat.weapon.feed as MagazineFeed).reserve_count()).is_equal(0)


func test_neutral_cache_serves_nobody() -> void:
	var h := _hero(C, CombatFixtures.rifle_mag(), _cache_at())
	(h.combat.weapon.feed as MagazineFeed).reserve = 0
	_run(2.0, [h])
	assert_int((h.combat.weapon.feed as MagazineFeed).reserve_count()).is_equal(0)


func test_mana_touch_halves_the_regen_delay_for_ten_seconds_with_a_cooldown() -> void:
	_obj.debug_set_owner(_hp.def.id, C)
	_run(11.0, [])
	var gun := CombatFixtures.auto_gun(10.0)
	gun.mana_regen_delay_s = 2.0
	var h := _hero(C, gun, _cache_at() + Vector3(1.0, 0, 0))
	var feed := h.combat.weapon.feed
	assert_float(feed.regen_delay_s()).is_equal_approx(2.0, 1e-4)
	_run(0.1, [h])
	assert_bool(SupplyCacheSystem.has_buff(h)).is_true()
	assert_float(feed.regen_delay_s()).is_equal_approx(1.0, 1e-4)
	# walk away: the buff runs out after 10 s
	h.state.position = _cache_at() + Vector3(20, 0, 0)
	_run(10.1, [h])
	assert_bool(SupplyCacheSystem.has_buff(h)).is_false()
	assert_float(feed.regen_delay_s()).is_equal_approx(2.0, 1e-4)


func test_mana_touch_cooldown_blocks_a_second_buff_within_eight_seconds() -> void:
	_obj.debug_set_owner(_hp.def.id, C)
	_run(11.0, [])
	var h := _hero(C, CombatFixtures.auto_gun(10.0), _cache_at())
	_run(0.1, [h])
	var first: float = float(_sys._touched[h.net_id])
	_run(5.0, [h])  # still touching
	assert_float(float(_sys._touched[h.net_id])).is_equal(first)
	_run(3.5, [h])
	assert_float(float(_sys._touched[h.net_id])).is_greater(first)


func test_flip_stops_service_until_the_new_owner_settles() -> void:
	_obj.debug_set_owner(_hp.def.id, C)
	_run(11.0, [])
	_obj.debug_set_owner(_hp.def.id, SY)
	var h := _hero(C, CombatFixtures.rifle_mag(), _cache_at())
	var foe := _hero(SY, CombatFixtures.rifle_mag(), _cache_at())
	(h.combat.weapon.feed as MagazineFeed).reserve = 0
	(foe.combat.weapon.feed as MagazineFeed).reserve = 0
	_run(5.0, [h, foe])
	assert_int((h.combat.weapon.feed as MagazineFeed).reserve_count()).is_equal(0)
	assert_int((foe.combat.weapon.feed as MagazineFeed).reserve_count()).is_equal(0)
	_run(6.0, [h, foe])
	assert_int((foe.combat.weapon.feed as MagazineFeed).reserve_count()).is_greater(0)
