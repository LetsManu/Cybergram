class_name DraftSession
extends RefCounted
## 5v5 champ select (design "Picking (5v5)", P3 formats in PROGRESS.md).
## Draft: turns follow rules.draft_order (1-2-2-2-2-1), teams alternating,
## `first_team` starting; within a turn the next N unpicked players of that
## team pick, in any order. Blind (opts.blind): one turn, everyone picks at
## once (rules.blind_pick_s); the caller hides enemy picks.
## Heroes are unique within a team; both teams may field the same hero.
## Hover (P3): any unlocked player may declare a hero at any time while
## picking; allies see it and cannot hover or lock it. A pick is the lock.
## At a turn's deadline each current picker who has not locked gets: the
## hovered hero (auto-lock), else, with opts.timeout_dodges (Ranked), the
## draft aborts with that player as dodger (timed_out = true), else a random
## legal hero (seeded RNG). Bots lock a random legal hero when their turn starts.
## Bans (rules.bans_per_team > 0): before the picks the first N humans of each
## team ban at once (hover + lock; hidden from the enemy) within rules.ban_s;
## a hovered ban locks at the deadline, no hover = no ban. Banned heroes are
## out for both teams; the first pick turn starts after rules.ban_reveal_s.
## Finalize (rules.finalize_s > 0): after the last lock, teammates who both
## locked may trade heroes (request + accept within swap_request_ttl_s) until
## the last rules.finalize_lock_s seconds. A player who leaves (dodge())
## aborts the draft; the caller treats it as a ready-check failure plus the
## dodge penalty. Time is injected.

enum State { PICKING, DONE, ABORTED, BANNING, FINALIZING }
enum Err { OK, E_NOT_YOUR_TURN, E_TAKEN, E_UNKNOWN_HERO, E_CLOSED, E_BANNED, E_NOT_TEAMMATE, E_NO_REQUEST }
## turn_team while everyone picks at once (blind).
const BOTH := 2

var teams: Array = [[], []]   # seat ids per team, in pick order
var heroes: Array[StringName] = []
var picks: Dictionary = {}    # seat id -> hero id
var auto_picked: Array = []   # seats whose hero was chosen on timeout / as bot
var state: State = State.PICKING
var dodger: String = ""
## True when the abort came from a pick timeout with nothing hovered (opts.timeout_dodges).
var timed_out: bool = false
## Declared heroes of unlocked seats (seat -> hero). Allies see them.
var hovers: Dictionary = {}
## Seats whose hover was locked at the deadline.
var hover_locked: Array = []
## Ban phase: seat -> hovered ban, seat -> locked ban, and the final bans.
var ban_hovers: Dictionary = {}
var ban_locks: Dictionary = {}
var bans: Array[StringName] = []
var blind: bool = false
var timeout_dodges: bool = false
var turn: int = -1
var turn_team: int = 0
var deadline: float = 0.0
var _order: PackedInt32Array
var _turn_s: float
var _first: int
var _pickers: Array = []
var _banners: Array = []
var _rng := RandomNumberGenerator.new()
var _ban_s: float = 0.0
var _reveal_s: float = 0.0
var _finalize_s: float = 0.0
var _finalize_lock_s: float = 0.0
var _trade_ttl: float = 10.0
var _trades: Dictionary = {}  # "from>to" -> expires
## End of trades in FINALIZING (deadline - finalize_lock_s).
var trades_until: float = 0.0


## `opts`: {blind: bool, timeout_dodges: bool} (P3; both false = the classic draft).
func _init(team_a: Array, team_b: Array, heroes_: Array[StringName], rules: MatchmakingRulesDef, now: float,
		seed_: int, first_team: int = 0, opts: Dictionary = {}) -> void:
	teams = [team_a.duplicate(), team_b.duplicate()]
	heroes = heroes_.duplicate()
	blind = bool(opts.get("blind", false))
	timeout_dodges = bool(opts.get("timeout_dodges", false))
	_order = PackedInt32Array([maxi(team_a.size(), team_b.size())]) if blind else rules.draft_order
	_turn_s = rules.blind_pick_s if blind else rules.pick_turn_s
	_first = first_team
	_ban_s = rules.ban_s
	_reveal_s = rules.ban_reveal_s
	_finalize_s = rules.finalize_s
	_finalize_lock_s = minf(rules.finalize_lock_s, rules.finalize_s)
	_trade_ttl = rules.swap_request_ttl_s
	_rng.seed = seed_
	var n := mini(rules.bans_per_team, maxi(0, (heroes.size() - 8) / 2)) if rules.bans_per_team > 0 else 0
	if n > 0:
		for t in 2:
			_banners.append_array(teams[t].filter(func(x: String) -> bool:
				return not MatchmakingRulesDef.is_bot(x)).slice(0, n))
	if not _banners.is_empty():
		state = State.BANNING
		deadline = now + _ban_s
	else:
		_next_turn(now)


