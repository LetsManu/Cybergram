class_name MatchmakingFakeClient
extends RefCounted
## W17B-UI: an offline stand-in for the matchmaking client, so the screens
## can be built, tested and screenshotted without a server. It runs the real
## phase-A rules (DraftSession, AllRandomSession, MatchmakingRulesDef) on
## injected time and fills the other seats with scripted players.
## Every screen talks to a client only through the signals and methods below
## (duck typed), so the network client of W17B-SRV drops in for this one.
##
## Signals carry plain Dictionaries (field lists on each signal). Times are
## seconds REMAINING when the message was sent; screens count down locally.
##
## Example (tests):
##   var c := MatchmakingFakeClient.new()
##   c.join_queue(MmView.Q_NORMAL, [&"north", &"center"])
##   c.step(c.found_after_s)            # -> match_found
##   c.reply_ready(true); c.step(1.0)   # -> ready_result {outcome: &"go"}, pick_state

## {state: &"idle"|&"queued"|&"locked", queue, waited_s, estimate_s,
## in_queue, locked_s, err: String key or ""}
signal queue_changed(status: Dictionary)
## {match_id, queue, deadline_s, humans, accepted, me_accepted}
signal match_found(info: Dictionary)
## {outcome: &"go"|&"requeued"|&"locked", locked_s, reason key}
signal ready_result(result: Dictionary)
## Draft: {mode: &"draft", queue, ranked, me, my_team, turn, turn_team,
## order, deadline_s, seats: [{id, name, team, lane, hero, bot, auto,
## picking}]}. All random: {mode: &"all_random", me, my_team, open,
## deadline_s, rerolls_left, bench, seats, swap_requests: [{from, name,
## hero}], outgoing: [ids]}
signal pick_state(state: Dictionary)
## {match_id, host, port, ticket, queue, map}
signal match_assigned(info: Dictionary)
## The match link dropped (the match is still running: offer reconnect).
signal connection_lost()
## {eligible, open, yes, no, needed, deadline_s, voted, outcome: &""|&"passed"|&"failed"}
signal remake_state(state: Dictionary)
## {match_id, queue, won, voided, duration_s, stats: {kills, deaths, assists,
## damage, healing, objective}, rating: {} | {before, after, delta, medal_before,
## medal_after, progress, calibrating, games_played, games_needed},
## players: [{id, name, team, hero, kills, deaths, assists, me, bot}]}
signal post_match(result: Dictionary)
## {tracks: {ranked: {calibrating, games_left, rating, medal, progress},
## normal: {games}, all_random: {games}}, history: [{queue, won, hero,
## kills, deaths, assists, delta, ago_s}], calibration_games}
signal profile_received(profile: Dictionary)
## {members: [{id, name, leader, me, rating_label}], leader}
signal party_changed(party: Dictionary)
## {host, me, map, mode (&"custom" | &"all_random"), bots (bool), team_size,
## maps: [], modes: [], members: [{id, name, team, bot}], invited: [], starting}
signal custom_changed(lobby: Dictionary)
## A request failed: a HUD_MM_ERR_* key.
signal failed(key: String)
## P1: the server-side player state, as MmClientAdapter.phase_changed
## (derived here from the fake's own signals, for the status bar).
signal phase_changed(state: Dictionary)
## P2: party chat (same interface as MmClientAdapter).
signal party_chat_changed()
## v20: loading percent per seat (pick-state seat order; bots 100).
signal load_progress(loads: Array)
## v20: the hero select team chat changed.
signal select_chat_changed()
## Answers to honour / report: {op: &"honour"|&"report", target, ok}.
signal feedback_result(result: Dictionary)
## W20-WEB public leaderboard opt-in: {public: bool, available: bool}
## (available false = a guest or a server without accounts).
signal leaderboard_changed(state: Dictionary)

const ME := "me"
const NAMES: Array[String] = ["Kestrel", "Nyx", "Orrin", "Talia", "Brick", "Mara", "Juno", "Vale", "Quill", "Rook"]

