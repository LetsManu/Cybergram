extends GdUnitTestSuite
## Polish sprint 2026-10-05: pressing a skill that cannot fire says why
## (HotS-style reliable input). Before: no feedback at all on the press.


func test_locked_or_missing_skill_reports_locked() -> void:
	assert_str(String(SkillBar.deny_reason(true, false, true))).is_equal("locked")
	assert_str(String(SkillBar.deny_reason(false, false, false))).is_equal("locked")


func test_cooling_skill_reports_cooldown() -> void:
	assert_str(String(SkillBar.deny_reason(false, true, true))).is_equal("cooldown")


func test_ready_skill_is_not_denied() -> void:
	assert_str(String(SkillBar.deny_reason(false, false, true))).is_empty()


func test_press_on_a_cooling_slot_starts_a_short_pulse() -> void:
	var bar: SkillBar = auto_free(SkillBar.new())
	bar.note_press(1, &"cooldown")
	assert_float(bar.deny_left(1)).is_greater(0.0)
	assert_str(String(bar.deny_kind(1))).is_equal("cooldown")
	bar.tick_deny(SkillBar.DENY_S + 0.01)
	assert_float(bar.deny_left(1)).is_equal(0.0)


func test_ready_press_starts_no_pulse() -> void:
	var bar: SkillBar = auto_free(SkillBar.new())
	bar.note_press(0, &"")
	assert_float(bar.deny_left(0)).is_equal(0.0)
