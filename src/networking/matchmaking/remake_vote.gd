class_name RemakeVote
extends RefCounted
## Early remake vote for one team (design "Fair play").
## - Trigger: a player of this team never connected or left (mark_absent()).
## - When: until rules.remake_window_s after the match started (~3 min).
## - Who votes: the team's connected human players (absent seats and bots
##   never vote). The starter votes yes.
## - Threshold: ceil(rules.remake_vote_fraction * eligible voters) yes votes
##   (default 0.8: 4 of 4, 3 of 3, 2 of 2 left in practice).
## - The vote stays open rules.remake_vote_s; it fails when it times out or
##   when enough "no" votes make the threshold unreachable.
## - One vote per absence: after a failed vote, a new one needs a new absent
##   player (no vote spam).
## - PASSED means the match is void: RatingService.apply_result(voided=true).
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


## Yes votes needed for the open (or a new) vote.
func needed() -> int:
	var n := _voters.size() if state == State.OPEN else eligible_voters().size()
	return maxi(1, ceili(_rules.remake_vote_fraction * n - 0.000001))


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
	elif _voters.size() - no < needed():
		state = State.FAILED
