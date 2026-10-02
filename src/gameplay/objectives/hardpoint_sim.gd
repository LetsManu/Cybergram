class_name HardpointSim
extends RefCounted
## Server-side state and Hold task of one hardpoint (architecture.md §5.4,
## match-flow-and-map.md §3.4-§3.5, F2/F3). Pure logic: ObjectiveSystem fills
## presence, eligibility and severed state each tick, then calls step().
##
## Task support: HOLD. PLANT and BREACH nodes run as Hold while
## MatchRulesDef.stage_all_as_hold is on (M1 staging, §3.7); `def.task` keeps
## the authored TaskKind.

signal ownership_changed(old_team: int, new_team: int)
signal contested_changed(is_contested: bool)

const NEUTRAL: int = MapDef.TEAM_NEUTRAL

enum StepResult { NONE, FLIPPED, DEFENDED }

var def: HardpointDef
var lane: int = 0
## Index along the lane (0 = nearest Concord HQ).
var index: int = 0
## Effective task this match runs (HOLD while staged).
var task: HardpointDef.TaskKind = HardpointDef.TaskKind.HOLD
## Hold T_base in seconds (before D_s and K_sev).
var base_s: float = 60.0

var owner: int = NEUTRAL
## Capture progress P in [0, 1]; belongs to capturing_team.
var progress: float = 0.0
## Team the progress belongs to, NEUTRAL when P = 0.
var capturing_team: int = NEUTRAL
## Attacker present and not out-numbering (frozen), or equal presence on neutral.
var contested: bool = false
## Seconds left in the Overtime freeze (> 0 = HUD "OVERTIME").
var overtime_left: float = 0.0

## Filled by ObjectiveSystem every tick, indexed by team (0, 1).
var presence: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var heroes_in: PackedInt32Array = PackedInt32Array([0, 0])
var eligible: Array[bool] = [true, true]
var severed: bool = false
## Hero net id -> [team, last second seen in the zone] (participant rewards).
var recent_heroes: Dictionary = {}

var _attacker_was_present: bool = false
var _peak: float = 0.0


func _init(d: HardpointDef, lane_: int, index_: int, rules: MatchRulesDef) -> void:
	def = d
	lane = lane_
	index = index_
	owner = d.initial_owner
	task = d.task
	base_s = d.base_duration_s
	if d.task != HardpointDef.TaskKind.HOLD and rules.stage_all_as_hold:
		task = HardpointDef.TaskKind.HOLD
		if d.tier < rules.staged_hold_base_s.size():
			base_s = rules.staged_hold_base_s[d.tier]


## True if `pos` lies in the zone cylinder (r = zone_radius, zone_height tall,
## 1 m tolerance below the floor).
func zone_contains(pos: Vector3) -> bool:
	var c := def.position
	if pos.y < c.y - 1.0 or pos.y > c.y + def.zone_height:
		return false
	return Vector2(pos.x - c.x, pos.z - c.z).length_squared() <= def.zone_radius * def.zone_radius


## True when `team` may not attack this hardpoint (HUD "Locked").
func locked_for(team: int) -> bool:
	return team != owner and not eligible[team]


## F2: dP/dt = K_hl × M(Δ) / (T_base × D_s × K_sev), 0 for Δ <= 0.
static func capture_rate(delta: float, attacker_hero: bool, t_base: float, d_s: float, k_sev: float,
		rules: MatchRulesDef) -> float:
	if delta <= 0.0:
		return 0.0
	var m := minf(rules.capture_m_max, rules.capture_m_intercept + rules.capture_m_slope * delta)
	var k_hl := 1.0 if attacker_hero else rules.heroless_mult
	return k_hl * m / (t_base * d_s * k_sev)


## F3 decay per second after the Overtime window.
static func decay_rate(defender_present: bool, t_base: float, d_s: float, rules: MatchRulesDef) -> float:
	return (rules.decay_mult_defended if defender_present else rules.decay_mult) / (t_base * d_s)


