extends GdUnitTestSuite
## Headless economy sanity check (wardlings-and-economy.md §18, §25 AC 1–2,
## §26): the GDD's per-minute average-player model run through the production
## formulas and data (EconomyMath, EconomyRulesDef, the Resonance table).
## Two configurations:
## - "gdd": GDD defaults (trickle 40/min, Sentinels in) -> must reproduce the
##   §18 average column (Lumen ~1,550 / 2,880 / 5,790 / 8,970 at 5/10/20/30 min);
## - "slice": the slice .tres (trickle 60/min, no Sentinels, Tier II from 15:00).
## Prints both tables (the report quotes them).

## §18 model inputs (average player).
const VANGUARD_PER_MIN: float = 2.8
const VANGUARD_GROWTH: float = 0.01
const SQUAD_PER_MIN: float = 0.7
const SENTINEL_PER_MIN: float = 0.25
const MEAN_SHARE: float = 0.8
const MOTE_COLLECT: float = 0.8
const KILLS_PER_MIN: float = 0.17
const ASSISTS_PER_MIN: float = 0.24
## Over 30 minutes: captures participated in, team captures, defences.
const CAPTURES_PART: float = 4.0
const CAPTURES_TEAM: float = 10.0
const DEFENCES: float = 4.0
const SENTINEL_MULT: float = 1.5
## Deploy (0:00–1:00): no waves, nothing capturable.
const DEPLOY_MIN: float = 1.0
## GDD §18 average column: [minute, Lumen, EXP, level].
const GDD_AVG: Array = [[5, 1550, 1050, 4], [10, 2880, 2370, 7], [20, 5790, 5230, 11], [30, 8970, 8360, 15]]


## Integrates the model in 1 s steps; returns {minute: [lumen, exp, level]} and "l6" (minutes).
## Activity (waves, squads, kills, captures) starts at 1:00: Deploy has no
## Vanguard waves and nothing is capturable (match-flow-and-map.md §2).
static func run_model(r: EconomyRulesDef, sentinels: bool, surge_s: float = 900.0) -> Dictionary:
	var out := {}
	var lumen := float(r.starting_purse)
	var xp := 0.0
	var l6 := -1.0
	var dt := 1.0 / 60.0  # minutes
	var steps := 30 * 60
	for i in steps:
		var m := (i + 0.5) * dt
		var tier := 1 if m * 60.0 < surge_s else 2
		var level := EconomyMath.level_for_exp(r, floori(xp))
		if m >= r.trickle_start_s / 60.0:
			lumen += r.trickle_per_min * dt
		var sec := i + 1
		if m < DEPLOY_MIN:
			continue
		var van := VANGUARD_PER_MIN * (1.0 + VANGUARD_GROWTH * m) * dt
		var lv := float(r.lumen_vanguard[tier - 1]) * MEAN_SHARE
		lumen += van * lv * ((1.0 - r.mote_fraction) + r.mote_fraction * MOTE_COLLECT)
		xp += van * r.exp_vanguard[tier - 1] * MEAN_SHARE
		var sq := SQUAD_PER_MIN * dt
		lumen += sq * r.lumen_squad[tier - 1] * MEAN_SHARE * ((1.0 - r.mote_fraction) + r.mote_fraction * MOTE_COLLECT)
		xp += sq * r.exp_squad[tier - 1] * MEAN_SHARE
		if sentinels:
			var se := SENTINEL_PER_MIN * dt
			lumen += se * SENTINEL_MULT * r.lumen_squad[tier - 1] * MEAN_SHARE
			xp += se * SENTINEL_MULT * r.exp_squad[tier - 1] * MEAN_SHARE
		var p_kill := EconomyMath.kill_exp(r, level, level, 1.0)
		lumen += KILLS_PER_MIN * dt * r.kill_lumen_base + ASSISTS_PER_MIN * dt * r.assist_lumen
		xp += KILLS_PER_MIN * dt * p_kill + ASSISTS_PER_MIN * dt * r.exp_assist_frac * p_kill
		lumen += (CAPTURES_TEAM * 40.0 + CAPTURES_PART * 120.0 + DEFENCES * 60.0) / 29.0 * dt
		xp += (CAPTURES_TEAM * r.exp_capture_team + CAPTURES_PART * r.exp_capture_participant
			+ DEFENCES * r.exp_defence) / 29.0 * dt
		if l6 < 0.0 and EconomyMath.level_for_exp(r, floori(xp)) >= 6:
			l6 = (i + 1) * dt
		if sec % 300 == 0:
			out[sec / 60] = [roundi(lumen), roundi(xp), EconomyMath.level_for_exp(r, floori(xp))]
	out["l6"] = l6
	return out


static func _table(name: String, res: Dictionary) -> String:
	var t := "[economy] %s: L6 at %.1f min\n" % [name, res["l6"]]
	for row in GDD_AVG:
		var v: Array = res[row[0]]
		t += "[economy]   %2d min  Lumen %5d (GDD %5d, %+4.0f%%)  EXP %5d (GDD %5d)  L%-2d (GDD L%d)\n" % [
			row[0], v[0], row[1], (float(v[0]) / row[1] - 1.0) * 100.0, v[1], row[2], v[2], row[3]]
	return t


func test_gdd_model_reproduces_the_average_lumen_curve() -> void:
	var res := run_model(EconomyRulesDef.new(), true)
	print(_table("gdd defaults (trickle 40, Sentinels)", res))
	for row in GDD_AVG:
		var v: Array = res[row[0]]
		assert_float(float(v[0])).is_between(row[1] * 0.93, row[1] * 1.07)  # Lumen within 7%
	assert_float(res["l6"]).is_between(6.0, 8.0)  # §25 AC 2: L6 in 6:00–8:00


func test_slice_model_stays_on_the_curve_without_sentinels() -> void:
	var r := load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef
	var res := run_model(r, false)
	print(_table("slice (trickle 60, no Sentinels)", res))
	var v30: Array = res[30]
	assert_float(float(v30[0])).is_between(8000.0, 10000.0)  # §25 AC 1 band
	assert_float(res["l6"]).is_between(6.0, 8.0)
	assert_int(v30[2]).is_greater_equal(14)  # §26: L14–15 at 30:00