## Seats allowed to pick right now.
func current_pickers() -> Array:
	if state != State.PICKING:
		return []
	return _pickers.filter(func(s: String) -> bool: return not picks.has(s))


## Seats that ban in the ban phase (and have not locked yet).
func current_banners() -> Array:
	if state != State.BANNING:
		return []
	return _banners.filter(func(s: String) -> bool: return not ban_locks.has(s))


## Heroes `team` may still pick: not banned, not locked by the team, not
## hovered by a teammate other than `seat` ("" = every hover counts).
func legal_heroes(team: int, seat: String = "") -> Array[StringName]:
	var taken := {}
	for s in teams[team]:
		if picks.has(s):
			taken[picks[s]] = true
		elif hovers.has(s) and s != seat and seat != "":
			taken[hovers[s]] = true
	var out: Array[StringName] = []
	for h in heroes:
		if not taken.has(h) and not bans.has(h):
			out.append(h)
	return out


## Declare `hero` (or &"" to clear). Picks: any unlocked seat, any time while
## picking. Bans: a banner before locking. Allies see hovers.
func hover(seat: String, hero: StringName, now: float) -> Err:
	var st := tick(now)
	var team := team_of(seat)
	if team < 0:
		return Err.E_NOT_YOUR_TURN
	if st == State.BANNING:
		if not current_banners().has(seat):
			return Err.E_NOT_YOUR_TURN
		if hero == &"":
			ban_hovers.erase(seat)
			return Err.OK
		if not heroes.has(hero):
			return Err.E_UNKNOWN_HERO
		ban_hovers[seat] = hero
		return Err.OK
	if st != State.PICKING:
		return Err.E_CLOSED
	if picks.has(seat):
		return Err.E_NOT_YOUR_TURN
	if hero == &"":
		hovers.erase(seat)
		return Err.OK
	if not heroes.has(hero):
		return Err.E_UNKNOWN_HERO
	if bans.has(hero):
		return Err.E_BANNED
	if not legal_heroes(team, seat).has(hero):
		return Err.E_TAKEN
	hovers[seat] = hero
	return Err.OK


## Lock a ban (ban phase only).
func ban(seat: String, hero: StringName, now: float) -> Err:
	if tick(now) != State.BANNING:
		return Err.E_CLOSED
	if not current_banners().has(seat):
		return Err.E_NOT_YOUR_TURN
	if not heroes.has(hero):
		return Err.E_UNKNOWN_HERO
	ban_locks[seat] = hero
	ban_hovers.erase(seat)
	if current_banners().is_empty():
		_end_bans(now)
	return Err.OK


## Finalize: `from` offers `to` (a teammate, both locked) to trade heroes.
func request_trade(from: String, to: String, now: float) -> Err:
	var e := _trade_check(from, to, now)
	if e == Err.OK:
		_trades["%s>%s" % [from, to]] = now + _trade_ttl
	return e


## Finalize: `me` accepts the trade offered by `from`; the heroes change places.
func accept_trade(me: String, from: String, now: float) -> Err:
	var e := _trade_check(me, from, now)
	if e != Err.OK:
		return e
	var k := "%s>%s" % [from, me]
	if now > float(_trades.get(k, -1.0)):
		_trades.erase(k)
		return Err.E_NO_REQUEST
	var h: StringName = picks[me]
	picks[me] = picks[from]
	picks[from] = h
	for key in _trades.keys():
		if key.begins_with(me + ">") or key.begins_with(from + ">") or key.ends_with(">" + me) or key.ends_with(">" + from):
			_trades.erase(key)
	return Err.OK