var rules: MatchmakingRulesDef
var now: float = 0.0
## Seconds in queue until a match is "found".
var found_after_s: float = 4.0
## Scripted players accept / pick after this long.
var think_s: float = 2.0
var queue: StringName = &""
var lanes: Array = [&"fill"]
var phase: StringName = &"idle"  # idle queued found pick assigned match post
var locked_until: float = 0.0
var my_ranked: Dictionary = {"calibrating": false, "games_left": 0, "rating": 1563,
	"medal": {"band": 3, "name": "Gold", "division": 2, "label": "Gold II"}}
var party: Array = []  # extra party members (names)
## W20-WEB: the public leaderboard opt-in (default off) and whether this
## player can opt in at all (accounts only).
var leaderboard_public: bool = false
var leaderboard_available: bool = true
## Last messages sent (tests read these).
var sent: Array = []

var _queued_at: float = 0.0
var _found: Dictionary = {}
var _me_accepted: bool = false
var _draft: DraftSession
var _aram: AllRandomSession
var _seat_names: Dictionary = {}
var _seat_lanes: Dictionary = {}
var _turn_seen: int = -1
var _turn_at: float = 0.0
var _incoming: Array = []  # [{from, at}]
var _outgoing: Array = []
var _match_id: int = 1000
var _remake: Dictionary = {}
var _custom: Dictionary = {}
var _my_hero: StringName = &""
## v20 loading: [{id, bot}] of the last pick state, and the percent per seat.
var _load_seats: Array = []
var loads: Array = []
## Seconds the fake players need to load (seat i takes load_s * (1 + i % 3) / 2).
var load_s: float = 4.0
var _assigned_at: float = 0.0


var _phase_seq: int = 0
var _phase_now: int = PhaseMachine.Player.IDLE


func _init(rules_: MatchmakingRulesDef = null) -> void:
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()
	var P := PhaseMachine.Player
	queue_changed.connect(func(st: Dictionary) -> void:
		_emit_phase(P.QUEUED if st.state == &"queued" else P.IDLE, st))
	match_found.connect(func(_i: Dictionary) -> void: _emit_phase(P.READY_CHECK))
	ready_result.connect(func(r: Dictionary) -> void:
		if r.outcome == &"go":
			_emit_phase(P.CHAMP_SELECT))
	match_assigned.connect(func(_i: Dictionary) -> void: _emit_phase(P.LOADING))
	connection_lost.connect(func() -> void: _emit_phase(P.RECONNECTING))
	post_match.connect(func(_r: Dictionary) -> void: _emit_phase(P.POST_GAME))


func _emit_phase(ph: int, st: Dictionary = {}) -> void:
	_phase_seq += 1
	var prev := _phase_now
	_phase_now = ph
	phase_changed.emit({"epoch": 1, "seq": _phase_seq, "phase": ph, "prev": prev, "snap": 0,
		"queue": 0, "party_size": 3, "leader": 1, "waited": int(st.get("waited_s", 0.0)),
		"estimate": int(st.get("estimate_s", 0.0)), "locked": ceili(float(st.get("locked_s", 0.0))), "match": "",
		"party": ""})


# --- requests (the client API the screens call) -------------------------------

func join_queue(queue_id: StringName, prefs: Array) -> void:
	sent.append({"op": &"queue_join", "queue": queue_id, "lanes": prefs})
	if now < locked_until:
		queue_changed.emit(_status(&"locked"))
		return
	queue = queue_id
	lanes = prefs.duplicate()
	phase = &"queued"
	_queued_at = now
	queue_changed.emit(_status(&"queued"))


func leave_queue() -> void:
	sent.append({"op": &"queue_leave"})
	if phase == &"queued" or phase == &"found":
		phase = &"idle"
		queue_changed.emit(_status(&"idle"))


func reply_ready(accept: bool) -> void:
	sent.append({"op": &"ready", "accept": accept})
	if phase != &"found":
		return
	if not accept:
		_fail_ready(&"locked")
		return
	_me_accepted = true
	_found.me_accepted = true
	_found.accepted = mini(int(_found.accepted) + 1, int(_found.humans))
	match_found.emit(_found_info())


