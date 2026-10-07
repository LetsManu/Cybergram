extends GdUnitTestSuite
## BuildAdvisor on the Armory v2 recipe catalog (items-and-armory.md §3.10):
## guides name finished items with 2-3 choices; the advisor picks the choice
## closest to done and recommends the next part (the goal when affordable,
## else the largest affordable Assembly, else the cheapest stat-giving
## component that fits a slot), never a buy the server would refuse. Every
## v22 guide, followed through ItemShop with unlimited Lumen, reaches the
## full build with no refused purchase.

const HZ: int = 30
const HERO_DIR := "res://assets/data/heroes"

var _cat: ArmoryCatalogDef
var _guides: RecommendedBuildsDef
var _r := EconomyRulesDef.new()
var _ar: AdviceRulesDef
var _bodies: Array[HeroBody] = []


func before_test() -> void:
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_guides = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	_ar = load(AdviceRulesDef.DEFAULT_PATH) as AdviceRulesDef


func after_test() -> void:
	for b in _bodies:
		b.free()
	_bodies.clear()


func _combat(def: HeroDef) -> HeroCombat:
	var h := HeroBody.new()
	h.setup(MovementDef.new(), Vector3.ZERO, false)
	h.combat = HeroCombat.new(def, 0, HZ, 1)
	_bodies.append(h)
	return h.combat


func _heroes() -> Array[HeroDef]:
	var out: Array[HeroDef] = []
	for f in DirAccess.get_files_at(HERO_DIR):
		if f.ends_with(".tres"):
			out.append(load(HERO_DIR.path_join(f)) as HeroDef)
	return out


func _state(p: HeroProgress, def: HeroDef) -> BuildState:
	return BuildState.from_hero(p, _cat, def.weapon, _r)


func _i(id: StringName) -> int:
	return _cat.index_of(id)


func test_v22_guides_are_valid_for_the_v22_catalog() -> void:
	var r := ArmoryValidator.check(_cat, _guides, _heroes(), BuildAdvisor.rule_ids())
	assert_array(Array(r["errors"])).is_empty()
	assert_int(_guides.builds.size()).is_equal(7)


func test_next_part_follows_the_gdd_order() -> void:
	var vesper := CombatFixtures.vesper()
	var p := HeroProgress.new(1)
	p.at_armory = true
	var st := _state(p, vesper)
	var heart := _i(&"ember_heart")
	# 500 Lumen: the Heart (2,550) and the Facet (1,000) are out of reach ->
	# the cheapest missing component that gives stats now.
	st.lumen = 500
	var nxt := BuildAdvisor.next_part(st, heart)
	assert_int(int(nxt["index"])).is_equal(_i(&"lens_part"))
	# 1,200: the largest affordable missing Assembly.
	st.lumen = 1200
	assert_int(int(BuildAdvisor.next_part(st, heart)["index"])).is_equal(_i(&"ember_facet"))
	# Enough for the whole recipe: the goal itself.
	st.lumen = 3000
	nxt = BuildAdvisor.next_part(st, heart)
	assert_int(int(nxt["index"])).is_equal(heart)
	assert_int(int(nxt["cost"])).is_equal(2550)
	# A component already owned would only be a spare: skipped.
	var c := _combat(vesper)
	p.lumen = 400
	ItemShop.buy(p, c, _cat, _i(&"ember_part"), _r)
	st = _state(p, vesper)
	st.lumen = 450
	# Missing: Lens (300) for the Facet, a 2nd Ember Shard, Tempo (350); the
	# owned Ember Shard id would only be a spare -> the cheapest is Lens.
	assert_int(int(BuildAdvisor.next_part(st, heart)["index"])).is_equal(_i(&"lens_part"))


func test_full_slots_never_get_a_component_recommendation() -> void:
	var vesper := CombatFixtures.vesper()
	var p := HeroProgress.new(1)
	p.at_armory = true
	p.lumen = 100000
	var c := _combat(vesper)
	for id in [&"plate_scale", &"null_thread", &"cadence_bead", &"stride_clip", &"steady_part", &"feed_part"]:
		assert_int(ItemShop.buy(p, c, _cat, _i(id), _r)).is_equal(HeroProgress.Result.OK)
	var st := _state(p, vesper)
	st.lumen = 500
	# Ember Heart needs ember/lens/tempo parts: no slot for a loose part.
	var nxt := BuildAdvisor.next_part(st, _i(&"ember_heart"))
	assert_int(int(nxt["index"])).is_equal(_i(&"ember_heart"))  # "save for" the goal


func test_the_choice_closest_to_done_wins() -> void:
	var vesper := CombatFixtures.vesper()
	var p := HeroProgress.new(1)
	p.at_armory = true
	p.lumen = 5000
	var c := _combat(vesper)
	ItemShop.buy(p, c, _cat, _i(&"med_pack"), _r)  # the guide's opening steps
	ItemShop.buy(p, c, _cat, _i(&"ember_part"), _r)
	ItemShop.buy(p, c, _cat, _i(&"pulse_facet"), _r)  # Tempest Heart's Assembly
	var st := _state(p, vesper)
	st.lumen = 0
	var g := _guides.for_hero(&"hero_vesper_loom")
	var core: Array = BuildAdvisor.evaluate(g, st, _ar).advice.filter(
		func(a: BuildAdvisor.Advice) -> bool: return a.node.id == &"core1")
	assert_int(core.size()).is_equal(1)
	assert_int(core[0].goal_index).is_equal(_i(&"tempest_heart"))  # not the guide's first choice


func test_every_guide_reaches_the_full_build_through_the_server_rules() -> void:
	for def in _heroes():
		var g := _guides.for_hero(def.id)
		assert_object(g).is_not_null()
		var p := HeroProgress.new(1)
		p.at_armory = true
		p.lumen = 60000
		var c := _combat(def)
		var refused := 0
		for step in 80:
			var st := _state(p, def)
			var best := BuildAdvisor.evaluate(g, st, _ar).best()
			if best == null:
				break
			var r := ItemShop.buy(p, c, _cat, best.item_index, _r)
			if r != HeroProgress.Result.OK:
				refused += 1
				break
		assert_int(refused).override_failure_message("%s: a recommended buy was refused" % def.id).is_equal(0)
		var inv := p.inv
		assert_int(inv.signature_count(_cat)).override_failure_message("%s signatures" % def.id).is_equal(2)
		for loc in [ItemInventory.LOC_CORE, ItemInventory.LOC_BARREL, ItemInventory.LOC_FRAME, ItemInventory.LOC_AMMO]:
			assert_int(inv.index_at(loc)).override_failure_message("%s place %d empty" % [def.id, loc]).is_not_equal(-1)
		assert_int(inv.slots.size()).override_failure_message("%s slots" % def.id).is_equal(6)
