extends GdUnitTestSuite
## E12 HUD formatters (design/ux/hud.md §4.4 cooldown tenths, §4.5 Lumen
## separators, §4.8 clock, §4.10 name truncation).


func test_clock_minutes_seconds() -> void:
	assert_str(HudFormat.clock(0.0)).is_equal("0:00")
	assert_str(HudFormat.clock(59.99)).is_equal("0:59")
	assert_str(HudFormat.clock(60.0)).is_equal("1:00")
	assert_str(HudFormat.clock(23.0 * 60.0 + 41.4)).is_equal("23:41")
	assert_str(HudFormat.clock(65.0 * 60.0)).is_equal("65:00")  # minutes are not capped
	assert_str(HudFormat.clock(-3.0)).is_equal("0:00")


func test_thousands_separators() -> void:
	assert_str(HudFormat.thousands(0)).is_equal("0")
	assert_str(HudFormat.thousands(999)).is_equal("999")
	assert_str(HudFormat.thousands(1240)).is_equal("1,240")
	assert_str(HudFormat.thousands(1000000)).is_equal("1,000,000")
	assert_str(HudFormat.thousands(-5000)).is_equal("-5,000")


func test_cooldown_tenths_at_or_below_three_seconds() -> void:
	assert_str(HudFormat.cooldown(0.0)).is_equal("")
	assert_str(HudFormat.cooldown(-1.0)).is_equal("")
	assert_str(HudFormat.cooldown(3.0)).is_equal("3.0")
	assert_str(HudFormat.cooldown(2.41)).is_equal("2.5")  # rounds up: never shows ready early
	assert_str(HudFormat.cooldown(0.05)).is_equal("0.1")
	assert_str(HudFormat.cooldown(3.01)).is_equal("4")
	assert_str(HudFormat.cooldown(12.0)).is_equal("12")


func test_percent_rounds_up_and_clamps() -> void:
	assert_int(HudFormat.percent(0.0)).is_equal(0)
	assert_int(HudFormat.percent(0.001)).is_equal(1)  # a scratched bar never reads 0%
	assert_int(HudFormat.percent(0.62)).is_equal(62)
	assert_int(HudFormat.percent(0.915)).is_equal(92)
	assert_int(HudFormat.percent(1.0)).is_equal(100)
	assert_int(HudFormat.percent(1.7)).is_equal(100)


func test_seconds_up_and_pairs() -> void:
	assert_int(HudFormat.seconds_up(13.2)).is_equal(14)
	assert_int(HudFormat.seconds_up(14.0)).is_equal(14)
	assert_int(HudFormat.seconds_up(-1.0)).is_equal(0)
	assert_str(HudFormat.pair(212, 279)).is_equal("212 / 279")
	assert_str(HudFormat.kd(7, 3)).is_equal("7 / 3")


func test_truncate_names() -> void:
	assert_str(HudFormat.truncate("Vesper Loom", 16)).is_equal("Vesper Loom")
	assert_str(HudFormat.truncate("Vesper Loom", 7)).is_equal("Vesper…")
	assert_int(HudFormat.truncate("Brannoc the Unbroken", 10).length()).is_equal(10)
