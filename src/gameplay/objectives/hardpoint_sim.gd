class_name HardpointSim
extends RefCounted
## Server-side state and task of one hardpoint (architecture.md §5.4,
## match-flow-and-map.md §3.4-§3.5, F2-F4). Pure logic: ObjectiveSystem fills
## presence, eligibility and severed state each tick, then calls step().
##
## Tasks (E7 Hold, E14 Plant and Breach), on owned hardpoints:
##   HOLD   P rises with presence advantage (F2).
##   PLANT  the attacker carries a Mana Cell from its Cradle (1 s pickup), plants
##          it in the zone (3 s channel); P charges only while it is planted (F3,
##          half speed while out-numbered); a defender hero defuses (6 s). A
##          dropped Cell lies 15 s; a defender standing on it 2 s disperses it.
##   BREACH phase 1: the Ward Generator (HP = base × D_s) takes damage only from
##          eligible attackers inside the zone, and none while Pres(def) >
##          Pres(att) (shield); it regenerates 4%/s after 8 s idle. Phase 2: a
##          Hold of def.base_duration_s; idle at P = 0 for 15 s resets phase 1.
## PLANT and BREACH run as Hold while MatchRulesDef.stage_all_as_hold is on (M1
## staging, §3.7); `def.task` keeps the authored TaskKind. A neutral Plant or
## Breach node (not on the slice map) also runs as Hold.

signal ownership_changed(old_team: int, new_team: int)
signal contested_changed(is_contested: bool)

const NEUTRAL: int = MapDef.TEAM_NEUTRAL

enum StepResult { NONE, FLIPPED, DEFENDED }
## Plant: where this hardpoint's active Mana Cell is.
enum CellState { NONE, CRADLE, CARRIED, DROPPED, PLANTED }
## Plant: the interact channel running this tick.
enum Channel { NONE, PICKUP, PLANT, DEFUSE, DISPERSE }

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

## ---- Plant (E14) ----
var cell_state: CellState = CellState.NONE
## Team the Cell belongs to (the attacker), NEUTRAL when none.
var cell_team: int = NEUTRAL
var cell_pos: Vector3 = Vector3.ZERO
## Hero net id carrying the Cell (CARRIED), else 0.
var carrier_id: int = 0
## NONE: seconds until the Cradle offers a Cell; DROPPED: seconds before it expires.
var cell_timer: float = 0.0
var channel: Channel = Channel.NONE
var channel_hero: int = 0
## Seconds channelled so far.
var channel_t: float = 0.0
## Hero that planted the active Cell (a capture participant, §16.1).
var planter_id: int = 0
## Counters (telemetry / tests).
var cells_planted: int = 0
var cells_defused: int = 0

## ---- Breach (E14) ----
## 1 = Ward Generator up, 2 = the hold after the breach.
var breach_phase: int = 1
## Generator HP as a fraction of HP_base × D_s (in-progress fraction survives a Surge).
var gen_frac: float = 1.0
## Pres(def) > Pres(att): the Generator takes no damage.
var gen_shielded: bool = false
## Seconds since the last attacker damage (regen after generator_regen_delay_s).
var gen_idle_s: float = 0.0
## Phase 2 at P = 0 with no attacker present (reset after breach_reset_idle_s).
var phase2_idle_s: float = 0.0
var generators_destroyed: int = 0
## Telemetry: Generator damage landed / stopped by the shield (out-numbered or from outside).
var gen_damage: float = 0.0
var gen_blocked: float = 0.0

var _attacker_was_present: bool = false
var _peak: float = 0.0
var _d_s: float = 1.0
var _regen_delay_s: float = 8.0
var _gen_hp_mult: float = 1.0
var _defused: bool = false


func _init(d: HardpointDef, lane_: int, index_: int, rules: MatchRulesDef) -> void:
	def = d
	lane = lane_
	index = index_
	owner = d.initial_owner
	task = d.task
	base_s = d.base_duration_s
	if d.task != HardpointDef.TaskKind.HOLD and (rules.stage_all_as_hold or d.initial_owner == NEUTRAL):
		task = HardpointDef.TaskKind.HOLD
		if d.tier < rules.staged_hold_base_s.size():
			base_s = rules.staged_hold_base_s[d.tier]
	elif task == HardpointDef.TaskKind.PLANT:
		cell_timer = 0.0  # the Cradle offers a Cell as soon as the attacker is eligible
		base_s = d.base_duration_s * rules.plant_base_mult  # slice tuning (1.0 = map value)
	_gen_hp_mult = rules.generator_hp_mult


