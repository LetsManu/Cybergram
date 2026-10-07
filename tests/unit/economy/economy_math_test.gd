extends GdUnitTestSuite
## E13/E15 formulas (wardlings-and-economy.md §15–§17; heroes.md §3.5;
## weapons-and-mods.md §4.7): the Resonance table, skill points, share factor,
## catch-up C, deficit D, Shutdown, the Wardling 75/25 split and shop math.

## §16 table: cumulative EXP at the start of L1..L15.
const CUMULATIVE: Array[int] = [0, 190, 430, 720, 1060, 1450, 1970, 2550, 3190, 3890, 4650, 5470, 6350, 7290, 8290]
const TO_NEXT: Array[int] = [190, 240, 290, 340, 390, 520, 580, 640, 700, 760, 820, 880, 940, 1000, 0]

var _r := EconomyRulesDef.new()


func test_exp_table_matches_the_gdd_thresholds() -> void:
	for l in range(1, 16):
		assert_int(EconomyMath.exp_for_level(_r, l)).is_equal(CUMULATIVE[l - 1])
		assert_int(EconomyMath.exp_to_next(_r, l)).is_equal(TO_NEXT[l - 1])
	assert_int(EconomyMath.level_for_exp(_r, 0)).is_equal(1)
	assert_int(EconomyMath.level_for_exp(_r, 189)).is_equal(1)
	assert_int(EconomyMath.level_for_exp(_r, 190)).is_equal(2)
	assert_int(EconomyMath.level_for_exp(_r, 1449)).is_equal(5)
	assert_int(EconomyMath.level_for_exp(_r, 1450)).is_equal(6)
	assert_int(EconomyMath.level_for_exp(_r, 8290)).is_equal(15)
	assert_int(EconomyMath.level_for_exp(_r, 99999)).is_equal(15)


func test_skill_point_schedule_is_one_at_l1_plus_one_per_level() -> void:
	assert_int(EconomyMath.skill_points_total(1)).is_equal(1)
	assert_int(EconomyMath.skill_points_total(3)).is_equal(3)
	assert_int(EconomyMath.skill_points_total(15)).is_equal(15)
	# Slice tree: 3 Unlocks + 3 Boosts + 3 ult ranks = 9 nodes; 6 points stay banked at L15.
	assert_int(EconomyMath.skill_points_total(15) - 9).is_equal(6)


func test_share_factor_table() -> void:
	var expect := [1.00, 0.85, 0.69, 0.60, 0.54]
	for n in range(1, 6):
		assert_float(EconomyMath.share(_r, n)).is_equal_approx(expect[n - 1], 0.006)
	assert_float(EconomyMath.share(_r, 0)).is_equal(0.0)


func test_catchup_deficit_and_worked_kill_example() -> void:
	assert_float(EconomyMath.catchup(_r, 12, 8)).is_equal_approx(1.6, 1e-6)
	assert_float(EconomyMath.catchup(_r, 10, 9)).is_equal_approx(1.15, 1e-6)
	assert_float(EconomyMath.catchup(_r, 8, 12)).is_equal_approx(1.0, 1e-6)
	# §16.1 worked example: 18k vs 24k -> gap 0.25 -> D 1.125; L8 kills L12 -> 792, assist 396.
	var d := EconomyMath.deficit(_r, 18000.0, 24000.0)
	assert_float(d).is_equal_approx(1.125, 1e-6)
	assert_float(EconomyMath.kill_exp(_r, 12, 8, d)).is_equal_approx(792.0, 1e-3)
	assert_float(_r.exp_assist_frac * EconomyMath.kill_exp(_r, 12, 8, d)).is_equal_approx(396.0, 1e-3)
	assert_float(EconomyMath.deficit(_r, 24000.0, 24000.0)).is_equal(1.0)
	assert_float(EconomyMath.deficit(_r, 0.0, 24000.0)).is_equal_approx(1.25, 1e-6)  # capped


func test_shutdown_bounty() -> void:
	assert_int(EconomyMath.shutdown(_r, 2)).is_equal(0)
	assert_int(EconomyMath.shutdown(_r, 5)).is_equal(150)
	assert_int(EconomyMath.shutdown(_r, 12)).is_equal(300)


func test_wardling_kill_splits_75_instant_25_mote() -> void:
	var v := EconomyMath.wardling_lumen_split(_r, false, 1, 1)
	assert_float(v[0]).is_equal_approx(26.25, 1e-4)
	assert_float(v[1]).is_equal_approx(8.75, 1e-4)
	var sq := EconomyMath.wardling_lumen_split(_r, true, 2, 2)  # 75 × S(2)
	assert_float(sq[0] + sq[1]).is_equal_approx(75.0 * EconomyMath.share(_r, 2), 1e-4)
	assert_float(sq[0] / (sq[0] + sq[1])).is_equal_approx(0.75, 1e-6)
	assert_float(EconomyMath.wardling_exp(_r, false, 1, 1)).is_equal_approx(20.0, 1e-6)
	assert_float(EconomyMath.wardling_exp(_r, true, 1, 3)).is_equal_approx(45.0 * EconomyMath.share(_r, 3), 1e-6)


func test_sell_value_and_upgrade_cost() -> void:
	assert_int(EconomyMath.sell_value(_r, 400, 400)).is_equal(400)  # same visit: undo 100%
	assert_int(EconomyMath.sell_value(_r, 400, 0)).is_equal(240)  # later: 60%
	assert_int(EconomyMath.sell_value(_r, 1800, 0)).is_equal(1080)  # §4.7 example
	assert_int(EconomyMath.sell_value(_r, 350, 0)).is_equal(210)
	assert_int(EconomyMath.sell_value(_r, 650, 0)).is_equal(390)
	assert_int(EconomyMath.sell_value(_r, 330, 0)).is_equal(195)  # rounded down to 5
	assert_int(EconomyMath.sell_value(_r, 900, 500)).is_equal(500 + 240)  # tier II bought this visit
	var oc := ArmoryItemDef.new()  # a three-tier line (v1 shape; v22 items have one price)
	oc.prices = PackedInt32Array([400, 900, 1800])
	assert_int(EconomyMath.upgrade_cost(oc, 2, 1)).is_equal(500)
	assert_int(EconomyMath.upgrade_cost(oc, 3, 2)).is_equal(900)
	assert_int(EconomyMath.upgrade_cost(oc, 3, 0)).is_equal(1800)


func test_v22_catalog_prices_are_positive_and_consumables_stay_cheap() -> void:
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	for it in cat.items:
		assert_int(it.price(1)).override_failure_message("%s has no price" % it.id).is_greater(0)
		if it.kind == ArmoryItemDef.Kind.CONSUMABLE:
			assert_int(it.prices[0]).is_less_equal(200)
	var slice_rules := load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef
	assert_float(slice_rules.trickle_per_min).is_equal(60.0)  # §26 slice re-tune
	assert_int(slice_rules.starting_purse).is_equal(500)
