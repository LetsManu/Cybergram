extends GdUnitTestSuite
## Armory v2 on a real ServerWorld with the v22 catalog (items-and-armory.md
## §3.6, §3.11): purchases, sales and undo arrive as InputCommand actions
## (ACTION_BUY index, ACTION_SELL place / UNDO_* args), the result channel
## reports them, and the inventory, undo bits and visit transactions reach
## the client through fill_own and the protocol 22 codec. The v22 wire order
## is pinned.

const HZ: int = 30
## v22 wire contract (§3.11): catalog order is the network item id, append-only.
const PINNED_V22: Array[StringName] = [&"med_pack", &"squad_expansion_1", &"squad_expansion_2",
	&"reinforced_cores_1", &"reinforced_cores_2", &"amplifier_emitters", &"harmonic_tether", &"quick_mint",
	&"bulwark_protocol", &"ember_part", &"tempo_part", &"lens_part", &"steady_part", &"feed_part", &"vital_cell",
	&"plate_scale", &"null_thread", &"cadence_bead", &"stride_clip", &"ember_facet", &"pulse_facet",
	&"longsight_ring", &"bore_ring", &"wellframe", &"vital_core", &"plate_harness", &"null_cowl",
	&"cadence_circlet", &"stride_rig", &"ember_heart", &"tempest_heart", &"prism_eye", &"longsight_lens",
	&"breaker_bore", &"reservoir_frame", &"flux_coil", &"anchor_frame", &"bastion_plate", &"null_veil",
	&"vigil_core", &"barrier_lattice", &"cadence_crown", &"breaker_sigil", &"ammo_piercing", &"ammo_incendiary",
	&"ammo_shock", &"ammo_siphon", &"ammo_cryo", &"ammo_sunder", &"mod_saturated", &"mod_lingering",
	&"mod_volatile", &"mod_tracer", &"mod_overcharged"]

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


func _hero() -> HeroBody:
	var id := _server.add_scripted_hero(ScriptedInputSource.new(CombatFixtures.idle_input()), Vector3.ZERO,
		CombatFixtures.vesper(), 0)
	return _server.hero(id)


func _act(h: HeroBody, action: int, arg: int) -> int:
	var c := InputCommand.new()
	c.action = action
	c.action_arg = arg
	return _pr.handle_action(h, c)


func _own(h: HeroBody) -> SnapshotData.ProgressState:
	var s := SnapshotData.new()
	_pr.fill_own(s, h)
	return SnapshotCodec.progress_from(SnapshotCodec.progress_blob(s.progress))


func _i(id: StringName) -> int:
	return _cat.index_of(id)


func test_v22_wire_order_is_pinned_and_fits_the_wire() -> void:
	assert_int(_cat.items.size()).is_equal(PINNED_V22.size())
	for i in PINNED_V22.size():
		assert_str(String(_cat.at(i).id)).override_failure_message(
			"v22 catalog index %d moved: append new items, never reorder" % i).is_equal(String(PINNED_V22[i]))
	assert_bool(_pr.is_v2()).is_true()
	assert_int(_cat.items.size()).is_less(128)  # s8 on the wire


func test_buy_sell_and_undo_through_actions_reach_the_client() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 5000
	assert_int(_act(h, InputCommand.ACTION_BUY, _i(&"ember_part"))).is_equal(HeroProgress.Result.OK)
	assert_int(_act(h, InputCommand.ACTION_BUY, _i(&"lens_part"))).is_equal(HeroProgress.Result.OK)
	assert_int(_act(h, InputCommand.ACTION_BUY, _i(&"ember_facet"))).is_equal(HeroProgress.Result.OK)
	assert_int(_act(h, InputCommand.ACTION_BUY, _i(&"vital_cell"))).is_equal(HeroProgress.Result.OK)
	var o := _own(h)
	assert_int(o.inv_items[0]).is_equal(_i(&"ember_facet"))  # Core
	assert_int(o.inv_items[5]).is_equal(_i(&"vital_cell"))  # open slot 0
	assert_int(o.inv_items[6]).is_equal(-1)
	assert_int(o.inv_txns).is_equal(4)
	assert_int(o.inv_undo_bits & 1).is_equal(1)  # the facet can be undone
	assert_int(o.shop_result).is_equal(HeroProgress.Result.OK)
	assert_int(o.lumen).is_equal(5000 - 1000 - 300)
	# Undo the facet by its place: the parts come back to the slots.
	assert_int(_act(h, InputCommand.ACTION_SELL, InputCommand.UNDO_ITEM_FLAG | 1)).is_equal(HeroProgress.Result.OK)
	o = _own(h)
	assert_int(o.inv_items[0]).is_equal(-1)
	assert_int(o.lumen).is_equal(5000 - 1000)
	# Undo last: the Vital Cell.
	assert_int(_act(h, InputCommand.ACTION_SELL, InputCommand.UNDO_LAST)).is_equal(HeroProgress.Result.OK)
	# Sell open slot 0 (the Ember Shard is back there) after the visit: 60%.
	p.end_visit()
	p.at_armory = true
	assert_int(p.inv.index_at(16)).is_equal(_i(&"ember_part"))
	var before := p.lumen
	assert_int(_act(h, InputCommand.ACTION_SELL, 16)).is_equal(HeroProgress.Result.OK)
	assert_int(p.lumen - before).is_equal(240)
	assert_int(_own(h).inv_txns).is_equal(1)


func test_forged_sell_args_are_refused_without_change() -> void:
	var h := _hero()
	var p := _pr.progress_of(h)
	p.lumen = 3000
	_act(h, InputCommand.ACTION_BUY, _i(&"vital_cell"))
	var lumen := p.lumen
	for arg in [0, 7, 15, 22, 99, 255, 0x1FF, 0x300]:
		var r := _act(h, InputCommand.ACTION_SELL, arg)
		assert_int(r).override_failure_message("arg 0x%x" % arg).is_not_equal(HeroProgress.Result.OK)
	assert_int(p.lumen).is_equal(lumen)
	assert_int(p.inv.slots.size()).is_equal(1)
	# The Med-Pack row undo flag.
	_act(h, InputCommand.ACTION_BUY, _i(&"med_pack"))
	assert_int(_act(h, InputCommand.ACTION_SELL,
		InputCommand.UNDO_ITEM_FLAG | InputCommand.UNDO_ROW_FLAG | _i(&"med_pack"))).is_equal(HeroProgress.Result.OK)
	assert_int(p.medpacks).is_equal(0)
	assert_int(p.lumen).is_equal(lumen)