func pick(hero: StringName) -> void:
	sent.append({"op": &"pick", "hero": hero})
	if _draft != null:
		_draft.pick(ME, hero, now)
		_emit_pick()


func reroll() -> void:
	sent.append({"op": &"reroll"})
	if _aram != null:
		_aram.reroll(ME, now)
		_emit_pick()


func take_bench(hero: StringName) -> void:
	sent.append({"op": &"take_bench", "hero": hero})
	if _aram != null:
		_aram.take_from_bench(ME, hero, now)
		_emit_pick()


func request_swap(seat_id: String) -> void:
	sent.append({"op": &"request_swap", "seat": seat_id})
	if _aram != null and _aram.request_swap(ME, seat_id, now) == AllRandomSession.Err.OK:
		_outgoing.append(seat_id)
		_emit_pick()


func answer_swap(from: String, accept: bool) -> void:
	sent.append({"op": &"answer_swap", "from": from, "accept": accept})
	_incoming = _incoming.filter(func(r: Dictionary) -> bool: return r.from != from)
	if accept and _aram != null:
		_aram.accept_swap(ME, from, now)
	_emit_pick()


## Leaving the pick phase: a dodge (lockout; rating penalty in ranked).
func dodge() -> void:
	sent.append({"op": &"dodge"})
	if phase != &"pick":
		return
	_draft = null
	_aram = null
	_fail_ready(&"locked")


func remake_vote(yes: bool) -> void:
	sent.append({"op": &"remake_vote", "yes": yes})
	if _remake.is_empty() or not bool(_remake.open):
		return
	_remake.voted = true
	if yes:
		_remake.yes = int(_remake.yes) + 1
	else:
		_remake.no = int(_remake.no) + 1
		_remake.open = false
		_remake.outcome = &"failed"
	remake_state.emit(_remake_info())


func reconnect() -> void:
	sent.append({"op": &"reconnect"})
	if phase == &"match" or phase == &"assigned":
		match_assigned.emit(_assigned_info())


func honour(match_id: Variant, target: String) -> void:
	sent.append({"op": &"honour", "match": match_id, "target": target})
	feedback_result.emit({"op": &"honour", "target": target, "ok": true})


func report(match_id: Variant, target: String, category: StringName) -> void:
	sent.append({"op": &"report", "match": match_id, "target": target, "category": category})
	feedback_result.emit({"op": &"report", "target": target, "ok": rules.report_categories.has(category)})


func request_profile() -> void:
	sent.append({"op": &"profile"})
	profile_received.emit(profile())


## W20-WEB: asks for the leaderboard opt-in state (-> leaderboard_changed).
func request_leaderboard() -> void:
	sent.append({"op": &"leaderboard"})
	leaderboard_changed.emit({"public": leaderboard_public, "available": leaderboard_available})


## W20-WEB: opts in to (true) or out of the public leaderboard.
func set_leaderboard_public(on: bool) -> void:
	sent.append({"op": &"leaderboard_set", "public": on})
	if leaderboard_available:
		leaderboard_public = on
	leaderboard_changed.emit({"public": leaderboard_public, "available": leaderboard_available})


func custom_open() -> void:
	sent.append({"op": &"custom_open"})
	_custom = {"host": ME, "me": ME, "map": &"shardline_front", "mode": &"custom", "bots": true, "team_size": 5,
		"bot_slots": [-1, -1], "difficulty": &"normal",
		"maps": MatchmakingCodec.CUSTOM_MAPS.duplicate(), "modes": [&"custom", &"all_random"],
		"members": [{"id": ME, "name": "You", "team": 0, "bot": false},
			{"id": "p2", "name": NAMES[0], "team": 0, "bot": false},
			{"id": "p3", "name": NAMES[1], "team": 1, "bot": false}],
		"invited": [], "starting": false}
	custom_changed.emit(_custom.duplicate(true))