## Generator max HP at Surge scale `d_s` (F4: HP_base × D_s; × the slice's generator_hp_mult).
func generator_max(d_s: float = -1.0) -> float:
	return def.generator_hp * _gen_hp_mult * (_d_s if d_s < 0.0 else d_s)


## Current Generator HP (Breach phase 1), else 0.
func generator_hp() -> float:
	return gen_frac * generator_max() if task == HardpointDef.TaskKind.BREACH and breach_phase == 1 else 0.0


## True while `team` can damage this Generator at all (phase 1, an eligible attacker).
func generator_attackable_by(team: int) -> bool:
	return task == HardpointDef.TaskKind.BREACH and breach_phase == 1 and owner != NEUTRAL \
		and team == 1 - owner and eligible[team]


## Breach phase 1 (§3.4 Breach 1, F4): a hit of `amount` (already scaled for
## Wardlings) from `team`, fired from `source_pos`. Blocked by the shield (all
## damage while Pres(def) > Pres(att), and damage from outside the zone) and
## ignored from an ineligible team. Returns the HP removed.
func damage_generator(amount: float, team: int, source_pos: Vector3) -> float:
	if amount <= 0.0 or not generator_attackable_by(team):
		return 0.0
	if gen_shielded or not zone_contains(source_pos):
		gen_blocked += amount
		return 0.0
	gen_damage += amount
	var mx := maxf(generator_max(), 1.0)
	var a := minf(amount, gen_frac * mx)
	gen_frac -= a / mx
	gen_idle_s = 0.0
	if gen_frac <= 1e-6:
		gen_frac = 0.0
		breach_phase = 2
		phase2_idle_s = 0.0
		generators_destroyed += 1
	return a


## An enemy is working this (owned) hardpoint: Hold progress, a damaged
## Generator, the hold after a breach, or an enemy Cell carried / planted.
func is_under_attack() -> bool:
	if owner == NEUTRAL:
		return false
	if progress > 0.0 and capturing_team == 1 - owner:
		return true
	match task:
		HardpointDef.TaskKind.BREACH:
			return breach_phase == 2 or (gen_frac < 1.0 and gen_idle_s < _regen_delay_s)
		HardpointDef.TaskKind.PLANT:
			return cell_state == CellState.PLANTED or cell_state == CellState.CARRIED
	return false


## How urgent the defence is, 0..1 (bots).
func pressure() -> float:
	if not is_under_attack():
		return 0.0
	match task:
		HardpointDef.TaskKind.BREACH:
			return 0.5 + 0.5 * progress if breach_phase == 2 else 0.5 * (1.0 - gen_frac)
		HardpointDef.TaskKind.PLANT:
			return 0.5 + 0.5 * progress if cell_state == CellState.PLANTED else 0.3
	return progress


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


## One tick. `d_s` is the Surge duration multiplier (F5). `actors` (net id ->
## TaskActor) and `carriers` (hero net id -> HardpointSim, shared by all
## hardpoints) drive Plant; Hold and Breach ignore them.
func step(dt: float, d_s: float, rules: MatchRulesDef, actors: Dictionary = {}, carriers: Dictionary = {}) -> StepResult:
	var was_contested := contested
	_d_s = d_s
	_regen_delay_s = rules.generator_regen_delay_s
	_defused = false
	var result := StepResult.NONE
	if owner == NEUTRAL:
		result = _step_neutral(dt, d_s, rules)
	elif task == HardpointDef.TaskKind.PLANT:
		result = _step_plant(dt, d_s, rules, actors, carriers)
	elif task == HardpointDef.TaskKind.BREACH:
		result = _step_breach(dt, d_s, rules)
	else:
		result = _step_owned(dt, d_s, rules)
	if result == StepResult.NONE and progress >= 1.0:
		result = _flip()
	if result == StepResult.NONE and _defused:
		result = StepResult.DEFENDED
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


