extends GdUnitTestSuite
## The Armory balance report's simulation (tools/balance/armory_sim.gd,
## docs/armory.md "Balance check"): it buys through the real path (BuildAdvisor
## -> ItemShop.buy), never spends Lumen it has not earned, is deterministic, and
## every hero has a guide. The whole report is not built here; the tool run covers it.

const ArmorySim := preload("res://tools/balance/armory_sim.gd")
const VISIT_S := 180

var _sim
var _slice: EconomyRulesDef


func before_test() -> void:
	_sim = ArmorySim.new()
	_slice = load(ArmorySim.SLICE_RULES) as EconomyRulesDef


func _hero(id: StringName) -> HeroDef:
	for h in _sim.heroes:
		if h.id == id:
			return h
	return null


func test_every_hero_has_a_guide() -> void:
	assert_int(_sim.heroes.size()).is_equal(7)
	for h in _sim.heroes:
		assert_object(_sim.guides.for_hero(h.id)).is_not_null()


func test_spending_stays_within_earned_lumen_and_buys_only_on_a_visit() -> void:
	var earned: Array = ArmorySim.curve(_slice, false)
	assert_int(earned.size()).is_equal(ArmorySim.MATCH_S)
	var h := _hero(&"hero_ryker_vance")
	var run: Dictionary = _sim.simulate(h, _sim.guides.for_hero(h.id), _slice, earned, VISIT_S)
	var buys: Array = run["buys"]
	assert_bool(buys.size() > 3).is_true()
	var last := 0
	for b in buys:
		assert_int(int(b["t"]) % VISIT_S).is_equal(0)  # only on a visit
		assert_bool(int(b["t"]) >= last).is_true()
		last = int(b["t"])
	var paid := int(run["items"]) + int(run["squad"]) + int(run["consumables"])
	assert_bool(int(run["left"]) >= 0).is_true()
	assert_int(paid + int(run["left"])).is_less_equal(floori(earned[ArmorySim.MATCH_S - 1]))
	assert_int(int(run["first_sig"])).is_greater(0)


func test_the_simulation_is_deterministic() -> void:
	var earned: Array = ArmorySim.curve(_slice, false)
	var h := _hero(&"hero_vesper_loom")
	var a: Dictionary = _sim.simulate(h, _sim.guides.for_hero(h.id), _slice, earned, 0)
	var b: Dictionary = ArmorySim.new().simulate(h, _sim.guides.for_hero(h.id), _slice, earned, 0)
	assert_array(a["buys"]).is_equal(b["buys"])
	assert_int(int(a["left"])).is_equal(int(b["left"]))