func custom_set(map_id: StringName, mode: StringName, bots: bool, team_size: int = 5) -> void:
	sent.append({"op": &"custom_set", "map": map_id, "mode": mode, "bots": bots, "team_size": team_size})
	if _custom.is_empty():
		return
	_custom.map = map_id
	_custom.mode = mode
	_custom.bots = bots
	_custom.team_size = clampi(team_size, 1, 5)
	custom_changed.emit(_custom.duplicate(true))


func custom_invite(id: String) -> void:
	sent.append({"op": &"custom_invite", "id": id})
	if not _custom.is_empty() and not (_custom.invited as Array).has(id):
		(_custom.invited as Array).append(id)
		custom_changed.emit(_custom.duplicate(true))


func custom_bots(bots_a: int, bots_b: int, difficulty: StringName) -> void:
	sent.append({"op": &"custom_bots", "bots": [bots_a, bots_b], "difficulty": difficulty})
	if _custom.is_empty():
		return
	_custom.bot_slots = [bots_a, bots_b]
	_custom.difficulty = difficulty
	custom_changed.emit(_custom.duplicate(true))


func custom_start() -> void:
	sent.append({"op": &"custom_start"})
	if _custom.is_empty():
		return
	queue = MmView.Q_CUSTOM
	phase = &"assigned"
	match_assigned.emit(_assigned_info())


## v20: own loading percent (like the server: only rising values count).
func report_load(pct: int) -> void:
	sent.append({"op": &"load", "pct": pct})
	for i in _load_seats.size():
		if str(_load_seats[i].id) == ME and pct > int(loads[i]):
			loads[i] = clampi(pct, 0, 100)
			load_progress.emit(loads.duplicate())


# --- scripted world -----------------------------------------------------------

## Advances fake time: queue -> found -> ready -> pick -> assigned.
func step(delta: float) -> void:
	now += delta
	match phase:
		&"queued":
			if now - _queued_at >= found_after_s:
				_propose()
		&"found":
			if now - float(_found.at) >= think_s:
				_found.accepted = int(_found.humans) - (0 if _me_accepted else 1)
			if _me_accepted and int(_found.accepted) >= int(_found.humans):
				_start_pick()
			elif now >= float(_found.deadline):
				_fail_ready(&"locked" if not _me_accepted else &"requeued")
		&"pick":
			_step_pick()
		&"assigned":
			_step_loads()
	if not _remake.is_empty() and bool(_remake.open) and now >= float(_remake.deadline):
		_remake.open = false
		_remake.outcome = &"failed"
		remake_state.emit(_remake_info())


## Test / preview: start the in-match remake vote (a teammate never connected).
func start_remake(window_open := true) -> void:
	phase = &"match"
	_remake = {"eligible": window_open, "open": window_open, "yes": 1, "no": 0, "needed": 4,
		"deadline": now + rules.remake_vote_s, "voted": false, "outcome": &""}
	remake_state.emit(_remake_info())


## Test / preview: the match ends.
func finish_match(won: bool, voided := false) -> void:
	phase = &"post"
	var ranked := queue == MmView.Q_RANKED
	var rating := {}
	if ranked:
		var before := float(my_ranked.get("rating", 1500))
		var delta := 0.0 if voided else (18.0 if won else -16.0)
		var svc_medal := func(r: float) -> Dictionary: return _medal(r)
		rating = {"before": roundi(before), "after": roundi(before + delta), "delta": roundi(delta),
			"medal_before": svc_medal.call(before), "medal_after": svc_medal.call(before + delta),
			"progress": MmView.medal_progress(before + delta, rules.medal_division_span, rules.medal_bands),
			"calibrating": bool(my_ranked.get("calibrating", false)),
			"games_played": rules.calibration_games - int(my_ranked.get("games_left", 0)),
			"games_needed": rules.calibration_games}
	var players: Array = []
	var size := 3 if queue == MmView.Q_ARAM else 5
	for t in 2:
		for i in size:
			var me := t == 0 and i == 0
			var id := ME if me else "p%d" % (t * size + i + 1)
			var heroes := MmView.all_heroes()
			players.append({"id": id, "name": "You" if me else NAMES[(t * size + i) % NAMES.size()], "team": t,
				"hero": heroes[(t * 3 + i) % heroes.size()], "kills": 3 + i, "deaths": 2 + t, "assists": 4 - i % 3,
				"me": me, "bot": false})
	post_match.emit({"match_id": _match_id, "queue": queue, "won": won, "voided": voided, "duration_s": 1325,
		"stats": {"kills": 7, "deaths": 4, "assists": 11, "damage": 18450, "healing": 2100, "objective": 3},
		"rating": rating, "players": players})