## Breach (§3.4 Breach): phase 1 is the Generator (damage arrives through
## damage_generator() between steps), phase 2 the Hold of def.base_duration_s.
func _step_breach(dt: float, d_s: float, rules: MatchRulesDef) -> StepResult:
	var a := 1 - owner
	var att := presence[a] if eligible[a] else 0.0
	var dfn := presence[owner]
	if breach_phase == 1:
		contested = false
		overtime_left = 0.0
		gen_shielded = dfn > att
		gen_idle_s += dt
		if gen_idle_s >= rules.generator_regen_delay_s and gen_frac < 1.0:
			gen_frac = minf(1.0, gen_frac + rules.generator_regen_frac_s * dt)
		return StepResult.NONE
	gen_shielded = false
	var r := _step_owned(dt, d_s, rules)
	if progress <= 0.0 and att <= 0.0:
		phase2_idle_s += dt
		if phase2_idle_s >= rules.breach_reset_idle_s:
			_reset_generator()
	else:
		phase2_idle_s = 0.0
	return r


func _reset_generator() -> void:
	breach_phase = 1
	gen_frac = 1.0
	gen_idle_s = 0.0
	phase2_idle_s = 0.0
	gen_shielded = false


## Plant (§3.4 Plant, F3): the Cell state machine, then charge / decay.
func _step_plant(dt: float, d_s: float, rules: MatchRulesDef, actors: Dictionary, carriers: Dictionary) -> StepResult:
	var a := 1 - owner
	var att := presence[a] if eligible[a] else 0.0
	var dfn := presence[owner]
	var k_sev := rules.severed_mult if severed else 1.0
	contested = false
	_step_cell(dt, rules, actors, carriers, a)
	if progress > 0.0 and not eligible[a]:
		# Prerequisite lost mid-task: the Cell dissolved; drain at 2x decay, no Overtime.
		overtime_left = 0.0
		_attacker_was_present = false
		progress -= rules.drain_mult * decay_rate(dfn > 0.0, base_s, d_s, rules) * dt
	elif cell_state == CellState.PLANTED and cell_team == a:
		capturing_team = a
		overtime_left = 0.0
		_attacker_was_present = true
		var k_hl := 1.0 if heroes_in[a] > 0 else rules.heroless_mult
		var rate := k_hl / (base_s * d_s * k_sev)
		if att < dfn:
			rate *= rules.plant_outnumbered_mult
			contested = true
		progress += rate * dt
		if def.tier == HardpointDef.Tier.INNER and heroes_in[a] == 0:
			progress = minf(progress, rules.heroless_inner_cap)
	elif progress > 0.0:
		_overtime_or_decay(dt, decay_rate(dfn > 0.0, base_s, d_s, rules), rules)
	else:
		_attacker_was_present = false
	return _settle(rules)


func _step_cell(dt: float, rules: MatchRulesDef, actors: Dictionary, carriers: Dictionary, a: int) -> void:
	if not eligible[a]:
		if cell_state != CellState.NONE:
			_clear_cell(carriers, 0.0)
		cell_timer = 0.0
		return
	match cell_state:
		CellState.NONE:
			cell_timer -= dt
			if cell_timer <= 0.0:
				cell_timer = 0.0
				var at := def.cradle_for(a)
				if at != Vector3.INF:
					cell_state = CellState.CRADLE
					cell_team = a
					cell_pos = at
		CellState.CRADLE:
			var who := _channeler(actors, carriers, a, cell_pos, rules.cell_interact_radius_m, true, false)
			if _advance(Channel.PICKUP, who, dt) >= rules.cell_pickup_s:
				_carry(who, carriers)
		CellState.CARRIED:
			var c: TaskActor = actors.get(carrier_id)
			if c == null or not c.alive or c.mobility:
				_drop(carriers, c.position if c != null else cell_pos, rules)
				return
			cell_pos = c.position
			var planting := c.interact and c.can_channel and zone_contains(c.position)
			if _advance(Channel.PLANT, carrier_id if planting else 0, dt) >= rules.plant_channel_s:
				carriers.erase(carrier_id)
				planter_id = carrier_id
				carrier_id = 0
				cell_state = CellState.PLANTED
				cell_pos = def.position
				cells_planted += 1
				_reset_channel()
		CellState.DROPPED:
			cell_timer -= dt
			var taker := _channeler(actors, carriers, a, cell_pos, rules.cell_touch_radius_m, false, false)
			if taker != 0:
				_carry(taker, carriers)
				return
			var who := _channeler(actors, carriers, owner, cell_pos, rules.cell_touch_radius_m, false, false)
			if _advance(Channel.DISPERSE, who, dt) >= rules.cell_disperse_s or cell_timer <= 0.0:
				_clear_cell(carriers, rules.cradle_respawn_s)
		CellState.PLANTED:
			var who := _channeler(actors, carriers, owner, def.position, def.zone_radius, true, true)
			if _advance(Channel.DEFUSE, who, dt) >= rules.defuse_channel_s:
				cells_defused += 1
				_defused = true  # a defuse is a defence (§3.5 Rewards)
				_clear_cell(carriers, rules.cradle_respawn_s)


