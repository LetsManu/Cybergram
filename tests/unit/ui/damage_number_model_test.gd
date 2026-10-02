extends GdUnitTestSuite
## E12 damage numbers (design/ux/hud.md §13.2): Compact merges hits on one
## target within the merge window, Full is per hit, Off shows nothing.

const MERGE: float = 0.5
const LIFE: float = 0.9


func test_compact_merges_within_window() -> void:
	var m := DamageNumberModel.new(DamageNumberModel.Mode.COMPACT, MERGE, LIFE)
	m.add(7, 20.0, false, false, Vector3.ZERO)
	m.advance(0.3)
	m.add(7, 22.0, true, false, Vector3.ONE)
	assert_int(m.numbers.size()).is_equal(1)
	var n := m.numbers[0]
	assert_float(n.amount).is_equal(42.0)
	assert_bool(n.headshot).is_true()
	assert_float(n.age).is_equal(0.0)  # restarts its life
	assert_str(DamageNumberModel.text_of(n)).is_equal("42!")


func test_compact_new_number_after_window_or_other_target() -> void:
	var m := DamageNumberModel.new(DamageNumberModel.Mode.COMPACT, MERGE, LIFE)
	m.add(7, 20.0, false, false, Vector3.ZERO)
	m.add(8, 20.0, false, false, Vector3.ZERO)
	assert_int(m.numbers.size()).is_equal(2)
	m.advance(0.6)
	m.add(7, 5.0, false, false, Vector3.ZERO)
	assert_int(m.numbers.size()).is_equal(3)


func test_full_mode_one_number_per_hit() -> void:
	var m := DamageNumberModel.new(DamageNumberModel.Mode.FULL, MERGE, LIFE)
	m.add(7, 20.0, false, false, Vector3.ZERO)
	m.add(7, 20.0, false, false, Vector3.ZERO)
	assert_int(m.numbers.size()).is_equal(2)


func test_off_mode_shows_nothing() -> void:
	var m := DamageNumberModel.new(DamageNumberModel.Mode.OFF, MERGE, LIFE)
	assert_object(m.add(7, 20.0, false, false, Vector3.ZERO)).is_null()
	assert_bool(m.numbers.is_empty()).is_true()


func test_numbers_expire_and_fade() -> void:
	var m := DamageNumberModel.new(DamageNumberModel.Mode.COMPACT, MERGE, LIFE)
	m.add(7, 20.4, false, false, Vector3.ZERO)
	assert_str(DamageNumberModel.text_of(m.numbers[0])).is_equal("20")
	m.advance(0.45)
	assert_float(m.alpha(m.numbers[0])).is_equal_approx(1.0, 1e-4)
	m.advance(0.225)
	assert_float(m.alpha(m.numbers[0])).is_equal_approx(0.5, 1e-4)
	m.advance(0.3)
	assert_bool(m.numbers.is_empty()).is_true()