## Test / preview: the party (names) beside you.
func set_party(names: Array) -> void:
	party = names.duplicate()
	var members: Array = [{"id": ME, "name": "You", "leader": true, "me": true, "ready": bool(party_ready_of.get(ME, false)),
		"rating_label": MmView.ranked_line(my_ranked, rules.calibration_games)}]
	for i in party.size():
		members.append({"id": "f%d" % i, "name": str(party[i]), "leader": false, "me": false, "ready": i == 0,
			"rating_label": "Silver IV · 1420" if i % 2 == 0 else "Gold I · 1515"})
	party_changed.emit({"members": members, "leader": ME})


## P2 preview / tests: party actions on the fake party.
var party_chat: Array = []
var party_ready_of: Dictionary = {}


func party_promote(_id: String) -> void:
	sent.append({"op": &"party_promote"})


func party_kick(id: String) -> void:
	sent.append({"op": &"party_kick", "id": id})


func party_ready(on: bool) -> void:
	party_ready_of[ME] = on
	set_party(party)


func party_leave() -> void:
	set_party([])


func party_say(text: String) -> void:
	party_chat.append({"name": "You", "text": text, "mine": true})
	party_chat_changed.emit()


func party_chat_lines() -> Array:
	return party_chat


## v20 hero select team chat (the fake echoes like the server).
var select_chat: Array = []


func select_say(text: String) -> void:
	sent.append({"op": &"select_chat", "text": text})
	select_chat.append({"name": "You", "text": text, "mine": true})
	select_chat_changed.emit()


## Test / preview: a teammate writes in hero select.
func teammate_says(name: String, text: String) -> void:
	select_chat.append({"name": name, "text": text, "mine": false})
	select_chat_changed.emit()


func select_chat_lines() -> Array:
	return select_chat


## Test / preview: you are locked out for `seconds`.
func lock_out(seconds: float) -> void:
	locked_until = now + seconds
	phase = &"idle"
	queue_changed.emit(_status(&"locked"))


## Test / preview: the match link drops.
func drop_connection() -> void:
	connection_lost.emit()


func profile() -> Dictionary:
	return {"calibration_games": rules.calibration_games,
		"tracks": {&"ranked": my_ranked.merged({"progress": MmView.medal_progress(float(my_ranked.get("rating", 0)),
			rules.medal_division_span, rules.medal_bands)}), &"normal": {"games": 42}, &"all_random": {"games": 17}},
		"history": [
			{"queue": MmView.Q_RANKED, "won": true, "hero": &"hero_brannoc", "kills": 7, "deaths": 4, "assists": 11, "delta": 18, "ago_s": 3600},
			{"queue": MmView.Q_ARAM, "won": false, "hero": &"hero_hex", "kills": 12, "deaths": 9, "assists": 14, "delta": 0, "ago_s": 7200},
			{"queue": MmView.Q_NORMAL, "won": true, "hero": &"hero_sable", "kills": 9, "deaths": 3, "assists": 5, "delta": 0, "ago_s": 86400},
			{"queue": MmView.Q_RANKED, "won": false, "hero": &"hero_liora_vale", "kills": 2, "deaths": 6, "assists": 19, "delta": -16, "ago_s": 172800}]}


# --- internals ------------------------------------------------------------------

