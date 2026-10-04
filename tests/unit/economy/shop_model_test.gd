extends GdUnitTestSuite
## Armory shop logic (ShopModel): tab / search filtering, affordability,
## wrong-family and locked states, the per-hero recommended next step, and
## buy / sell / undo driven through the real server path (ProgressionSystem
## handle_action -> fill_own -> the replicated ProgressState the HUD reads).

const VESPER := &"hero_vesper_loom"
const BRANNOC := &"hero_brannoc"

var _server: ServerWorld
var _link: LoopbackLink
var _pr: ProgressionSystem
var _cat: ArmoryCatalogDef
var _rules: EconomyRulesDef
var _builds: RecommendedBuildsDef


func _setup() -> void:
	var net := NetFixtures.net_config()
	_link = LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(auto_free(vp))
	_server = ServerWorld.new()
	vp.add_child(_server)
	_server.setup(net, MovementDef.new(), CombatFixtures.range_scene(false), _link.create_endpoint(1),
		CombatFixtures.vesper(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	_rules = load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_builds = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	_pr = _server.enable_progression(_rules, _cat, null)
	_pr.debug_shop_anywhere = true


func _hero(def: HeroDef) -> HeroBody:
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()), Vector3.ZERO, def, 0)
	return _server.hero(id)


## Model fed with the same ProgressState the client would receive.
func _model(h: HeroBody, hero_id: StringName) -> ShopModel:
	var s := SnapshotData.new()
	_pr.fill_own(s, h)
	var m := ShopModel.new(_cat, _rules, _builds, hero_id, h.combat.weapon.def)
	m.update(s.progress)
	return m


func _act(h: HeroBody, action: int, arg: int) -> int:
	var cmd := InputCommand.new()
	cmd.action = action
	cmd.action_arg = arg
	return _pr.handle_action(h, cmd)


func _names(m: ShopModel, rows: Array[int]) -> Array[String]:
	var out: Array[String] = []
	for i in rows:
		out.append(String(_cat.at(i).id))
	return out


func test_tabs_and_search_filter_the_catalog() -> void:
	_setup()
	var m := _model(_hero(CombatFixtures.vesper()), VESPER)
	assert_int(m.rows(ShopModel.Tab.ALL).size()).is_equal(_cat.items.size())
	assert_array(_names(m, m.rows(ShopModel.Tab.CORE))).contains_exactly(["ember_heart", "overclock"])
	assert_array(_names(m, m.rows(ShopModel.Tab.CHAMBER))).contains_exactly(["ammo_piercing", "ammo_sunder"])
	assert_array(_names(m, m.rows(ShopModel.Tab.CONSUMABLES))).contains_exactly(["med_pack"])
	assert_int(m.rows(ShopModel.Tab.SQUAD).size()).is_equal(5)
	assert_array(_names(m, m.rows(ShopModel.Tab.ALL, "  EMBER "))).contains_exactly(["ember_heart"])
	# Search also reads the effect text, inside a tab.
	assert_array(_names(m, m.rows(ShopModel.Tab.FRAME, "reload"))).contains_exactly(["quickload"])
	assert_int(m.rows(ShopModel.Tab.CORE, "reload").size()).is_equal(0)


func test_affordability_family_and_requirements() -> void:
	_setup()
	var h := _hero(CombatFixtures.vesper())
	var p := _pr.progress_of(h)
	p.lumen = 500
	var m := _model(h, VESPER)
	var ember := _cat.index_of(&"ember_heart")
	assert_int(m.state(ember)).is_equal(ShopModel.State.AVAILABLE)  # 400 <= 500
	assert_int(m.state(_cat.index_of(&"overclock"))).is_equal(ShopModel.State.WRONG_FAMILY)
	assert_int(m.state(_cat.index_of(&"squad_expansion_1"))).is_equal(ShopModel.State.CANT_AFFORD)
	assert_int(m.state(_cat.index_of(&"squad_expansion_2"))).is_equal(ShopModel.State.LOCKED)
	assert_int(m.state(ember, 2)).is_equal(ShopModel.State.CANT_AFFORD)  # tier II lists at 900
	p.lumen = 100
	m = _model(h, VESPER)
	assert_int(m.state(ember)).is_equal(ShopModel.State.CANT_AFFORD)
	assert_int(m.state(_cat.index_of(&"med_pack"))).is_equal(ShopModel.State.AVAILABLE)
	var brannoc := _model(_hero(CombatFixtures.brannoc()), BRANNOC)
	assert_int(brannoc.state(ember)).is_equal(ShopModel.State.WRONG_FAMILY)


func test_buy_through_the_server_updates_state_and_upgrade_cost() -> void:
	_setup()
	var h := _hero(CombatFixtures.vesper())
	var p := _pr.progress_of(h)
	p.lumen = 2000
	var ember := _cat.index_of(&"ember_heart")
	var m := _model(h, VESPER)
	assert_int(_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(ember))).is_equal(HeroProgress.Result.OK)
	m = _model(h, VESPER)
	assert_int(m.held_tier(ember)).is_equal(1)
	assert_int(m.progress.lumen).is_equal(1600)
	assert_int(m.purchase_cost(ember)).is_equal(500)  # list(II) - list(I)
	assert_int(_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(ember))).is_equal(HeroProgress.Result.OK)
	assert_int(_model(h, VESPER).progress.lumen).is_equal(1100)
	assert_int(_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(ember, 3))).is_equal(HeroProgress.Result.OK)
	m = _model(h, VESPER)
	assert_int(m.state(ember)).is_equal(ShopModel.State.MAXED)
	assert_int(m.purchase_cost(ember)).is_equal(-1)
	assert_int(_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(ember))).is_equal(HeroProgress.Result.MAXED)


