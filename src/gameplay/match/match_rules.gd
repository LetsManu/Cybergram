class_name MatchRules
extends RefCounted
## Server match state machine (architecture.md §2 MatchRules, §8.3 stage 9;
## match-flow-and-map.md §3.1, §3.6, F5, F6, F8; Canon C6-C11). Data-driven
## from MatchRulesDef. Each server tick, after ObjectiveSystem.step():
##   advance the match clock (dt × clock_scale) -> phase transitions by time ->
##   Uplink exposure (F6) -> Time-out resolution at time_cap_s.
## An Uplink at Integrity 0 ends the match immediately (on_uplink_destroyed).
##
##   LOAD -> DEPLOY (0:00, Mids locked) -> SKIRMISH (deploy_end_s) -> SURGE_I
##   (surge_times_s[0], D_s 0.85) -> SURGE_II -> DROUGHT -> TIME_OUT (time_cap_s)
##   -> END. Stages at or past the cap never start (M1 slice: cap 30:00, so only
##   Surge I). Time-out resolves at once (no capture overtime / freeze in M1):
##   Incursion (F8) -> Uplink-% tie-break (C9) -> draw (Sudden Death is M3).

signal phase_changed(old_phase: int, new_phase: int)
## index 0 = Surge I (Wardlings Tier II), 1 = Surge II (Tier III).
signal surge_started(index: int, task_scale: float)
signal match_ended(winner: int, reason: int)

enum Phase { LOAD, DEPLOY, SKIRMISH, SURGE_I, SURGE_II, DROUGHT, TIME_OUT, END }
enum EndReason { NONE, UPLINK_DESTROYED, INCURSION, UPLINK_DAMAGE, DRAW }

const PHASE_NAMES := ["LOADING", "DEPLOY", "SKIRMISH", "SURGE I", "SURGE II", "DROUGHT",
	"TIME-OUT", "MATCH OVER"]
const NEUTRAL: int = MapDef.TEAM_NEUTRAL

var def: MatchRulesDef
## Null on maps without hardpoints (no exposure, Incursion 0-0).
var objectives: ObjectiveSystem
## Indexed by team (0 = Concord, 1 = Syndicate); may be empty.
var uplinks: Array[UplinkSim] = []
var phase: Phase = Phase.LOAD
## Match clock in seconds (0 at Deploy).
var time_s: float = 0.0
## Debug: > 1 compresses the timeline (--match-clock).
var clock_scale: float = 1.0
## Debug: the clock starts here when Deploy begins (--debug-match-time).
var debug_start_s: float = 0.0
var winner: int = NEUTRAL
var end_reason: EndReason = EndReason.NONE
## Surges started so far (0 = none, 1 = Surge I ...).
var surges_started: int = 0
## Wardling tier hook (1 = Tier I; a Surge raises it). Read by WardlingWorld.
var wardling_tier: int = 1
## Incursion scores [Concord, Syndicate] and Uplink % [U_A, U_B] at Time-out.
var final_incursion: PackedInt32Array = PackedInt32Array([0, 0])
var final_uplink_pct: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Phase changes not yet replicated; the owner (ServerWorld) drains it every
## tick. An Uplink kill mid-tick queues END here before step() runs.
var phase_events: Array[int] = []


func _init(rules: MatchRulesDef, objective_system: ObjectiveSystem = null) -> void:
	def = rules
	objectives = objective_system
	if objectives != null:
		objectives.mid_locked = true  # Load and Deploy: Mids locked


## Builds one UplinkSim per HQ of `map` at HqDef.uplink (caller adds them to the tree).
func build_uplinks(map: MapDef) -> Array[UplinkSim]:
	uplinks.clear()
	if map == null:
		return uplinks
	for team in 2:
		var hq := map.hq(team)
		if hq == null:
			continue
		var u := UplinkSim.new()
		u.name = "Uplink%d" % team
		u.setup(team, hq.uplink, def)
		uplinks.append(u)
	return uplinks


func uplink_of(team: int) -> UplinkSim:
	for u in uplinks:
		if u.team == team:
			return u
	return null


func is_over() -> bool:
	return phase == Phase.END


## True while combat counts toward the Uplinks (not Load / End).
func is_live() -> bool:
	return phase != Phase.LOAD and phase != Phase.END


func minutes() -> float:
	return time_s / 60.0


## D_s for the current time (F5).
func task_duration_scale() -> float:
	var s := 1.0
	for i in surges_started:
		if i < def.surge_task_scale.size():
			s = def.surge_task_scale[i]
	return s


## Match time at which the next phase starts, or -1 (none before the cap).
func next_phase_time() -> float:
	match phase:
		Phase.LOAD:
			return 0.0
		Phase.DEPLOY:
			return def.deploy_end_s
		Phase.SKIRMISH, Phase.SURGE_I, Phase.SURGE_II:
			var nxt := def.time_cap_s
			if surges_started < def.surge_times_s.size():
				nxt = minf(nxt, def.surge_times_s[surges_started])
			if def.drought_time_s > time_s:
				nxt = minf(nxt, def.drought_time_s)
			return nxt
		Phase.DROUGHT:
			return def.time_cap_s
	return -1.0


