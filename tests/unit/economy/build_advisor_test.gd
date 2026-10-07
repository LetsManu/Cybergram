extends GdUnitTestSuite
## BuildAdvisor on the v22 catalog and guides (docs/armory.md): simple builds
## keep the first-unowned behaviour; guides open nodes by prerequisites, honour alternatives,
## fallbacks, skippable / optional nodes and time windows; situational rules
## (server signals, enemy threat tags, team roles) change the ranking and give
## the reason; affordability flags; a trace explains every decision; every hero
## ships a guide that starts sensibly.

var _cat: ArmoryCatalogDef
var _builds: RecommendedBuildsDef
var _ar: AdviceRulesDef


func before_test() -> void:
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_builds = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	_ar = load(AdviceRulesDef.DEFAULT_PATH) as AdviceRulesDef


func _state(weapon: WeaponDef, lumen: int, own: Dictionary = {}) -> BuildState:
	var st := BuildState.new()
	st.catalog = _cat
	st.weapon = weapon
	st.lumen = lumen
	st.team_size = 5
	for id in own:
		st.holdings[_cat.index_of(id)] = own[id]
	return st


func _mana() -> WeaponDef:
	return CombatFixtures.vesper().weapon


func _mech() -> WeaponDef:
	return CombatFixtures.brannoc().weapon


func _guide(hero: StringName) -> RecommendedBuildDef:
	return _builds.for_hero(hero)


func _best_item(r: BuildAdvisor.Result) -> StringName:
	return _cat.at(r.best().item_index).id if r.best() != null else &""


## Id of the guide node the advisor picks (the item it names is a part of the node's goal).
func _best_node(r: BuildAdvisor.Result) -> StringName:
	return r.best().node.id if r.best() != null else &""


func _node_ids(r: BuildAdvisor.Result) -> Array:
	var out: Array = []
	for a in r.advice:
		out.append(String(a.node.id))
	return out


func _node(id: StringName, item: StringName, prio: int, requires: Array = [], target := 1) -> BuildNodeDef:
	var n := BuildNodeDef.new()
	n.id = id
	n.item_id = item
	n.priority = prio
	n.target = target
	n.requires = PackedStringArray(requires)
	return n


func _custom(nodes: Array) -> RecommendedBuildDef:
	var b := RecommendedBuildDef.new()
	b.hero_id = &"t"
	for n in nodes:
		b.nodes.append(n)
	return b


func test_simple_build_recommends_the_first_unowned_step_that_is_sold() -> void:
	var b := RecommendedBuildDef.new()
	b.item_ids = PackedStringArray(["med_pack", "ammo_shock", "squad_expansion_1", "squad_expansion_2"])
	b.targets = PackedInt32Array([1, 1, 1, 1])
	_cat = _cat.duplicate(true) as ArmoryCatalogDef
	_cat.find(&"ammo_shock").disabled = true
	var st := _state(_mana(), 5000)
	assert_str(String(_best_item(BuildAdvisor.evaluate(b, st, _ar)))).is_equal("med_pack")
	st.holdings[_cat.index_of(&"med_pack")] = 1
	# Shock Rounds are switched off: skipped, the list continues.
	var r := BuildAdvisor.evaluate(b, st, _ar)
	assert_str(String(_best_item(r))).is_equal("squad_expansion_1")
	assert_int(r.best().cost).is_equal(800)
	st.holdings[_cat.index_of(&"squad_expansion_1")] = 1
	r = BuildAdvisor.evaluate(b, st, _ar)
	assert_str(String(_best_item(r))).is_equal("squad_expansion_2")


func test_every_hero_has_a_guide_that_opens_with_a_med_pack_then_the_first_mount() -> void:
	for h in ["hero_vesper_loom", "hero_sable", "hero_hex", "hero_liora_vale", "hero_brannoc", "hero_ryker_vance",
			"hero_juniper_quill"]:
		var g := _guide(StringName(h))
		assert_object(g).override_failure_message("%s has no guide" % h).is_not_null()
		assert_bool(g.is_guide()).is_true()
		var mana: bool = h in ["hero_vesper_loom", "hero_sable", "hero_hex", "hero_liora_vale"]
		var st := _state(_mana() if mana else _mech(), 500)
		assert_str(String(_best_node(BuildAdvisor.evaluate(g, st, _ar)))).is_equal("open")
		assert_str(String(_best_item(BuildAdvisor.evaluate(g, st, _ar)))).is_equal("med_pack")
		st.holdings[_cat.index_of(&"med_pack")] = 1
		# One Med-Pack opens the build; the restock step tops the bag up to three.
		assert_str(String(_best_node(BuildAdvisor.evaluate(g, st, _ar)))).override_failure_message(h).is_equal("restock")
		st.holdings[_cat.index_of(&"med_pack")] = 3
		assert_str(String(_best_node(BuildAdvisor.evaluate(g, st, _ar)))).override_failure_message(h).is_equal("start")


