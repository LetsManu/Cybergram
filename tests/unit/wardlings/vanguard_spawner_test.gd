extends GdUnitTestSuite
## Vanguard cadence and gate (Canon C15, wardlings-and-economy.md §10).

const HZ: int = 30

var _rules: WardlingRulesDef


func before_test() -> void:
	_rules = load("res://assets/data/wardlings/wardling_rules_slice.tres") as WardlingRulesDef


func test_waves_tick_every_60_s_from_1_00() -> void:
	assert_bool(VanguardSpawner.is_wave_tick(0, _rules, HZ)).is_false()
	assert_bool(VanguardSpawner.is_wave_tick(60 * HZ - 1, _rules, HZ)).is_false()
	assert_bool(VanguardSpawner.is_wave_tick(60 * HZ, _rules, HZ)).is_true()
	assert_bool(VanguardSpawner.is_wave_tick(90 * HZ, _rules, HZ)).is_false()
	assert_bool(VanguardSpawner.is_wave_tick(120 * HZ, _rules, HZ)).is_true()


func test_debug_clock_scales_the_cadence() -> void:
	assert_int(VanguardSpawner.first_tick(_rules, HZ, 30.0)).is_equal(60)
	assert_bool(VanguardSpawner.is_wave_tick(60, _rules, HZ, 30.0)).is_true()
	assert_bool(VanguardSpawner.is_wave_tick(120, _rules, HZ, 30.0)).is_true()


func test_gate_spawns_only_when_previous_wave_has_at_most_one_alive() -> void:
	assert_int(VanguardSpawner.mint_count(0, _rules)).is_equal(4)
	assert_int(VanguardSpawner.mint_count(1, _rules)).is_equal(3)  # survivor merges: never more than 4
	for alive in [2, 3, 4]:
		assert_int(VanguardSpawner.mint_count(alive, _rules)).is_equal(0)  # lane skips this tick