func test_undo_refunds_in_full_this_visit_and_sell_pays_sixty_percent_later() -> void:
	_setup()
	var h := _hero(CombatFixtures.vesper())
	var p := _pr.progress_of(h)
	p.lumen = 2000
	var ember := _cat.index_of(&"ember_heart")
	var socket := int(ArmoryItemDef.Socket.CORE)
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(ember, 2))  # 900
	var m := _model(h, VESPER)
	assert_int(m.sell_socket(ember)).is_equal(socket)
	assert_bool(m.is_undo(socket)).is_true()
	assert_int(m.undo_socket(socket)).is_equal(socket)
	assert_int(m.sell_value(socket)).is_equal(900)
	assert_int(_act(h, InputCommand.ACTION_SELL, socket)).is_equal(HeroProgress.Result.OK)
	m = _model(h, VESPER)
	assert_int(m.progress.lumen).is_equal(2000)
	assert_int(m.held_tier(ember)).is_equal(0)
	assert_int(m.undo_socket(socket)).is_equal(-1)
	# Buy again, leave the pad (visit over): selling pays 60% rounded down to 5.
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(ember, 2))
	p.end_visit()
	m = _model(h, VESPER)
	assert_bool(m.is_undo(socket)).is_false()
	assert_int(m.undo_socket(socket)).is_equal(-1)
	assert_int(m.sell_value(socket)).is_equal(540)
	_pr.debug_shop_anywhere = false
	assert_int(_act(h, InputCommand.ACTION_SELL, socket)).is_equal(HeroProgress.Result.NOT_AT_ARMORY)  # off the pad
	assert_int(_model(h, VESPER).held_tier(ember)).is_equal(2)


func test_swap_credit_counts_toward_affordability_and_squad_cannot_be_sold() -> void:
	_setup()
	var h := _hero(CombatFixtures.vesper())
	var p := _pr.progress_of(h)
	p.lumen = 400
	var ember := _cat.index_of(&"ember_heart")
	var flux := _cat.index_of(&"flux_coil")
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(ember))
	var m := _model(h, VESPER)
	assert_int(m.progress.lumen).is_equal(0)
	assert_int(m.state(flux)).is_equal(ShopModel.State.CANT_AFFORD)  # 350, different socket
	var piercing := _cat.index_of(&"ammo_piercing")
	p.lumen = 0
	assert_int(_model(h, VESPER).swap_credit(piercing)).is_equal(0)
	# Squad upgrades and Med-Packs have no sell rule.
	p.lumen = 5000
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(_cat.index_of(&"squad_expansion_1")))
	m = _model(h, VESPER)
	assert_int(m.state(_cat.index_of(&"squad_expansion_1"))).is_equal(ShopModel.State.OWNED)
	assert_int(m.sell_socket(_cat.index_of(&"squad_expansion_1"))).is_equal(-1)
	assert_int(m.state(_cat.index_of(&"squad_expansion_2"))).is_equal(ShopModel.State.AVAILABLE)


func test_med_pack_carry_limit_state() -> void:
	_setup()
	var h := _hero(CombatFixtures.vesper())
	_pr.progress_of(h).lumen = 5000
	var med := _cat.index_of(&"med_pack")
	for i in 3:
		assert_int(_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(med))).is_equal(HeroProgress.Result.OK)
	assert_int(_model(h, VESPER).state(med)).is_equal(ShopModel.State.CARRY_FULL)


func test_recommended_next_follows_the_build_and_skips_other_families() -> void:
	_setup()
	var h := _hero(CombatFixtures.vesper())
	var p := _pr.progress_of(h)
	p.lumen = 9000
	var m := _model(h, VESPER)
	assert_int(m.recommended_next()).is_equal(_cat.index_of(&"med_pack"))
	assert_bool(m.is_recommended(_cat.index_of(&"ember_heart"))).is_true()
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(_cat.index_of(&"med_pack")))
	m = _model(h, VESPER)
	assert_int(m.recommended_next()).is_equal(_cat.index_of(&"ember_heart"))
	assert_int(m.recommended_target()).is_equal(1)
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(_cat.index_of(&"ember_heart")))
	assert_int(_model(h, VESPER).recommended_next()).is_equal(_cat.index_of(&"reinforced_cores_1"))
	# A held Ember Heart I still leaves the tier II step open after the earlier ones are done.
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(_cat.index_of(&"reinforced_cores_1")))
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(_cat.index_of(&"flux_coil")))
	_act(h, InputCommand.ACTION_BUY, ShopModel.buy_arg(_cat.index_of(&"amplifier_emitters")))
	m = _model(h, VESPER)
	assert_int(m.recommended_next()).is_equal(_cat.index_of(&"ember_heart"))
	assert_int(m.recommended_target()).is_equal(2)
	# Brannoc's build never points at Crystal lines, and a hero without a build gets none.
	var b := _model(_hero(CombatFixtures.brannoc()), BRANNOC)
	assert_bool(_cat.at(b.recommended_next()).fits(b.weapon)).is_true()
	assert_int(_model(h, &"nobody").recommended_next()).is_equal(-1)


func test_recommended_builds_reference_real_catalog_items() -> void:
	_setup()
	for b in _builds.builds:
		assert_int(b.item_ids.size()).is_equal(b.targets.size())
		for s in b.steps():
			var it := _cat.find(b.item_at(s))
			assert_object(it).is_not_null()
			assert_int(b.target_at(s)).is_less_equal(maxi(it.tiers(), it.carry_limit))
