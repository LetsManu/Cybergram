extends GdUnitTestSuite
## Armory transactions on a real ServerWorld (v22 catalog): same-visit undo of
## squad upgrades and Med-Packs (full refund, effects removed, dependants block
## it, gone after the visit), the shop result channel (shop_seq / shop_result
## through handle_action -> fill_own -> codec), forged and repeated requests,
## failed requests change nothing, price_of honours ownership, the wire format
## round-trips and the catalog's squad / consumable wire indices stay pinned
## (the full v22 order: item_shop_wire_test.gd).

const HZ: int = 30
## Wire contract: catalog order is the network item id (ACTION_BUY,
## ProgressState). Existing entries may never move; new items are appended.
const PINNED_ORDER: Array[StringName] = [&"med_pack", &"squad_expansion_1", &"squad_expansion_2",
	&"reinforced_cores_1", &"reinforced_cores_2", &"amplifier_emitters", &"harmonic_tether", &"quick_mint",
	&"bulwark_protocol", &"ember_part", &"tempo_part", &"lens_part"]

var _server: ServerWorld
var _link: LoopbackLink
var _pr: ProgressionSystem
var _cat: ArmoryCatalogDef


func before_test() -> void:
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
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_pr = _server.enable_progression(load("res://assets/data/economy/economy_rules_slice.tres"), _cat, null)
	_pr.debug_shop_anywhere = true
	_pr.armory_log = false


func _hero(def: HeroDef = null) -> HeroBody:
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()), Vector3.ZERO,
		def if def != null else CombatFixtures.vesper(), 0)
	return _server.hero(id)


func _cmd(action: int, arg: int) -> InputCommand:
	var c := InputCommand.new()
	c.action = action
	c.action_arg = arg
	return c


func _own(h: HeroBody) -> SnapshotData.ProgressState:
	var s := SnapshotData.new()
	_pr.fill_own(s, h)
	return SnapshotCodec.progress_from(SnapshotCodec.progress_blob(s.progress))


func _idx(id: StringName) -> int:
	return _cat.index_of(id)


## The v22 request undoing a squad upgrade / Med-Pack bought this visit.
func _undo_row(h: HeroBody, id: StringName) -> int:
	return _pr.handle_action(h, _cmd(InputCommand.ACTION_SELL,
		InputCommand.UNDO_ITEM_FLAG | InputCommand.UNDO_ROW_FLAG | _idx(id)))


func _cost(id: StringName) -> int:
	return RecipeMath.total(_cat, _idx(id))


func test_catalog_wire_indices_are_pinned() -> void:
	for i in PINNED_ORDER.size():
		assert_str(String(_cat.at(i).id)).override_failure_message(
			"catalog index %d moved: append new items, never reorder" % i).is_equal(String(PINNED_ORDER[i]))


func test_squad_upgrade_undo_refunds_and_removes_the_effect_this_visit_only() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 2000
	var cap0: float = h.combat.stats.get_value(StatCatalog.hero_index(&"squad_capacity_bonus"))
	assert_int(_pr.buy(h, &"squad_expansion_1")).is_equal(HeroProgress.Result.OK)
	assert_float(h.combat.stats.get_value(StatCatalog.hero_index(&"squad_capacity_bonus"))).is_equal(cap0 + 1.0)
	assert_int(_own(h).visit_owned_bits & (1 << _idx(&"squad_expansion_1"))).is_not_equal(0)
	assert_int(_undo_row(h, &"squad_expansion_1")).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(2000)
	assert_bool(p.owned.has(&"squad_expansion_1")).is_false()
	assert_float(h.combat.stats.get_value(StatCatalog.hero_index(&"squad_capacity_bonus"))).is_equal(cap0)
	# Bought again, then the visit ends: no more undo.
	assert_int(_pr.buy(h, &"squad_expansion_1")).is_equal(HeroProgress.Result.OK)
	p.end_visit()
	assert_int(_undo_row(h, &"squad_expansion_1")).is_equal(HeroProgress.Result.NOT_OWNED)
	assert_int(_own(h).visit_owned_bits).is_equal(0)


func test_squad_undo_is_blocked_while_an_upgrade_built_on_it_is_held() -> void:
	var h := _hero()
	_pr.progress_of(h).lumen = 5000
	assert_int(_pr.buy(h, &"squad_expansion_1")).is_equal(HeroProgress.Result.OK)
	assert_int(_pr.buy(h, &"squad_expansion_2")).is_equal(HeroProgress.Result.OK)
	assert_int(_undo_row(h, &"squad_expansion_1")).is_equal(HeroProgress.Result.REQUIRES)
	assert_int(_undo_row(h, &"squad_expansion_2")).is_equal(HeroProgress.Result.OK)
	assert_int(_undo_row(h, &"squad_expansion_1")).is_equal(HeroProgress.Result.OK)
	assert_int(_pr.progress_of(h).lumen).is_equal(5000)