func test_alternative_satisfies_a_node() -> void:
	var g := _custom([_node(&"a", &"ammo_piercing", 100), _node(&"b", &"med_pack", 50, ["a"])])
	g.nodes[0].alternatives = PackedStringArray(["ammo_sunder"])
	var r := BuildAdvisor.evaluate(g, _state(_mana(), 5000, {&"ammo_sunder": 1}), _ar)
	assert_bool(r.done.has("a")).is_true()
	assert_str(String(_best_item(r))).is_equal("med_pack")


func test_unavailable_items_do_not_block_and_fallbacks_step_in() -> void:
	_cat = _cat.duplicate(true) as ArmoryCatalogDef
	_cat.find(&"ammo_cryo").disabled = true  # switched off: unavailable to everyone
	var pref := _node(&"pref", &"ammo_cryo", 100)
	var fb := _node(&"fb", &"ember_heart", 90, ["pref"])
	fb.fallback = true
	var after := _node(&"next", &"flux_coil", 80, ["pref"])
	var r := BuildAdvisor.evaluate(_custom([pref, fb, after]), _state(_mana(), 5000), _ar)
	assert_array(_node_ids(r)).contains_exactly(["fb", "next"])
	# Once the preferred item is sold again the fallback stays hidden.
	_cat.find(&"ammo_cryo").disabled = false
	r = BuildAdvisor.evaluate(_custom([pref, fb, after]), _state(_mech(), 5000), _ar)
	assert_str(String(_best_node(r))).is_equal("pref")
	assert_array(_node_ids(r)).not_contains(["fb"])


func test_situational_node_waits_for_its_condition_and_explains_itself() -> void:
	var g := _guide(&"hero_vesper_loom")
	var st := _state(_mana(), 5000, {&"med_pack": 1, &"ember_heart": 1})
	var r := BuildAdvisor.evaluate(g, st, _ar)
	assert_array(_node_ids(r)).not_contains(["heal_pack"])
	st.signals = SnapshotData.ProgressState.SIG_SKILL_DAMAGE
	r = BuildAdvisor.evaluate(g, st, _ar)
	var heal: BuildAdvisor.Advice = null
	for a in r.advice:
		if a.node.id == &"heal_pack":
			heal = a
	assert_object(heal).is_not_null()
	assert_str(heal.reason_key).is_equal("HUD_ADVICE_R_TAKING_SKILL_DAMAGE")
	assert_bool(heal.situational).is_true()


func test_enemy_threat_tags_open_counter_branches_at_the_trait_threshold() -> void:
	var g := _guide(&"hero_ryker_vance")
	var st := _state(_mech(), 5000, {&"med_pack": 1, &"ember_heart": 1})
	st.enemy_tags = {"frontline": 1}
	var ids := func(res: BuildAdvisor.Result) -> Array:
		var out: Array = []
		for a in res.advice:
			out.append(String(a.node.id))
		return out
	# "frontline" is a rare trait (one hero carries it): one enemy is enough even in 5v5.
	assert_array(ids.call(BuildAdvisor.evaluate(g, st, _ar))).contains(["vs_armor"])
	# "cc" is common (three heroes): 5v5 still needs two, 3v3 one.
	st.enemy_tags = {"cc": 1}
	assert_array(ids.call(BuildAdvisor.evaluate(g, st, _ar))).not_contains(["vs_skills"])
	st.team_size = 3
	assert_array(ids.call(BuildAdvisor.evaluate(g, st, _ar))).contains(["vs_skills"])
	st.team_size = 5
	st.enemy_tags = {"cc": 2}
	assert_array(ids.call(BuildAdvisor.evaluate(g, st, _ar))).contains(["vs_skills"])
	st.enemy_tags = {"frontline": 2}
	var r := BuildAdvisor.evaluate(g, st, _ar)
	assert_array(ids.call(r)).contains(["vs_armor"])
	for a in r.advice:
		if a.node.id == &"vs_armor":
			assert_str(a.reason_key).is_equal("HUD_ADVICE_R_ENEMY_FRONTLINE")
			assert_array(Array(a.rules)).contains(["enemy_frontline"])


func test_rule_bonus_can_lift_a_situational_node_to_the_top() -> void:
	var core := _node(&"core", &"ember_heart", 100)
	var heal := _node(&"heal", &"med_pack", 60)
	heal.conditions = PackedStringArray(["died_often"])
	var st := _state(_mana(), 5000)
	assert_str(String(_best_node(BuildAdvisor.evaluate(_custom([core, heal]), st, _ar)))).is_equal("core")
	st.signals = SnapshotData.ProgressState.SIG_DIED_OFTEN
	var r := BuildAdvisor.evaluate(_custom([core, heal]), st, _ar)
	assert_str(String(_best_node(r))).is_equal("heal")
	assert_str(r.best().reason_key).is_equal("HUD_ADVICE_R_DIED_OFTEN")