func _status(state: StringName) -> Dictionary:
	var info := {"state": state, "queue": queue, "waited_s": now - _queued_at if state == &"queued" else 0.0,
		"estimate_s": rules.default_wait_estimate_s, "in_queue": 37, "locked_s": maxf(0.0, locked_until - now),
		"err": ""}
	if state == &"locked":
		info.err = "HUD_MM_ERR_LOCKED"
	return info


func _propose() -> void:
	phase = &"found"
	select_chat.clear()
	_match_id += 1
	_me_accepted = false
	var size := 3 if queue == MmView.Q_ARAM else 5
	_found = {"match_id": _match_id, "queue": queue, "at": now, "deadline": now + rules.ready_check_s,
		"humans": size * 2, "accepted": 0, "me_accepted": false}
	match_found.emit(_found_info())


func _found_info() -> Dictionary:
	var d := _found.duplicate()
	d.deadline_s = maxf(0.0, float(_found.deadline) - now)
	return d


func _fail_ready(outcome: StringName) -> void:
	var locked := outcome == &"locked"
	if locked:
		locked_until = now + rules.decline_lockout_steps_s[0]
	phase = &"idle"
	ready_result.emit({"outcome": outcome, "locked_s": maxf(0.0, locked_until - now),
		"reason": "HUD_MM_READY_DECLINED" if locked else "HUD_MM_READY_OTHERS"})
	if locked:
		queue_changed.emit(_status(&"locked"))
	else:
		join_queue(queue, lanes)


func _start_pick() -> void:
	phase = &"pick"
	ready_result.emit({"outcome": &"go", "locked_s": 0.0, "reason": ""})
	var size := 3 if queue == MmView.Q_ARAM else 5
	var a: Array = [ME]
	var b: Array = []
	_seat_names = {ME: "You"}
	for i in range(1, size):
		a.append("p%d" % (i + 1))
	for i in size:
		b.append("p%d" % (size + i + 1))
	for k in a.size() + b.size():
		var id: String = (a + b)[k]
		if id != ME:
			_seat_names[id] = NAMES[(k - 1) % NAMES.size()]
	var slots: Array = [&"north", &"center", &"south", &"flex", &"flex"]
	for k in a.size():
		_seat_lanes[a[k]] = slots[k] if size == 5 else &""
		_seat_lanes[b[k]] = slots[(k + 2) % 5] if size == 5 else &""
	var heroes := MmView.all_heroes()
	_incoming.clear()
	_outgoing.clear()
	if queue == MmView.Q_ARAM:
		_aram = AllRandomSession.new(a, b, heroes, rules, now, _match_id)
		_draft = null
	else:
		# Team 1 starts so the screens show the enemy pick, then you.
		_draft = DraftSession.new(a, b, heroes, rules, now, _match_id, 1)
		_aram = null
	_turn_seen = _draft.turn if _draft != null else -1
	_turn_at = now
	_emit_pick()


func _step_pick() -> void:
	if _draft != null:
		if _draft.turn != _turn_seen:
			_turn_seen = _draft.turn
			_turn_at = now
		if now - _turn_at >= think_s:
			for s: String in _draft.current_pickers():
				if s != ME:
					var legal := _draft.legal_heroes(_draft.turn_team)
					if not legal.is_empty():
						_draft.pick(s, legal[(s.hash() & 0xFFFF) % legal.size()], now)
		_draft.tick(now)
		if _draft.turn != _turn_seen:
			_turn_seen = _draft.turn
			_turn_at = now
		_emit_pick()
		if _draft.state == DraftSession.State.DONE:
			_draft = null
			phase = &"assigned"
			match_assigned.emit(_assigned_info())
	elif _aram != null:
		if _incoming.is_empty() and _outgoing.is_empty() and now - _turn_at >= think_s and now - _turn_at < think_s + 0.5:
			var mate: String = _aram.teams[0][1]
			if _aram.request_swap(mate, ME, now) == AllRandomSession.Err.OK:
				_incoming.append({"from": mate, "at": now})
		_incoming = _incoming.filter(func(r: Dictionary) -> bool: return now - float(r.at) < rules.swap_request_ttl_s)
		if _aram.tick(now) == AllRandomSession.State.LOCKED:
			_emit_pick()
			_aram = null
			phase = &"assigned"
			match_assigned.emit(_assigned_info())
			return
		_emit_pick()


