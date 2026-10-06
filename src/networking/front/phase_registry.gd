class_name PhaseRegistry
extends RefCounted
## Current state per key for one PhaseMachine kind (P1). Every accepted change
## bumps the key's sequence number and is passed to `on_change`; an illegal
## change is rejected (the state stays), counted and passed to `on_illegal`
## so the caller can log it. Memory only. Time is injected.
##
## Example:
##   var reg := PhaseRegistry.new(PhaseMachine.Kind.PLAYER)
##   reg.on_change = func(key, e): push_phase(key, e)
##   reg.request(id, PhaseMachine.Player.QUEUED, now, {"queue": "normal_5v5"})

var kind: PhaseMachine.Kind
## func(key: String, entry: Dictionary) for every accepted change.
var on_change: Callable = Callable()
## func(key: String, from: int, to: int, ctx: Dictionary) for every rejected change.
var on_illegal: Callable = Callable()
## Rejected transitions since start (metrics).
var illegal_count: int = 0

## key -> {state, prev, seq, since, ctx}
var _entries: Dictionary = {}


func _init(kind_: PhaseMachine.Kind) -> void:
	kind = kind_


## Asks for `key` to move to `to`. Returns true when the key is now in `to`
## (also when it already was). `ctx` (ids, queue, ...) is kept with the entry.
func request(key: String, to: int, now: float, ctx: Dictionary = {}) -> bool:
	var e: Dictionary = _entries.get(key, {})
	var from: int = int(e.get("state", PhaseMachine.initial(kind)))
	if from == to and not e.is_empty():
		e.ctx = ctx
		return true
	if not PhaseMachine.is_legal(kind, from, to):
		illegal_count += 1
		if on_illegal.is_valid():
			on_illegal.call(key, from, to, ctx)
		return false
	var n := {"state": to, "prev": from, "seq": int(e.get("seq", 0)) + 1, "since": now, "ctx": ctx}
	_entries[key] = n
	if on_change.is_valid():
		on_change.call(key, n)
	return true


## True if `key` may move to `to` right now.
func can(key: String, to: int) -> bool:
	return PhaseMachine.is_legal(kind, state_of(key), to)


func state_of(key: String) -> int:
	return int((_entries.get(key, {}) as Dictionary).get("state", PhaseMachine.initial(kind)))


## {state, prev, seq, since, ctx} or {} for an unknown key.
func entry(key: String) -> Dictionary:
	return _entries.get(key, {})


func keys() -> Array:
	return _entries.keys()


## Forgets a key (account deleted, party dissolved, lobby closed). The next
## request starts from the initial state with sequence 1.
func forget(key: String) -> void:
	_entries.erase(key)


## Number of keys per state: {state: count}.
func counts() -> Dictionary:
	var out := {}
	for e: Dictionary in _entries.values():
		out[int(e.state)] = int(out.get(int(e.state), 0)) + 1
	return out