func test_skippable_node_releases_later_nodes_when_its_condition_is_gone() -> void:
	var opt := _node(&"opt", &"ammo_piercing", 100)
	opt.conditions = PackedStringArray(["enemy_frontline"])
	opt.skippable = true
	var later := _node(&"later", &"flux_coil", 50, ["opt"])
	var r := BuildAdvisor.evaluate(_custom([opt, later]), _state(_mana(), 5000), _ar)
	assert_str(String(_best_node(r))).is_equal("later")
	opt.skippable = false
	r = BuildAdvisor.evaluate(_custom([opt, later]), _state(_mana(), 5000), _ar)
	assert_object(r.best()).is_null()
	assert_str("\n".join(r.trace)).contains("waits for opt")


func test_time_window_and_catalog_requirements_gate_offers() -> void:
	var late := _node(&"late", &"ember_heart", 100)
	late.min_s = 600
	var exp2 := _node(&"exp2", &"squad_expansion_2", 90)
	var st := _state(_mana(), 5000)
	var r := BuildAdvisor.evaluate(_custom([late, exp2]), st, _ar)
	assert_object(r.best()).is_null()
	assert_str("\n".join(r.trace)).contains("needs squad_expansion_1 first")
	st.time_s = 700.0
	st.holdings[_cat.index_of(&"squad_expansion_1")] = 1
	r = BuildAdvisor.evaluate(_custom([late, exp2]), st, _ar)
	assert_int(r.advice.size()).is_equal(2)


func test_affordability_and_soon_follow_lumen_and_expected_income() -> void:
	var g := _custom([_node(&"q", &"squad_expansion_1", 100)])
	var st := _state(_mech(), 600)
	var r := BuildAdvisor.evaluate(g, st, _ar)
	assert_int(r.best().cost).is_equal(800)
	assert_bool(r.best().affordable).is_false()
	assert_bool(r.best().soon).is_true()  # 200 short: within 60 s of expected income (270/min)
	st.lumen = 100
	assert_bool(BuildAdvisor.evaluate(g, st, _ar).best().soon).is_false()
	st.lumen = 800
	assert_bool(BuildAdvisor.evaluate(g, st, _ar).best().affordable).is_true()


func test_completed_guide_reports_full_progress_and_ignored_advice_never_blocks() -> void:
	var g := _guide(&"hero_brannoc")
	var own := {}
	for n in g.nodes:
		if n.core and not n.optional and not n.fallback:
			own[StringName(n.item_id)] = 1
	var r := BuildAdvisor.evaluate(g, _state(_mech(), 0, own), _ar)
	assert_int(r.core_done).is_equal(r.core_total)
	assert_int(r.core_total).is_greater(0)
	# A player who bought something off-guide still gets the rest of the guide.
	r = BuildAdvisor.evaluate(g, _state(_mech(), 5000, {&"ammo_cryo": 1}), _ar)
	assert_str(String(_best_node(r))).is_equal("open")


func test_trace_explains_offers_skips_and_the_pick() -> void:
	var r := BuildAdvisor.evaluate(_guide(&"hero_hex"), _state(_mana(), 500), _ar)
	var t := "\n".join(r.trace)
	assert_str(t).contains("offer open (med_pack)")
	assert_str(t).contains("skip start (cadence_bead): waits for open")
	assert_str(t).contains("pick open")


func test_team_role_rules() -> void:
	var heal := _node(&"heal", &"med_pack", 50)
	heal.conditions = PackedStringArray(["team_lacks_sustain"])
	var st := _state(_mana(), 500)
	st.ally_roles = {"healer": 1}
	assert_object(BuildAdvisor.evaluate(_custom([heal]), st, _ar).best()).is_null()
	st.ally_roles = {"tank": 1}
	assert_str(BuildAdvisor.evaluate(_custom([heal]), st, _ar).best().reason_key).is_equal(
		"HUD_ADVICE_R_TEAM_LACKS_SUSTAIN")


func test_validator_accepts_the_rule_ids_used_by_the_shipped_guides() -> void:
	var heroes: Array = []
	for f in DirAccess.get_files_at("res://assets/data/heroes"):
		if f.ends_with(".tres"):
			heroes.append(load("res://assets/data/heroes".path_join(f)))
	var res := ArmoryValidator.check(_cat, _builds, heroes, BuildAdvisor.rule_ids())
	assert_array(res["errors"]).override_failure_message("\n".join(res["errors"])).is_empty()
