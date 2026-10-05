class_name DraftSession
extends RefCounted
## 5v5 alternating draft (design "Picking (5v5)"). Turns follow
## rules.draft_order (1-2-2-2-2-1), teams alternating, `first_team`
## starting. Within a turn the next N unpicked players of that team pick, in
## any order. Heroes are unique within a team; both teams may field the same
## hero. No bans. A turn lasts rules.pick_turn_s; at the deadline every
## current picker who has not picked gets a random legal hero (seeded RNG).
## Bots pick a random legal hero as soon as their turn starts. A player who
## leaves (dodge()) aborts the draft; the caller treats it as a ready-check
## failure (Matchmaker.resolve_ready_check) plus, in ranked, the dodge
## penalty (RatingService.apply_dodge_penalty). Time is injected.

enum State { PICKING, DONE, ABORTED }
enum Err { OK, E_NOT_YOUR_TURN, E_TAKEN, E_UNKNOWN_HERO, E_CLOSED }

var teams: Array = [[], []]   # seat ids per team, in pick order
var heroes: Array[StringName] = []
var picks: Dictionary = {}    # seat id -> hero id
var auto_picked: Array = []   # seats whose hero was chosen on timeout / as bot
var state: State = State.PICKING
var dodger: String = ""
var turn: int = -1
var turn_team: int = 0
var deadline: float = 0.0
var _order: PackedInt32Array
var _turn_s: float
var _first: int
var _pickers: Array = []
var _rng := RandomNumberGenerator.new()


func _init(team_a: Array, team_b: Array, heroes_: Array[StringName], rules: MatchmakingRulesDef, now: float,
		seed_: int, first_team: int = 0) -> void:
	teams = [team_a.duplicate(), team_b.duplicate()]
	heroes = heroes_.duplicate()
	_order = rules.draft_order
	_turn_s = rules.pick_turn_s
	_first = first_team
	_rng.seed = seed_
	_next_turn(now)


## Seats allowed to pick right now.
func current_pickers() -> Array:
	return _pickers.filter(func(s: String) -> bool: return not picks.has(s))


## Heroes `team` may still pick.
func legal_heroes(team: int) -> Array[StringName]:
	var taken := {}
	for s in teams[team]:
		if picks.has(s):
			taken[picks[s]] = true
	var out: Array[StringName] = []
	for h in heroes:
		if not taken.has(h):
			out.append(h)
	return out


func team_of(seat: String) -> int:
	return 0 if teams[0].has(seat) else (1 if teams[1].has(seat) else -1)


func pick(seat: String, hero: StringName, now: float) -> Err:
	if tick(now) != State.PICKING:
		return Err.E_CLOSED
	if not current_pickers().has(seat):
		return Err.E_NOT_YOUR_TURN
	if not heroes.has(hero):
		return Err.E_UNKNOWN_HERO
	if not legal_heroes(turn_team).has(hero):
		return Err.E_TAKEN
	picks[seat] = hero
	if current_pickers().is_empty():
		_next_turn(now)
	return Err.OK


## Advances timeouts (possibly several turns). Returns the state.
func tick(now: float) -> State:
	while state == State.PICKING and now >= deadline:
		for s in current_pickers():
			_auto(s)
		_next_turn(deadline)
	return state


## A seat left during the draft: everything stops.
func dodge(seat: String) -> void:
	if state == State.PICKING and team_of(seat) >= 0:
		state = State.ABORTED
		dodger = seat


func _auto(seat: String) -> void:
	var legal := legal_heroes(team_of(seat))
	if legal.is_empty():
		return
	picks[seat] = legal[_rng.randi_range(0, legal.size() - 1)]
	auto_picked.append(seat)


func _next_turn(now: float) -> void:
	while true:
		turn += 1
		if turn >= _order.size():
			state = State.DONE
			_pickers = []
			return
		turn_team = (_first + turn) % 2
		_pickers = teams[turn_team].filter(func(s: String) -> bool: return not picks.has(s)).slice(0, _order[turn])
		deadline = now + _turn_s
		for s in _pickers:
			if MatchmakingRulesDef.is_bot(s):
				_auto(s)
		if not current_pickers().is_empty():
			return
