class_name AllRandomSession
extends RefCounted
## 3v3 All Random hero phase (design "3v3 All Random", ARAM style).
## - Every seat is dealt a random hero, unique within its team (both teams
##   may hold the same hero).
## - Reroll: the seat's hero goes onto the team's shared bench and a new
##   random hero is dealt from the heroes the team neither holds nor has on
##   the bench. Each human seat has rules.rerolls_per_player rerolls; bots
##   never reroll. When nothing is left to deal the reroll fails (E_EMPTY)
##   and is not used up.
## - Bench: any teammate may take a bench hero; their own hero takes its
##   place on the bench.
## - Swap: a seat asks a teammate (request_swap); the teammate accepts
##   within rules.swap_request_ttl_s and the two heroes trade places.
## - At rules.all_random_s the phase locks. Time is injected; RNG seeded.

enum State { OPEN, LOCKED }
enum Err { OK, E_CLOSED, E_NOT_SEAT, E_NO_REROLLS, E_EMPTY, E_NOT_ON_BENCH, E_NOT_TEAMMATE, E_NO_REQUEST }

var teams: Array = [[], []]
var heroes: Array[StringName] = []
var hero_of: Dictionary = {}       # seat -> hero
var rerolls_left: Dictionary = {}  # seat -> int
var bench: Array = [[], []]        # per team: Array[StringName]
var state: State = State.OPEN
var deadline: float
var _swap_ttl: float
var _requests: Dictionary = {}     # "from>to" -> expires
var _rng := RandomNumberGenerator.new()


func _init(team_a: Array, team_b: Array, heroes_: Array[StringName], rules: MatchmakingRulesDef, now: float,
		seed_: int) -> void:
	teams = [team_a.duplicate(), team_b.duplicate()]
	heroes = heroes_.duplicate()
	deadline = now + rules.all_random_s
	_swap_ttl = rules.swap_request_ttl_s
	_rng.seed = seed_
	for t in 2:
		for s in teams[t]:
			var pool := drawable(t)
			hero_of[s] = pool[_rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else &""
			rerolls_left[s] = 0 if MatchmakingRulesDef.is_bot(s) else rules.rerolls_per_player


func team_of(seat: String) -> int:
	return 0 if teams[0].has(seat) else (1 if teams[1].has(seat) else -1)


## Heroes the team could still be dealt (not held, not benched).
func drawable(team: int) -> Array[StringName]:
	var used := {}
	for s in teams[team]:
		if hero_of.has(s):
			used[hero_of[s]] = true
	for h in bench[team]:
		used[h] = true
	var out: Array[StringName] = []
	for h in heroes:
		if not used.has(h):
			out.append(h)
	return out


func reroll(seat: String, now: float) -> Err:
	var t := _check(seat, now)
	if t < 0:
		return Err.E_CLOSED if t == -2 else Err.E_NOT_SEAT
	if int(rerolls_left[seat]) <= 0:
		return Err.E_NO_REROLLS
	var pool := drawable(t)
	if pool.is_empty():
		return Err.E_EMPTY
	(bench[t] as Array).append(hero_of[seat])
	hero_of[seat] = pool[_rng.randi_range(0, pool.size() - 1)]
	rerolls_left[seat] = int(rerolls_left[seat]) - 1
	return Err.OK


func take_from_bench(seat: String, hero: StringName, now: float) -> Err:
	var t := _check(seat, now)
	if t < 0:
		return Err.E_CLOSED if t == -2 else Err.E_NOT_SEAT
	var b: Array = bench[t]
	var i := b.find(hero)
	if i < 0:
		return Err.E_NOT_ON_BENCH
	b[i] = hero_of[seat]
	hero_of[seat] = hero
	return Err.OK


func request_swap(from: String, to: String, now: float) -> Err:
	var t := _check(from, now)
	if t < 0:
		return Err.E_CLOSED if t == -2 else Err.E_NOT_SEAT
	if from == to or team_of(to) != t or MatchmakingRulesDef.is_bot(to):
		return Err.E_NOT_TEAMMATE
	_requests["%s>%s" % [from, to]] = now + _swap_ttl
	return Err.OK


## `me` accepts the swap `from` asked for: the two heroes trade places.
func accept_swap(me: String, from: String, now: float) -> Err:
	var t := _check(me, now)
	if t < 0:
		return Err.E_CLOSED if t == -2 else Err.E_NOT_SEAT
	var key := "%s>%s" % [from, me]
	if not _requests.has(key) or now > float(_requests[key]):
		_requests.erase(key)
		return Err.E_NO_REQUEST
	_requests.erase(key)
	var h: StringName = hero_of[me]
	hero_of[me] = hero_of[from]
	hero_of[from] = h
	return Err.OK


func tick(now: float) -> State:
	if state == State.OPEN and now >= deadline:
		state = State.LOCKED
	return state


## Team index, -1 not a seat, -2 closed.
func _check(seat: String, now: float) -> int:
	if tick(now) != State.OPEN:
		return -2
	return team_of(seat)