## Seats that offered `to` a trade right now.
func trade_requests_to(to: String, now: float) -> Array:
	var out: Array = []
	for k: String in _trades:
		var parts := k.split(">")
		if parts[1] == to and now <= float(_trades[k]):
			out.append(parts[0])
	return out


func _trade_check(a: String, b: String, now: float) -> Err:
	if tick(now) != State.FINALIZING or now >= trades_until:
		return Err.E_CLOSED
	if a == b or team_of(a) < 0 or team_of(a) != team_of(b):
		return Err.E_NOT_TEAMMATE
	if not picks.has(a) or not picks.has(b) or MatchmakingRulesDef.is_bot(a) or MatchmakingRulesDef.is_bot(b):
		return Err.E_NOT_TEAMMATE
	return Err.OK


func team_of(seat: String) -> int:
	return 0 if teams[0].has(seat) else (1 if teams[1].has(seat) else -1)


func pick(seat: String, hero: StringName, now: float) -> Err:
	if tick(now) != State.PICKING:
		return Err.E_CLOSED
	if not current_pickers().has(seat):
		return Err.E_NOT_YOUR_TURN
	if not heroes.has(hero):
		return Err.E_UNKNOWN_HERO
	if bans.has(hero):
		return Err.E_BANNED
	if not legal_heroes(team_of(seat), seat).has(hero):
		return Err.E_TAKEN
	picks[seat] = hero
	hovers.erase(seat)
	if current_pickers().is_empty():
		_next_turn(now)
	return Err.OK


## Advances timeouts (possibly several turns). Returns the state.
func tick(now: float) -> State:
	if state == State.BANNING and now >= deadline:
		for s in current_banners():
			if ban_hovers.has(s):
				ban_locks[s] = ban_hovers[s]  # hovered ban locks; no hover = no ban
		_end_bans(deadline)
	while state == State.PICKING and now >= deadline:
		for s in current_pickers():
			if hovers.has(s) and legal_heroes(team_of(s), s).has(hovers[s]):
				picks[s] = hovers[s]
				hovers.erase(s)
				hover_locked.append(s)
			elif timeout_dodges and not MatchmakingRulesDef.is_bot(s):
				state = State.ABORTED
				dodger = s
				timed_out = true
				return state
			else:
				_auto(s)
		_next_turn(deadline)
	if state == State.FINALIZING and now >= deadline:
		state = State.DONE
	return state


## A seat left during the draft: everything stops.
func dodge(seat: String) -> void:
	if state in [State.PICKING, State.BANNING, State.FINALIZING] and team_of(seat) >= 0:
		state = State.ABORTED
		dodger = seat


func _end_bans(now: float) -> void:
	for s in _banners:
		var h: StringName = ban_locks.get(s, &"")
		if h != &"" and not bans.has(h):
			bans.append(h)
	ban_hovers.clear()
	state = State.PICKING
	_next_turn(now + _reveal_s)  # the first turn's clock starts after the reveal


func _auto(seat: String) -> void:
	var legal := legal_heroes(team_of(seat), seat)
	if legal.is_empty():
		return
	picks[seat] = legal[_rng.randi_range(0, legal.size() - 1)]
	auto_picked.append(seat)


func _next_turn(now: float) -> void:
	while true:
		turn += 1
		if turn >= _order.size():
			_pickers = []
			# A draft order shorter than the teams (bad data): nobody plays heroless.
			for t in 2:
				for seat in teams[t]:
					if not picks.has(seat):
						_auto(seat)
			if _finalize_s > 0.0:
				state = State.FINALIZING
				deadline = now + _finalize_s
				trades_until = deadline - _finalize_lock_s
			else:
				state = State.DONE
			return
		if blind:
			turn_team = BOTH
			_pickers = teams[0] + teams[1]
		else:
			turn_team = (_first + turn) % 2
			_pickers = teams[turn_team].filter(func(s: String) -> bool: return not picks.has(s)).slice(0, _order[turn])
		deadline = now + _turn_s
		for s in _pickers:
			if MatchmakingRulesDef.is_bot(s):
				_auto(s)
		if not current_pickers().is_empty():
			return
