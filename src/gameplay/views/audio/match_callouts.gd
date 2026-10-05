class_name MatchCallouts
extends RefCounted
## W21-A1: derives announcer lines from replicated match events (pure logic).
## No protocol data exists for streaks, so they are tracked here from the KILL
## events every client receives (a client that joins late misses earlier kills).
##   first_blood         first hero-on-hero kill of the match
##   double / triple     the same killer again within multikill_window_s
##   shutdown            the victim had >= shutdown_streak kills since its last death
##   hardpoint_captured / hardpoint_lost   own team gained / lost a hardpoint
##   uplink_under_attack own Uplink integrity dropped
##   sudden_death        phase SUDDEN_DEATH
##   victory / defeat    match end vs own team
##   thirty_seconds      DEPLOY with countdown_line_s left before Skirmish

var def: AnnouncerDef
var _first_blood_done: bool = false
var _streak: Dictionary = {}  # net id -> kills since last death
var _multi: Dictionary = {}  # killer net id -> [count, last kill time]
var _uplink_prev: float = -1.0
var _countdown_done: bool = false


func _init(announcer_def: AnnouncerDef = null) -> void:
	def = announcer_def if announcer_def != null else AnnouncerDef.new()


## A kill. `killer_is_hero` false for Wardlings / structures / the ring (no streaks).
func on_kill(victim: int, killer: int, killer_is_hero: bool, now: float) -> Array[StringName]:
	var out: Array[StringName] = []
	var victim_streak := int(_streak.get(victim, 0))
	_streak[victim] = 0
	_multi.erase(victim)
	if not killer_is_hero or killer == victim or killer == 0:
		return out
	if not _first_blood_done:
		_first_blood_done = true
		out.append(&"first_blood")
	_streak[killer] = int(_streak.get(killer, 0)) + 1
	var m: Array = _multi.get(killer, [0, -1000.0])
	var count: int = int(m[0]) + 1 if now - float(m[1]) <= def.multikill_window_s else 1
	_multi[killer] = [count, now]
	if count == 2:
		out.append(&"double_kill")
	elif count >= 3:
		out.append(&"triple_kill")
	if victim_streak >= def.shutdown_streak:
		out.append(&"shutdown")
	return out


func on_hardpoint(old_team: int, new_team: int, own_team: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if new_team == own_team and old_team != own_team:
		out.append(&"hardpoint_captured")
	elif old_team == own_team and new_team != own_team:
		out.append(&"hardpoint_lost")
	return out


## Own Uplink integrity sample (any rate); a drop larger than uplink_drop_frac of max fires.
func on_uplink(integrity: float, max_integrity: float) -> Array[StringName]:
	var out: Array[StringName] = []
	# _uplink_prev is the reference level: it follows heals up, and accumulated
	# chip damage past the threshold fires once and re-arms from the new level.
	if _uplink_prev < 0.0 or integrity > _uplink_prev:
		_uplink_prev = integrity
	elif max_integrity > 0.0 and _uplink_prev - integrity > def.uplink_drop_frac * max_integrity:
		out.append(&"uplink_under_attack")
		_uplink_prev = integrity
	return out


func on_phase(phase: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if phase == MatchRules.Phase.SUDDEN_DEATH:
		out.append(&"sudden_death")
	return out


func on_match_end(winner: int, own_team: int) -> Array[StringName]:
	var out: Array[StringName] = []
	out.append(&"victory" if winner == own_team else &"defeat")
	return out


## Match clock sample: `left_s` seconds left in DEPLOY (the "30 s to start" line, once).
func on_clock(phase: int, left_s: float) -> Array[StringName]:
	var out: Array[StringName] = []
	if phase == MatchRules.Phase.DEPLOY and not _countdown_done and left_s <= def.countdown_line_s and left_s > 0.0:
		_countdown_done = true
		out.append(&"thirty_seconds")
	return out
