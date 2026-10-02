class_name BotMatchReport
extends RefCounted
## Match summary for bot-vs-bot runs (E11; feeds the E14 telemetry): winner,
## end reason, length, captures, kills, Uplink damage and bot cost, as one
## JSON object. Listens to ServerWorld / ObjectiveSystem / MatchRules signals.

const TEAM_NAMES: Array[String] = ["concord", "syndicate"]
const REASONS: Array[String] = ["none", "uplink_destroyed", "incursion", "uplink_damage", "draw"]

var server: ServerWorld
var director: BotDirector
var seed_value: int = 0
var captures: PackedInt32Array = PackedInt32Array([0, 0])
var kills: PackedInt32Array = PackedInt32Array([0, 0])
var first_capture_s: float = -1.0
## Ownership changes: "m:ss id C|S" (compact timeline).
var flips: PackedStringArray = PackedStringArray()
## Damage dealt to enemy heroes per attacking team (heroes only).
var damage: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var exposed_s: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var ended: bool = false
var end_tick: int = 0
var _exposed_since: PackedFloat32Array = PackedFloat32Array([-1.0, -1.0])
## Match time each team's Uplink was first Exposed (-1 = never).
var first_exposed_s: PackedFloat32Array = PackedFloat32Array([-1.0, -1.0])


func _init(s: ServerWorld, d: BotDirector, seed_: int) -> void:
	server = s
	director = d
	seed_value = seed_
	server.hero_died.connect(_on_hero_died)
	server.hero_damaged.connect(_on_hero_damaged)
	if server.objectives != null:
		server.objectives.hardpoint_flipped.connect(_on_flipped)
	if server.match_flow != null:
		server.match_flow.match_ended.connect(_on_ended)
		for u in server.match_flow.uplinks:
			u.exposure_changed.connect(_on_exposure.bind(u.team))


func _on_exposure(exposed: bool, team: int) -> void:
	var t := server.match_flow.time_s
	if exposed:
		_exposed_since[team] = t
		if first_exposed_s[team] < 0.0:
			first_exposed_s[team] = t
	elif _exposed_since[team] >= 0.0:
		exposed_s[team] += t - _exposed_since[team]
		_exposed_since[team] = -1.0


func summary() -> Dictionary:
	var mf := server.match_flow
	var d := {
		"seed": seed_value,
		"winner": TEAM_NAMES[mf.winner] if mf != null and mf.winner >= 0 and mf.winner <= 1 else "none",
		"end_reason": REASONS[mf.end_reason] if mf != null else "none",
		"duration_s": snappedf(mf.time_s, 0.1) if mf != null else 0.0,
		"clock": MatchRules.format_clock(mf.time_s) if mf != null else "0:00",
		"clock_scale": mf.clock_scale if mf != null else 1.0,
		"ticks": server.tick,
		"captures": {TEAM_NAMES[0]: captures[0], TEAM_NAMES[1]: captures[1]},
		"first_capture_s": snappedf(first_capture_s, 0.1),
		"kills": {TEAM_NAMES[0]: kills[0], TEAM_NAMES[1]: kills[1]},
		"uplink_pct_dealt": {},
		"uplink_exposed_s": {TEAM_NAMES[0]: snappedf(exposed_s[0], 0.1), TEAM_NAMES[1]: snappedf(exposed_s[1], 0.1)},
		"ownership": _ownership(),
		"flips": flips,
	}
	if mf != null:
		d["uplink_pct_dealt"] = {TEAM_NAMES[0]: snappedf(mf.uplink_pct_dealt(0), 0.01),
			TEAM_NAMES[1]: snappedf(mf.uplink_pct_dealt(1), 0.01)}
		d["incursion"] = [mf.incursion(0), mf.incursion(1)]
	if director != null:
		d["bots"] = director.brains.size()
		d["bot_cost"] = director.meter.summary()
		var shots := 0
		var skills := 0
		var orders := 0
		var gt := PackedInt32Array([0, 0, 0, 0, 0, 0])
		var dec_us := 0
		for b in director.brains:
			dec_us += b.decide_usec
			for k in gt.size():
				gt[k] += b.goal_ticks[k]
			shots += b.shots_pressed
			skills += b.skills_pressed
			orders += b.squad_orders
		d["bot_shots"] = shots
		d["bot_skill_casts"] = skills
		d["bot_squad_orders"] = orders
		var total := 0.0
		for v in gt:
			total += v
		total = maxf(total, 1.0)
		var share := {}
		for k in gt.size():
			share[BotGoal.NAMES[k]] = snappedf(gt[k] / total, 0.001)
		d["bot_goal_share"] = share
		d["bot_decide_ms_per_tick"] = snappedf(dec_us / 1000.0 / maxf(server.tick, 1), 0.001)
		d["damage_to_heroes"] = {TEAM_NAMES[0]: roundi(damage[0]), TEAM_NAMES[1]: roundi(damage[1])}
	d["tick_time"] = server.tick_time_summary()
	d["tasks"] = _tasks()
	d["levels"] = _levels()
	d["uplink_first_exposed_s"] = {TEAM_NAMES[0]: snappedf(first_exposed_s[0], 0.1), TEAM_NAMES[1]: snappedf(first_exposed_s[1], 0.1)}
	if server.wardlings != null:
		d["wardling_step_ms_avg"] = snappedf(server.wardlings.step_usec_total / 1000.0 / maxf(server.wardlings.steps, 1), 0.001)
	return d