func test_med_pack_undo_this_visit_and_not_after_use() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 1000
	assert_int(_pr.buy(h, &"med_pack")).is_equal(HeroProgress.Result.OK)
	assert_int(_pr.buy(h, &"med_pack")).is_equal(HeroProgress.Result.OK)
	assert_int(_own(h).visit_medpacks).is_equal(2)
	assert_int(_undo_row(h, &"med_pack")).is_equal(HeroProgress.Result.OK)
	assert_int(p.medpacks).is_equal(1)
	assert_int(p.lumen).is_equal(900)
	h.combat.health.hp = 100.0
	assert_int(_server.use_medpack(h)).is_equal(HeroProgress.Result.OK)
	assert_int(_server.use_medpack(h)).is_equal(HeroProgress.Result.NOT_OWNED)
	assert_int(_undo_row(h, &"med_pack")).is_equal(HeroProgress.Result.NOT_OWNED)
	assert_int(p.lumen).is_equal(900)


func test_second_med_pack_while_healing_reports_healing() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.medpacks = 2
	h.combat.health.hp = 100.0
	assert_int(_server.use_medpack(h)).is_equal(HeroProgress.Result.OK)
	assert_int(_server.use_medpack(h)).is_equal(HeroProgress.Result.HEALING)


func test_requests_report_their_result_through_the_snapshot() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	var cost := _cost(&"ember_heart")
	p.lumen = 100
	var seq0 := _own(h).shop_seq
	_pr.handle_action(h, _cmd(InputCommand.ACTION_BUY, _idx(&"ember_heart")))
	var o := _own(h)
	assert_int(o.shop_seq).is_equal((seq0 + 1) & 0xFF)
	assert_int(o.shop_result).is_equal(HeroProgress.Result.NO_FUNDS)
	assert_int(o.lumen).is_equal(100)
	p.lumen = cost + 1000
	_pr.handle_action(h, _cmd(InputCommand.ACTION_BUY, _idx(&"ember_heart")))
	o = _own(h)
	assert_int(o.shop_seq).is_equal((seq0 + 2) & 0xFF)
	assert_int(o.shop_result).is_equal(HeroProgress.Result.OK)
	_pr.handle_action(h, _cmd(InputCommand.ACTION_SELL, InputCommand.UNDO_LAST))
	o = _own(h)
	assert_int(o.shop_result).is_equal(HeroProgress.Result.OK)
	assert_int(o.lumen).is_equal(cost + 1000)  # undo: full refund
	# Non-shop actions do not move the shop sequence.
	_pr.handle_action(h, _cmd(InputCommand.ACTION_SPAWN_CHOICE, 0))
	assert_int(_own(h).shop_seq).is_equal((seq0 + 3) & 0xFF)


func test_forged_requests_are_refused_and_change_nothing() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 5000
	var cases := [
		[InputCommand.ACTION_BUY, 0xFF, HeroProgress.Result.UNKNOWN_ITEM],  # index past the catalog
		[InputCommand.ACTION_SELL, 0, HeroProgress.Result.INVALID],  # no such place
		[InputCommand.ACTION_SELL, 77, HeroProgress.Result.INVALID],
		[InputCommand.ACTION_SELL, 0x1FF, HeroProgress.Result.INVALID],
		[InputCommand.ACTION_SELL, InputCommand.UNDO_ITEM_FLAG | InputCommand.UNDO_ROW_FLAG | _idx(&"med_pack"),
			HeroProgress.Result.NOT_OWNED],
	]
	for c in cases:
		var r := _pr.handle_action(h, _cmd(c[0], c[1]))
		assert_int(r).override_failure_message("arg %d -> %d" % [c[1], r]).is_equal(c[2])
		assert_int(p.lumen).is_equal(5000)
		assert_int(p.inv.pool().size()).is_equal(0)
		assert_int(p.owned.size()).is_equal(0)
		assert_int(p.medpacks).is_equal(0)


func test_repeated_buy_of_a_squad_upgrade_charges_once() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 2000
	var arg := _idx(&"reinforced_cores_1")
	assert_int(_pr.handle_action(h, _cmd(InputCommand.ACTION_BUY, arg))).is_equal(HeroProgress.Result.OK)
	assert_int(_pr.handle_action(h, _cmd(InputCommand.ACTION_BUY, arg))).is_equal(HeroProgress.Result.LIMIT)
	assert_int(p.lumen).is_equal(2000 - 350)