## First live hero of `team` within `radius` of `at` (holding interact and free
## to channel when `needs_interact`; inside the zone when `in_zone`). The hero
## already channelling keeps priority; carriers are skipped. 0 = none.
func _channeler(actors: Dictionary, carriers: Dictionary, team: int, at: Vector3, radius: float,
		needs_interact: bool, in_zone: bool) -> int:
	var best := 0
	for id in actors:
		var t: TaskActor = actors[id]
		if t.team != team or not t.alive or carriers.has(id):
			continue
		if needs_interact and not (t.interact and t.can_channel):
			continue
		if in_zone:
			if not zone_contains(t.position):
				continue
		elif Vector2(t.position.x - at.x, t.position.z - at.z).length() > radius or absf(t.position.y - at.y) > 3.0:
			continue
		if id == channel_hero:
			return id
		if best == 0 or id < best:
			best = id
	return best


## Runs `kind` for hero `who` (0 = nobody: reset). Returns seconds channelled.
func _advance(kind: Channel, who: int, dt: float) -> float:
	if who == 0:
		if channel == kind:
			_reset_channel()
		return 0.0
	if channel != kind or channel_hero != who:
		channel = kind
		channel_hero = who
		channel_t = 0.0
	channel_t += dt
	return channel_t


func _reset_channel() -> void:
	channel = Channel.NONE
	channel_hero = 0
	channel_t = 0.0


func _carry(who: int, carriers: Dictionary) -> void:
	cell_state = CellState.CARRIED
	carrier_id = who
	carriers[who] = self
	_reset_channel()


func _drop(carriers: Dictionary, at: Vector3, rules: MatchRulesDef) -> void:
	carriers.erase(carrier_id)
	carrier_id = 0
	cell_state = CellState.DROPPED
	cell_pos = at
	cell_timer = rules.cell_drop_life_s
	_reset_channel()


## The Cell is gone (expired, dispersed, defused, dissolved, or the node flipped).
func _clear_cell(carriers: Dictionary, refill_s: float) -> void:
	if carrier_id != 0:
		carriers.erase(carrier_id)
	cell_state = CellState.NONE
	cell_team = NEUTRAL
	carrier_id = 0
	planter_id = 0
	cell_timer = refill_s
	_reset_channel()


## Debug / tests / evidence: puts `team`'s Cell straight into `state`
## (PLANTED at the Socket, CARRIED by `hero_id`, or CRADLE).
func debug_set_cell(state: CellState, team: int, carriers: Dictionary, hero_id: int = 0, pos: Vector3 = Vector3.INF) -> void:
	_clear_cell(carriers, 0.0)
	if state == CellState.NONE:
		return
	cell_state = state
	cell_team = team
	cell_pos = def.position if pos == Vector3.INF else pos
	if state == CellState.CRADLE:
		cell_pos = def.cradle_for(team)
	elif state == CellState.CARRIED:
		carrier_id = hero_id
		carriers[hero_id] = self
	elif state == CellState.PLANTED:
		planter_id = hero_id


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
	if cell_state != CellState.NONE or carrier_id != 0:
		cell_state = CellState.NONE
		cell_team = NEUTRAL
		carrier_id = 0
		_reset_channel()
	cell_timer = 0.0
	if task == HardpointDef.TaskKind.BREACH:
		_reset_generator()
	owner = capturing_team
	progress = 0.0
	capturing_team = NEUTRAL
	contested = false
	overtime_left = 0.0
	_attacker_was_present = false
	_peak = 0.0
	ownership_changed.emit(old, owner)
	return StepResult.FLIPPED
