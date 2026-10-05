extends GdUnitTestSuite
## W14-M2 Sudden Death (Canon C10, match-flow-and-map.md §3.1): a tied Time-out
## with sudden_death_enabled enters SUDDEN_DEATH; the ring shrinks 45 -> 4 m over
## 90 s; outside it 8 %/s; Leyfall Bloom from 90 s (2 %/s, +2 % per 10 s); the
## last team standing wins; a double wipe or the hard cap is a draw.

const DT := 1.0 / 30.0


func _rules(enabled: bool) -> MatchRulesDef:
	var r := MatchRulesDef.new()
	r.sudden_death_enabled = enabled
	return r


func test_tie_goes_to_sudden_death_only_when_enabled() -> void:
	var off := MatchRules.new(_rules(false))
	off.resolve_time_out()
	assert_int(off.phase).is_equal(MatchRules.Phase.END)
	assert_int(off.end_reason).is_equal(MatchRules.EndReason.DRAW)
	var on := MatchRules.new(_rules(true))
	var started := [0]
	on.sudden_death_started.connect(func() -> void: started[0] += 1)
	on.resolve_time_out()
	assert_int(on.phase).is_equal(MatchRules.Phase.SUDDEN_DEATH)
	assert_int(started[0]).is_equal(1)
	assert_bool(on.is_over()).is_false()


func test_ring_and_bloom_formulas() -> void:
	var m := MatchRules.new(_rules(true))
	m.resolve_time_out()
	assert_float(m.sudden_death_radius()).is_equal_approx(45.0, 0.001)
	assert_float(m.sudden_death_damage_frac_s(false)).is_equal(0.0)
	assert_float(m.sudden_death_damage_frac_s(true)).is_equal_approx(0.08, 0.0001)
	for i in 45 * 30:
		m.step(DT)
	assert_float(m.sudden_death_radius()).is_equal_approx(24.5, 0.1)  # halfway
	for i in 50 * 30:
		m.step(DT)
	assert_float(m.sudden_death_radius()).is_equal_approx(4.0, 0.001)
	# 95 s: Bloom base 2 %; 105 s: +2 %.
	assert_float(m.sudden_death_damage_frac_s(false)).is_equal_approx(0.02, 0.0001)
	for i in 10 * 30:
		m.step(DT)
	assert_float(m.sudden_death_damage_frac_s(false)).is_equal_approx(0.04, 0.0001)
	assert_float(m.sudden_death_damage_frac_s(true)).is_equal_approx(0.12, 0.0001)


func test_last_team_standing_wins() -> void:
	var m := MatchRules.new(_rules(true))
	m.resolve_time_out()
	m.resolve_sudden_death(2, 1)
	assert_int(m.phase).is_equal(MatchRules.Phase.SUDDEN_DEATH)
	m.resolve_sudden_death(0, 1)
	assert_int(m.phase).is_equal(MatchRules.Phase.END)
	assert_int(m.winner).is_equal(MapDef.TEAM_SYNDICATE)
	assert_int(m.end_reason).is_equal(MatchRules.EndReason.SUDDEN_DEATH)


func test_double_wipe_and_cap_are_draws() -> void:
	var m := MatchRules.new(_rules(true))
	m.resolve_time_out()
	m.resolve_sudden_death(0, 0)
	assert_int(m.end_reason).is_equal(MatchRules.EndReason.DRAW)
	var r := _rules(true)
	r.sudden_death_max_s = 30.0
	var c := MatchRules.new(r)
	c.resolve_time_out()
	for i in 31 * 30:
		c.step(DT)
	assert_int(c.phase).is_equal(MatchRules.Phase.END)
	assert_int(c.end_reason).is_equal(MatchRules.EndReason.DRAW)