## One tick. `d_s` is the Surge duration multiplier (F5).
func step(dt: float, d_s: float, rules: MatchRulesDef) -> StepResult:
	var was_contested := contested
	var result := _step_neutral(dt, d_s, rules) if owner == NEUTRAL else _step_owned(dt, d_s, rules)
	if result == StepResult.NONE and progress >= 1.0:
		result = _flip()
	if contested != was_contested:
		contested_changed.emit(contested)
	return result


func _step_owned(dt: float, d_s: float, rules: MatchRulesDef) -> StepResult:
	var a := 1 - owner
	var att := presence[a] if eligible[a] else 0.0
	var dfn := presence[owner]
	var k_sev := rules.severed_mult if severed else 1.0
	contested = false
	if progress > 0.0 and not eligible[a]:
		# Prerequisite lost mid-task: drain at 2x decay, no Overtime (§3.4).
		overtime_left = 0.0
		_attacker_was_present = false
		progress -= rules.drain_mult * decay_rate(dfn > 0.0, base_s, d_s, rules) * dt
	elif att > 0.0:
		capturing_team = a
		overtime_left = 0.0
		_attacker_was_present = true
		var delta := att - dfn
		if delta > 0.0:
			progress += capture_rate(delta, heroes_in[a] > 0, base_s, d_s, k_sev, rules) * dt
			if def.tier == HardpointDef.Tier.INNER and heroes_in[a] == 0:
				progress = minf(progress, rules.heroless_inner_cap)
		else:
			contested = true
	elif progress > 0.0:
		_overtime_or_decay(dt, decay_rate(dfn > 0.0, base_s, d_s, rules), rules)
	else:
		_attacker_was_present = false
	return _settle(rules)


## Neutral Mid: the higher-presence team is the attacker; the other team's
## progress first drains at 2x decay; equal presence freezes (§3.4).
func _step_neutral(dt: float, d_s: float, rules: MatchRulesDef) -> StepResult:
	var p0 := presence[0] if eligible[0] else 0.0
	var p1 := presence[1] if eligible[1] else 0.0
	contested = false
	if p0 == p1:
		if p0 > 0.0:
			contested = true
			overtime_left = 0.0
			_attacker_was_present = true
		elif progress > 0.0:
			_overtime_or_decay(dt, decay_rate(false, base_s, d_s, rules), rules)
		else:
			_attacker_was_present = false
		return _settle(rules)
	var h := 0 if p0 > p1 else 1
	overtime_left = 0.0
	if capturing_team == NEUTRAL or capturing_team == h or progress <= 0.0:
		capturing_team = h
		_attacker_was_present = true
		progress += capture_rate(absf(p0 - p1), heroes_in[h] > 0, base_s, d_s, 1.0, rules) * dt
	else:
		_attacker_was_present = false
		progress -= rules.drain_mult * decay_rate(false, base_s, d_s, rules) * dt
		if progress <= 0.0:
			progress = 0.0
			capturing_team = h  # the new team builds from the next tick
			_peak = 0.0
			return StepResult.NONE
	return _settle(rules)


func _overtime_or_decay(dt: float, decay: float, rules: MatchRulesDef) -> void:
	if _attacker_was_present:
		_attacker_was_present = false
		overtime_left = rules.overtime_long_s if progress >= rules.overtime_long_threshold else rules.overtime_short_s
	if overtime_left > 0.0:
		overtime_left = maxf(0.0, overtime_left - dt)
	else:
		progress -= decay * dt


func _settle(rules: MatchRulesDef) -> StepResult:
	_peak = maxf(_peak, progress)
	if progress > 0.0:
		return StepResult.NONE
	progress = 0.0
	var defended := owner != NEUTRAL and capturing_team != NEUTRAL and _peak >= rules.defence_threshold
	if capturing_team != NEUTRAL and not _attacker_was_present:
		capturing_team = NEUTRAL
		overtime_left = 0.0
	if capturing_team == NEUTRAL or defended:
		_peak = 0.0
	return StepResult.DEFENDED if defended else StepResult.NONE


func _flip() -> StepResult:
	var old := owner
	owner = capturing_team
	progress = 0.0
	capturing_team = NEUTRAL
	contested = false
	overtime_left = 0.0
	_attacker_was_present = false
	_peak = 0.0
	ownership_changed.emit(old, owner)
	return StepResult.FLIPPED