func test_repeated_buy_of_a_signature_is_refused_without_stacking_modifiers() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 9000
	var i := StatCatalog.hero_index(&"mod_damage")
	var base: float = h.combat.stats.get_value(i)
	assert_int(_pr.buy(h, &"ember_heart")).is_equal(HeroProgress.Result.OK)
	var once: float = h.combat.stats.get_value(i)
	assert_float(once).is_greater(base)
	assert_int(_pr.buy(h, &"ember_heart")).is_equal(HeroProgress.Result.ALREADY_OWNED)
	assert_float(h.combat.stats.get_value(i)).is_equal_approx(once, 1e-6)
	assert_int(p.lumen).is_equal(9000 - _cost(&"ember_heart"))


func test_price_of_respects_ownership_requirements_and_carry() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 5000
	assert_int(_pr.price_of(h, &"squad_expansion_2")).is_equal(-1)  # needs I
	assert_int(_pr.price_of(h, &"squad_expansion_1")).is_equal(800)
	_pr.buy(h, &"squad_expansion_1")
	assert_int(_pr.price_of(h, &"squad_expansion_1")).is_equal(-1)
	assert_int(_pr.price_of(h, &"squad_expansion_2")).is_equal(1500)
	p.medpacks = 3
	assert_int(_pr.price_of(h, &"med_pack")).is_equal(-1)


func test_spent_lumen_is_tracked_net_of_refunds() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 9000
	_pr.buy(h, &"ember_heart")
	_pr.buy(h, &"med_pack")
	assert_int(p.spent_lumen).is_equal(_cost(&"ember_heart") + 100)
	_pr.undo(h, -1)  # the last change of the visit: the Med-Pack
	assert_int(p.spent_lumen).is_equal(_cost(&"ember_heart"))


func test_progress_wire_round_trip_keeps_the_v21_fields() -> void:
	var o := SnapshotData.ProgressState.new()
	o.lumen = 1234
	o.shop_seq = 255
	o.shop_result = HeroProgress.Result.REQUIRES
	o.visit_owned_bits = 0x8000_0021
	o.visit_medpacks = 2
	o.signals = SnapshotData.ProgressState.SIG_SKILL_DAMAGE | SnapshotData.ProgressState.SIG_TEAM_BEHIND
	o.mount_item = PackedInt32Array([6, -1, 10, 12])
	o.mount_tier = PackedInt32Array([2, 0, 1, 3])
	o.mount_paid = PackedInt32Array([900, 0, 750, 1800])
	o.mount_paid_visit = PackedInt32Array([500, 0, 0, 1800])
	var r := SnapshotCodec.progress_from(SnapshotCodec.progress_blob(o))
	assert_int(r.lumen).is_equal(1234)
	assert_int(r.shop_seq).is_equal(255)
	assert_int(r.shop_result).is_equal(HeroProgress.Result.REQUIRES)
	assert_int(r.visit_owned_bits).is_equal(0x8000_0021)
	assert_int(r.visit_medpacks).is_equal(2)
	assert_int(r.signals).is_equal(o.signals)
	assert_array(Array(r.mount_item)).is_equal(Array(o.mount_item))
	assert_array(Array(r.mount_tier)).is_equal(Array(o.mount_tier))
	assert_array(Array(r.mount_paid_visit)).is_equal(Array(o.mount_paid_visit))


func test_shop_model_offers_undo_for_squad_and_med_pack_bought_this_visit() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 3000
	_pr.buy(h, &"reinforced_cores_1")
	_pr.buy(h, &"med_pack")
	var m := ItemShopModel.new(_cat, load("res://assets/data/economy/economy_rules_slice.tres"), null,
		&"hero_vesper_loom", h.combat.def.weapon)
	m.update(_own(h))
	var cores := _idx(&"reinforced_cores_1")
	assert_int(m.row_undo_arg(cores)).is_equal(InputCommand.UNDO_ITEM_FLAG | InputCommand.UNDO_ROW_FLAG | cores)
	assert_int(m.undo_value(cores)).is_equal(350)
	assert_int(m.undo_arg(_idx(&"med_pack"))).is_equal(InputCommand.UNDO_ITEM_FLAG | _idx(&"med_pack"))
	assert_int(m.undo_arg(_idx(&"amplifier_emitters"))).is_equal(-1)
	_pr.handle_action(h, _cmd(InputCommand.ACTION_SELL, m.undo_arg(cores)))
	m.update(_own(h))
	assert_int(m.undo_arg(cores)).is_equal(-1)
	assert_str(ItemShopModel.result_key(HeroProgress.Result.NO_FUNDS)).is_equal("HUD_SHOP_R_NO_FUNDS")
