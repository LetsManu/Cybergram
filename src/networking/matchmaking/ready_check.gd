class_name ReadyCheck
extends RefCounted
## One ready check (design "Ready check"): every human seat must accept
## within rules.ready_check_s. One decline fails it at once; at the deadline
## everyone who did not accept fails it. Bots are never part of it.
## Time is injected. The caller passes the result to
## Matchmaker.resolve_ready_check().

enum State { PENDING, ACCEPTED, FAILED }

var deadline: float
var state: State = State.PENDING
var _accepted: Dictionary = {}
var _declined: Dictionary = {}
var _ids: Array = []


func _init(account_ids: Array, now: float, window_s: float) -> void:
	_ids = account_ids.duplicate()
	deadline = now + window_s


func accept(account_id: String, now: float) -> bool:
	if tick(now) != State.PENDING or not _ids.has(account_id):
		return false
	_accepted[account_id] = true
	if _accepted.size() == _ids.size():
		state = State.ACCEPTED
	return true


func decline(account_id: String, now: float) -> bool:
	if tick(now) != State.PENDING or not _ids.has(account_id):
		return false
	_declined[account_id] = true
	state = State.FAILED
	return true


## Advances to the deadline. Returns the state.
func tick(now: float) -> State:
	if state == State.PENDING and now >= deadline:
		state = State.FAILED
	return state


## Who failed it: the decliners, or (on timeout) everyone who did not accept.
func failed_ids() -> Array:
	if state != State.FAILED:
		return []
	if not _declined.is_empty():
		return _declined.keys()
	return _ids.filter(func(id: String) -> bool: return not _accepted.has(id))


func accepted_count() -> int:
	return _accepted.size()