func _emit_pick() -> void:
	if _draft != null:
		_my_hero = StringName(_draft.picks.get(ME, _my_hero))
	elif _aram != null:
		_my_hero = StringName(_aram.hero_of.get(ME, _my_hero))
	if _draft != null:
		var seats: Array = []
		var pickers := _draft.current_pickers()
		for t in 2:
			for id: String in _draft.teams[t]:
				seats.append({"id": id, "name": _seat_names.get(id, id), "team": t, "lane": _seat_lanes.get(id, &""),
					"hero": _draft.picks.get(id, &""), "bot": MatchmakingRulesDef.is_bot(id),
					"auto": _draft.auto_picked.has(id), "picking": pickers.has(id)})
		pick_state.emit({"mode": &"draft", "queue": queue, "ranked": queue == MmView.Q_RANKED, "me": ME, "my_team": 0,
			"turn": _draft.turn, "turn_team": _draft.turn_team, "order": rules.draft_order, "first_team": 1,
			"deadline_s": maxf(0.0, _draft.deadline - now), "turn_s": rules.pick_turn_s,
			"done": _draft.state != DraftSession.State.PICKING, "seats": seats})
		_load_seats = seats
	elif _aram != null:
		var seats: Array = []
		for t in 2:
			for id: String in _aram.teams[t]:
				seats.append({"id": id, "name": _seat_names.get(id, id), "team": t, "lane": &"",
					"hero": _aram.hero_of.get(id, &""), "bot": MatchmakingRulesDef.is_bot(id), "auto": false,
					"picking": false})
		var reqs: Array = []
		for r: Dictionary in _incoming:
			reqs.append({"from": r.from, "name": _seat_names.get(r.from, r.from), "hero": _aram.hero_of.get(r.from, &"")})
		pick_state.emit({"mode": &"all_random", "queue": queue, "me": ME, "my_team": 0,
			"open": _aram.state == AllRandomSession.State.OPEN, "deadline_s": maxf(0.0, _aram.deadline - now),
			"turn_s": rules.all_random_s, "rerolls_left": int(_aram.rerolls_left.get(ME, 0)),
			"bench": (_aram.bench[0] as Array).duplicate(), "seats": seats, "swap_requests": reqs,
			"outgoing": _outgoing.duplicate()})
		_load_seats = seats


func _assigned_info() -> Dictionary:
	_assigned_at = now
	loads = _load_seats.map(func(st: Dictionary) -> int: return 100 if bool(st.bot) else 0)
	return {"match_id": _match_id, "host": "127.0.0.1", "port": rules.match_port_first,
		"ticket": "fake-ticket-%d-%d" % [_match_id, int(now * 1000.0)], "queue": queue,
		"hero": _my_hero, "hero_index": MmView.hero_index(_my_hero),
		"map": &"slice" if queue == MmView.Q_ARAM else &"shardline_front"}


## The other players load at their own pace (rising in 10 % steps).
func _step_loads() -> void:
	var changed := false
	for i in mini(_load_seats.size(), loads.size()):
		var st: Dictionary = _load_seats[i]
		if bool(st.bot) or str(st.id) == ME:
			continue
		var pct := clampi(floori((now - _assigned_at) / (load_s * (1 + i % 3) / 2.0) * 10.0) * 10, 0, 100)
		if pct > int(loads[i]):
			loads[i] = pct
			changed = true
	if changed:
		load_progress.emit(loads.duplicate())


func _remake_info() -> Dictionary:
	var d := _remake.duplicate()
	d.deadline_s = maxf(0.0, float(_remake.deadline) - now)
	if not bool(d.open) and d.outcome == &"":
		d.outcome = &"failed"
	if int(d.yes) >= int(d.needed):
		d.outcome = &"passed"
		d.open = false
	return d


func _medal(rating: float) -> Dictionary:
	return RatingService.new(MemoryRatingStore.new(), rules).medal_for(rating)
