class_name RemakeVote
extends RefCounted
## Early remake vote for one team (design "Fair play").
## - Trigger: a player of this team never connected or left (mark_absent()).
## - When: until rules.remake_window_s after the match started (~3 min).
## - Who votes: the team's connected human players (absent seats and bots
##   never vote). The starter votes yes.
## - Threshold: ALL present (owner decision 2026-10-05): every connected
##   human teammate, as counted when the vote starts, must vote yes. One
##   "no" fails it.
## - The vote stays open rules.remake_vote_s; it fails when it times out or
##   when enough "no" votes make the threshold unreachable.
## - One vote per absence: after a failed vote, a new one needs a new absent
##   player (no vote spam).
## - PASSED means the match is void: RatingService.apply_result(voided=true).
##   The seats absent when it passed (absent_at_pass) caused the remake and
##   each gets a LEAVE strike (strike_absent(), escalating ranked lockout,
##   owner decision 2026-10-05). Bots are never struck.
## Time is injected.

enum State { IDLE, OPEN, PASSED, FAILED }
enum Err { OK, E_TOO_LATE, E_NO_TRIGGER, E_NOT_VOTER, E_ACTIVE, E_CLOSED, E_ALREADY_VOTED }

var state: State = State.IDLE
var team: Array = []
var match_start: float
var deadline: float = 0.0
var _rules: MatchmakingRulesDef
var _absent: Dictionary = {}
var _votes: Dictionary = {}       # seat -> bool
var _voters: Array = []           # frozen at start
var _absences_used: int = 0
var _absences_seen: int = 0
## Human seats absent at the moment the vote passed (set once, on PASSED).
var absent_at_pass: Array = []


func _init(team_: Array, match_start_: float, rules: MatchmakingRulesDef) -> void:
	team = team_.duplicate()
	match_start = match_start_
	_rules = rules


## A seat never connected or left. Counts as a new trigger.
func mark_absent(seat: String) -> void:
	if team.has(seat) and not _absent.has(seat):
		_absent[seat] = true
		_absences_seen += 1


## A seat (re)connected.
func mark_present(seat: String) -> void:
	_absent.erase(seat)


func eligible_voters() -> Array:
	return team.filter(func(s: String) -> bool: return not _absent.has(s) and not MatchmakingRulesDef.is_bot(s))


## Yes votes needed for the open (or a new) vote: all present voters.
func needed() -> int:
	return maxi(1, _voters.size() if state == State.OPEN else eligible_voters().size())


## Gives every account in `absent_ids` a LEAVE strike (bots skipped).
## Returns {account id: lockout seconds}. The front calls it with the match
## result's remake_absent (= absent_at_pass of the passed vote).
static func strike_absent(lockouts: LockoutTracker, absent_ids: Array, now: float) -> Dictionary:
	var out := {}
	for id in absent_ids:
		if not MatchmakingRulesDef.is_bot(String(id)):
			out[id] = lockouts.record(String(id), LockoutTracker.Kind.LEAVE, now)
	return out


func start(seat: String, now: float) -> Err:
	tick(now)
	if state == State.OPEN:
		return Err.E_ACTIVE
	if state == State.PASSED:
		return Err.E_CLOSED
	if now - match_start > _rules.remake_window_s:
		return Err.E_TOO_LATE
	if _absent.is_empty() or _absences_seen <= _absences_used:
		return Err.E_NO_TRIGGER
	if not eligible_voters().has(seat):
		return Err.E_NOT_VOTER
	_absences_used = _absences_seen
	_voters = eligible_voters()
	_votes = {}
	state = State.OPEN
	deadline = now + _rules.remake_vote_s
	return vote(seat, true, now)


func vote(seat: String, yes: bool, now: float) -> Err:
	if tick(now) != State.OPEN:
		return Err.E_CLOSED
	if not _voters.has(seat):
		return Err.E_NOT_VOTER
	if _votes.has(seat):
		return Err.E_ALREADY_VOTED
	_votes[seat] = yes
	_settle()
	return Err.OK


func yes_count() -> int:
	return _votes.values().count(true)


func tick(now: float) -> State:
	if state == State.OPEN and now >= deadline:
		state = State.FAILED
	return state


func _settle() -> void:
	var yes := yes_count()
	var no := _votes.size() - yes
	if yes >= needed():
		state = State.PASSED
		absent_at_pass = team.filter(func(x: String) -> bool:
			return _absent.has(x) and not MatchmakingRulesDef.is_bot(x))
	elif _voters.size() - no < needed():
		state = State.FAILED