## One server tick (call after ObjectiveSystem.step()).
func step(dt: float) -> void:
	if phase == Phase.END:
		return
	if phase == Phase.LOAD:
		_enter(Phase.DEPLOY)
		if objectives != null:
			objectives.mid_locked = true
		time_s = debug_start_s
		if time_s > 0.0:
			_advance_phases()
		refresh_exposure()
		return
	time_s += dt * clock_scale
	_advance_phases()
	if phase != Phase.END:
		refresh_exposure()


## Recomputes every Uplink's Exposed flag (F6).
func refresh_exposure() -> void:
	for u in uplinks:
		u.set_exposed(is_live() and exposed_now(u.team))


## F6: enemy holds >= 1 Inner of `team`, or (Drought) >= 1 Outer.
func exposed_now(team: int) -> bool:
	if objectives == null:
		return false
	var outer_too := time_s >= def.drought_time_s and def.drought_time_s < def.time_cap_s
	for h in objectives.all:
		if h.owner != 1 - team or half_of(h) != team:
			continue
		if h.def.tier == HardpointDef.Tier.INNER or (outer_too and h.def.tier == HardpointDef.Tier.OUTER):
			return true
	return false


## Which team's half a hardpoint is on (NEUTRAL for a Mid). Lane index 0 is
## nearest the Concord HQ; the Mid splits the lane.
func half_of(h: HardpointSim) -> int:
	if h.def.tier == HardpointDef.Tier.MID:
		return NEUTRAL
	var hps: Array = objectives.lanes[h.lane]
	var mid := hps.size() / 2
	for i in hps.size():
		if (hps[i] as HardpointSim).def.tier == HardpointDef.Tier.MID:
			mid = i
	return MapDef.TEAM_CONCORD if h.index < mid else MapDef.TEAM_SYNDICATE


## F8 depth of a held hardpoint for `team`: own half 0, Mid 1, enemy Outer 2, enemy Inner 3.
func depth(h: HardpointSim, team: int) -> int:
	var half := half_of(h)
	if half == NEUTRAL:
		return 1
	if half == team:
		return 0
	return 3 if h.def.tier == HardpointDef.Tier.INNER else 2


## F8 Incursion score of `team` (sum over lanes of the deepest held node).
func incursion(team: int) -> int:
	if objectives == null:
		return 0
	var total := 0
	for lane in objectives.lanes:
		var best := 0
		for h in lane:
			if (h as HardpointSim).owner == team:
				best = maxi(best, depth(h, team))
		total += best
	return total


## C9 U for `team`: damage it dealt to the enemy Uplink, % of max Integrity.
func uplink_pct_dealt(team: int) -> float:
	var enemy := uplink_of(1 - team)
	return enemy.removed_pct() if enemy != null else 0.0


## An Uplink reached 0: End now; the attacking team wins (§3.6).
func on_uplink_destroyed(team: int) -> void:
	if phase == Phase.END:
		return
	_end(1 - team, EndReason.UPLINK_DESTROYED)


## Time-out (C8/C9, slice rules): Incursion, then Uplink %, else a draw.
func resolve_time_out() -> void:
	final_incursion = PackedInt32Array([incursion(0), incursion(1)])
	final_uplink_pct = PackedFloat32Array([uplink_pct_dealt(0), uplink_pct_dealt(1)])
	if final_incursion[0] != final_incursion[1]:
		_end(0 if final_incursion[0] > final_incursion[1] else 1, EndReason.INCURSION)
		return
	var du := final_uplink_pct[0] - final_uplink_pct[1]
	if absf(du) >= def.uplink_tiebreak_min_pct:
		_end(0 if du > 0.0 else 1, EndReason.UPLINK_DAMAGE)
		return
	# Sudden Death (C10) is M3; the M1 slice rule is a draw (sudden_death_enabled is ignored).
	_end(NEUTRAL, EndReason.DRAW)


func _advance_phases() -> void:
	var guard := 8
	while guard > 0 and phase != Phase.END:
		guard -= 1
		if time_s >= def.time_cap_s:
			_enter(Phase.TIME_OUT)
			resolve_time_out()
			return
		if phase == Phase.DEPLOY and time_s >= def.deploy_end_s:
			if objectives != null:
				objectives.mid_locked = false
			_enter(Phase.SKIRMISH)
			continue
		if phase == Phase.DEPLOY:
			return
		if surges_started < def.surge_times_s.size() and surges_started < 2 \
				and time_s >= def.surge_times_s[surges_started] and def.surge_times_s[surges_started] < def.time_cap_s:
			surges_started += 1
			wardling_tier = surges_started + 1
			var s := task_duration_scale()
			if objectives != null:
				objectives.duration_scale = s
			_enter(Phase.SURGE_I if surges_started == 1 else Phase.SURGE_II)
			surge_started.emit(surges_started - 1, s)
			continue
		if phase != Phase.DROUGHT and time_s >= def.drought_time_s and def.drought_time_s < def.time_cap_s:
			_enter(Phase.DROUGHT)
			continue
		return


func _end(team: int, reason: EndReason) -> void:
	winner = team
	end_reason = reason
	for u in uplinks:
		u.set_exposed(false)
	_enter(Phase.END)
	match_ended.emit(team, reason)


func _enter(p: Phase) -> void:
	var old := phase
	phase = p
	phase_events.append(p)
	phase_changed.emit(old, p)


## "MM:SS" for a match time in seconds.
static func format_clock(seconds: float) -> String:
	var s := maxi(floori(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]
