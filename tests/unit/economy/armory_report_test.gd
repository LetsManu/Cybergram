extends GdUnitTestSuite
## The Armory balance report's simulation (tools/balance/armory_sim.gd,
## docs/armory.md "Balance check"): it buys through the real path, never
## spends Lumen it has not earned, is deterministic, and every hero has a guide.
## The whole report is not built here (about 40 s); the tool run covers it.

const ArmorySim := preload("res://tools/balance/armory_sim.gd")
const VISIT_S := 180

var _sim
var _slice: EconomyRulesDef


func before_test() -> void:
	_sim = ArmorySim.new()
	_slice = load(ArmorySim.SLICE_RULES) as EconomyRulesDef


func _vesper() -> HeroDef:
	for h in _sim.heroes:
		if h.id == &"hero_vesper_loom":
			return h
	return null


func test_every_hero_has_a_guide() -> void:
	assert_int(_sim.heroes.size()).is_equal(7)
	for h in _sim.heroes:
		assert_object(_sim.guides.for_hero(h.id)).is_not_null()


func test_spending_follows_the_guide_and_stays_within_earned_lumen() -> void:
	var earned: Array = ArmorySim.curve(_slice, false)
	assert_int(earned.size()).is_equal(ArmorySim.MATCH_S)
	var h := _vesper()
	var none: Array[HeroDef] = []
	var res: Dictionary = _sim.simulate(h, _sim.guides.for_hero(h.id), _slice, earned, VISIT_S, none)
	var buys: Array = res["buys"]
	assert_bool(buys.size() > 3).is_true()
	assert_str(String(buys[0]["id"])).is_equal("med_pack")  # the opening step
	var last := 0
	var paid := 0
	for b in buys:
		assert_bool(int(b["t"]) % VISIT_S == 0).is_true()  # only on a visit
		assert_bool(int(b["t"]) >= last).is_true()
		last = int(b["t"])
		paid += int(b["cost"])
	assert_bool(int(res["left"]) >= 0).is_true()
	assert_int(paid + int(res["left"])).is_equal(floori(earned[ArmorySim.MATCH_S - 1]))


func test_the_simulation_is_deterministic() -> void:
	# The full report takes about 40 s; one hero against all threat tags is enough here.
	var earned: Array = ArmorySim.curve(_slice, false)
	var h := _vesper()
	var others: Array[HeroDef] = []
	for o in _sim.heroes:
		if o != h:
			others.append(o)
	var a: Dictionary = _sim.simulate(h, _sim.guides.for_hero(h.id), _slice, earned, 0, others)
	var b: Dictionary = ArmorySim.new().simulate(h, _sim.guides.for_hero(h.id), _slice, earned, 0, others)
	assert_array(a["buys"]).is_equal(b["buys"])
	assert_int(int(a["left"])).is_equal(int(b["left"]))