## E14: Plant / Breach counters over the match.
func _tasks() -> Dictionary:
	var out := {"cells_planted": 0, "cells_defused": 0, "generators_destroyed": 0, "gen_damage": 0, "gen_blocked": 0}
	if server.objectives != null:
		for h in server.objectives.all:
			out["cells_planted"] += h.cells_planted
			out["cells_defused"] += h.cells_defused
			out["generators_destroyed"] += h.generators_destroyed
			out["gen_damage"] += roundi(h.gen_damage)
			out["gen_blocked"] += roundi(h.gen_blocked)
	return out


## Mean hero level per team at the end (E15 pacing).
func _levels() -> Dictionary:
	var out := {}
	var prog = server.get("progression")
	if prog == null:
		return out
	var sum := [0.0, 0.0]
	var n := [0, 0]
	for id in prog.progress:
		var h := server.hero(id)
		if h != null and h.combat != null:
			sum[h.combat.team] += prog.progress[id].level
			n[h.combat.team] += 1
	for t in 2:
		out[TEAM_NAMES[t]] = snappedf(sum[t] / maxf(n[t], 1), 0.1)
	return out


func to_json() -> String:
	return JSON.stringify(summary())


## "AAMBB"-style owner string along the lane: C, S or - (neutral).
func _ownership() -> String:
	var s := ""
	if server.objectives == null:
		return s
	for h in server.objectives.all:
		s += "C" if h.owner == 0 else ("S" if h.owner == 1 else "-")
	return s


func _on_hero_died(victim: int, killer: int) -> void:
	var k := server.hero(killer)
	if k != null and k.combat != null and killer != victim:
		kills[k.combat.team] += 1


func _on_hero_damaged(_victim: int, attacker: int, amount: float) -> void:
	var a := server.hero(attacker)
	if a != null and a.combat != null:
		damage[a.combat.team] += amount


func _on_flipped(hp: HardpointSim, _old: int, new_team: int) -> void:
	if new_team >= 0 and new_team <= 1:
		captures[new_team] += 1
		if server.match_flow != null and flips.size() < 200:
			flips.append("%s %s %s" % [MatchRules.format_clock(server.match_flow.time_s), hp.def.id, "C" if new_team == 0 else "S"])
		if first_capture_s < 0.0 and server.match_flow != null:
			first_capture_s = server.match_flow.time_s


func _on_ended(_winner: int, _reason: int) -> void:
	ended = true
	end_tick = server.tick
