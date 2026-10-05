class_name MatchmakingFront
extends RefCounted
## The front's matchmaking owner (W17B, docs/architecture/matchmaking-phaseB.md
## §3-4, design/gdd/matchmaking.md). Lives in the front process next to
## AccountService; FrontServer feeds it MM_REQ packets and calls step().
##
## Flow per match (state machine of one `Match`):
##   queue (Matchmaker) -> READY (ReadyCheck) -> PICK (DraftSession /
##   AllRandomSession) -> STARTING (MatchSupervisor.request_match) ->
##   RUNNING (join tickets sent) -> result (ratings, lockouts, history,
##   reports window) or void (no rating change, players re-queued).
## Custom games skip the queue and the ready check: a host builds a lobby,
## invites friends / the party, picks, starts (unrated, no lockouts).
##
## Server authoritative: every request is checked against the sender's
## logged-in identity (AccountService) and the match state. Bad packets are
## dropped (FrontServer counts violations).
##
## Collaborators are injected so tests run in memory: the supervisor is a
## MatchSupervisor or any object with request_match / issue_join_ticket /
## find_match and the signals match_started / match_result / match_voided /
## abandon_reported. Time: `clock` returns unix seconds (float); persisted
## data and queue logic share that clock, so lockouts survive restarts.
##
## Privacy (PRIVACY.md, W17B-OPS): ratings (until account deletion), reports
## (report_retention_days), match history (history_retention_days: ids,
## heroes, result, duration), lockout strikes (lockout_retention_days after
## the last strike). Display names are only held in memory for a running
## match and the post-match report window. account_deleted erases all four.

enum State { READY, PICK, STARTING, RUNNING }

const LOCKOUT_FILE := "lockouts.json"
const DAY: float = 86400.0
## Seconds between supervisor retries while every match process is busy.
const ALLOCATE_RETRY_S := 2.0
## Map ids of the queues -> the game's --map names.
const MAP_NAMES := {&"shardline_front": "front", &"slice": "slice"}


class Match:
	extends RefCounted
	var id: String = ""
	var queue: MatchQueueDef
	var proposal: Dictionary = {}
	var state: int = State.READY
	var rc: ReadyCheck
	var draft: DraftSession
	var aram: AllRandomSession
	## Seats in wire order (team 0 then team 1): {id, team, lane, bot, name, accent, hero}.
	var seats: Array = []
	var rated: bool = false
	var custom: bool = false
	var custom_mode: int = 0
	var map: String = ""
	var mood: int = 0
	var since: float = 0.0
	var started_at: float = 0.0
	var requested: bool = false
	var last_try: float = -1.0e9
	var leavers: Dictionary = {}
	var gone_since: Dictionary = {}
	var pick_sig: String = ""


var transport: Transport
var accounts: AccountService
var rules: MatchmakingRulesDef
var supervisor: Variant
var matchmaker: Matchmaker
var lockouts: LockoutTracker
var ratings: RatingService
var reports: ReportStore
var history: MatchHistoryStore
var content: ContentDB
var heroes: Array[StringName] = []
## Folder for lockouts.json ("" = memory only).
var mm_dir: String = ""
## Unix seconds (float). Tests inject a fake.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()
var log_fn: Callable = func(line: String) -> void: print(line)
## Extra keys copied into every match setup's rules (debug: match_clock, end_after_s).
var setup_rules: Dictionary = {}
## Testing only (CYBERGRAM_RATE_GUESTS): keep guest ratings in the store.
var rate_guests: bool = false

var _matches: Dictionary = {}        # match id -> Match
var _account_match: Dictionary = {}  # account id -> Match
var _queued: Dictionary = {}         # account id -> party member ids (as queued)
var _away_since: Dictionary = {}     # queued account id -> time it lost its connection
var _recent: Dictionary = {}         # match id -> {participants, names, until}
var _customs: Dictionary = {}        # host id -> custom lobby
var _custom_of: Dictionary = {}      # member id -> host id
var _last_strike: Dictionary = {}    # account id -> unix time of the last strike
var _since_status: float = 0.0
var _last_housekeeping: float = -1.0e12
var _last_now: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init(t: Transport, accounts_: AccountService, supervisor_: Variant, ratings_: RatingService,
		reports_: ReportStore, history_: MatchHistoryStore, rules_: MatchmakingRulesDef = null,
		mm_dir_: String = "", content_: ContentDB = null) -> void:
	transport = t
	accounts = accounts_
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()
	supervisor = supervisor_
	ratings = ratings_
	reports = reports_
	history = history_
	mm_dir = mm_dir_
	content = content_ if content_ != null else ContentDB.shared()
	heroes = HeroPool.from_content_db(content)
	lockouts = LockoutTracker.new(rules)
	matchmaker = Matchmaker.new(rules, lockouts)
	_rng.randomize()
	_load_lockouts()
	if supervisor != null:
		supervisor.match_started.connect(_on_match_started)
		supervisor.match_result.connect(_on_match_result)
		supervisor.match_voided.connect(_on_match_voided)
		supervisor.abandon_reported.connect(_on_abandon)
	if accounts != null:
		accounts.account_deleted.connect(erase_account)


func now() -> float:
	return float(clock.call())


# --- requests --------------------------------------------------------------------

## One MM_REQ packet from `peer`.
func handle(peer: int, data: PackedByteArray) -> bool:
	var r := MatchmakingCodec.decode_request(data)
	if r.is_empty():
		_ack(peer, data.decode_u8(1) if data.size() > 1 else 0, MatchmakingCodec.E_BAD_REQUEST)
		return false
	var who := accounts.identity(peer)
	var op: int = r.op
	if who.is_empty():
		_ack(peer, op, MatchmakingCodec.E_NOT_LOGGED_IN)
		return true
	var me := str(who.id)
	var t := now()
	match op:
		MatchmakingCodec.OP_QUEUE_JOIN:
			_queue_join(peer, who, r, t)
		MatchmakingCodec.OP_QUEUE_LEAVE:
			_queue_leave(me, t)
		MatchmakingCodec.OP_READY_REPLY:
			_ready_reply(peer, me, int(r.accept) != 0, t)
		MatchmakingCodec.OP_PICK:
			_pick(peer, me, int(r.hero), t)
		MatchmakingCodec.OP_ARAM_REROLL, MatchmakingCodec.OP_ARAM_BENCH, MatchmakingCodec.OP_ARAM_SWAP_REQUEST, \
				MatchmakingCodec.OP_ARAM_SWAP_ACCEPT:
			_aram(peer, me, r, t)
		MatchmakingCodec.OP_REPORT, MatchmakingCodec.OP_HONOUR:
			_report(peer, me, r)
		MatchmakingCodec.OP_RANKED_INFO:
			if bool(who.get("guest", false)):
				_ack(peer, op, MatchmakingCodec.E_GUEST)
			else:
				send_ranked_info(me)
		MatchmakingCodec.OP_REJOIN:
			var m: Match = _account_match.get(me)
			if m == null or m.state != State.RUNNING or not _send_assigned(m, me, t):
				_ack(peer, op, MatchmakingCodec.E_NOT_FOUND)
		MatchmakingCodec.OP_CUSTOM_CREATE, MatchmakingCodec.OP_CUSTOM_INVITE, MatchmakingCodec.OP_CUSTOM_JOIN, \
				MatchmakingCodec.OP_CUSTOM_LEAVE, MatchmakingCodec.OP_CUSTOM_TEAM, MatchmakingCodec.OP_CUSTOM_PICK, \
				MatchmakingCodec.OP_CUSTOM_START:
			_custom(peer, who, r, t)
		MatchmakingCodec.OP_REMAKE_VOTE:
			_ack(peer, op, MatchmakingCodec.E_NOT_ALLOWED)  # in-match only (the match process)
	return true


func _queue_join(_peer: int, who: Dictionary, r: Dictionary, t: float) -> void:
	var me := str(who.id)
	var qi := int(r.queue)
	var q: MatchQueueDef = null
	if qi < MatchmakingClient.QUEUE_IDS.size():
		q = rules.queue(MatchmakingClient.QUEUE_IDS[qi])
	if q == null or not q.matchmade:
		_send_status(me, MatchmakingCodec.E_QUEUE)
		return
	var members: Array = [me]
	if accounts.parties != null:
		var ps := accounts.parties.state_of(me, t)
		if str(ps.party) != "":
			if str(ps.leader) != me:
				_send_status(me, MatchmakingCodec.E_NOT_LEADER)
				return
			members = ps.members
	if members.size() > mini(rules.party_max, q.team_size):
		_send_status(me, MatchmakingCodec.E_PARTY_SIZE)
		return
	for id in members:
		if _account_match.has(id):
			_send_status(me, MatchmakingCodec.E_IN_MATCH)
			return
		if _custom_of.has(id) or matchmaker.ticket_of(str(id)) != 0:
			_send_status(me, MatchmakingCodec.E_ALREADY)
			return
		var ident := _identity_of(str(id))
		if ident.is_empty():
			_send_status(me, MatchmakingCodec.E_NOT_ALLOWED)  # a party member is offline
			return
		if q.ranked and bool(ident.get("guest", false)):
			_send_status(me, MatchmakingCodec.E_GUEST)
			return
	var lanes: Array = [&"fill"]
	if int(r.lane1) != MatchmakingCodec.LANE_FILL:
		lanes = [MatchmakingCodec.lane_of(int(r.lane1)), MatchmakingCodec.lane_of(int(r.lane2))]
		if int(r.lane2) == MatchmakingCodec.LANE_FILL or r.lane1 == r.lane2:
			lanes = [lanes[0], &"fill"] if lanes[0] != &"flex" else [&"flex", &"fill"]
	var ms: Array = []
	for id in members:
		ms.append({"id": str(id), "rating": _rating_of(str(id), q.rating_track),
			"lanes": lanes if str(id) == me else [&"fill"]})
	var res := matchmaker.enqueue(q.id, ms, t)
	var err := int(res.err)
	if err == Matchmaker.Err.E_LANES and lanes != [&"fill"]:
		for m in ms:
			m.lanes = [&"fill"]  # an unusual lane pair: queue as fill rather than fail
		res = matchmaker.enqueue(q.id, ms, t)
		err = int(res.err)
	if err != Matchmaker.Err.OK:
		if err == Matchmaker.Err.E_LOCKED:
			_send_lockout(me, float(res.locked_until) - t, q.ranked, MatchmakingCodec.LK_DECLINE)
		_send_status(me, err + 1, float(res.get("locked_until", 0.0)) - t)
		return
	for id in members:
		_queued[str(id)] = members.duplicate()
		_away_since.erase(str(id))
		_send_status(str(id))
	_log("[front] queue %s: party of %d joined" % [q.id, members.size()])


func _queue_leave(me: String, t: float) -> void:
	var m: Match = _account_match.get(me)
	if m != null:
		if m.state == State.READY:
			m.rc.decline(me, t)
		elif m.state == State.PICK and not m.custom:
			_dodge(m, me, t)
		return
	var mates: Array = _queued.get(me, [me])
	matchmaker.leave(me)
	for id in mates:
		_queued.erase(str(id))
		_send_status(str(id))


func _ready_reply(peer: int, me: String, accept: bool, t: float) -> void:
	var m: Match = _account_match.get(me)
	if m == null or m.state != State.READY:
		_ack(peer, MatchmakingCodec.OP_READY_REPLY, MatchmakingCodec.E_NOT_FOUND)
		return
	var ok := m.rc.accept(me, t) if accept else m.rc.decline(me, t)
	if not ok:
		_ack(peer, MatchmakingCodec.OP_READY_REPLY, MatchmakingCodec.E_NOT_ALLOWED)
		return
	if accept:
		_send_found(m, t)


func _pick(peer: int, me: String, hero_index: int, t: float) -> void:
	var m: Match = _account_match.get(me)
	if m == null or m.state != State.PICK or m.draft == null:
		_ack(peer, MatchmakingCodec.OP_PICK, MatchmakingCodec.E_NOT_ALLOWED)
		return
	var hero := _hero_id(hero_index)
	var e := m.draft.pick(me, hero, t)
	var code := MatchmakingCodec.OK
	match e:
		DraftSession.Err.E_TAKEN:
			code = MatchmakingCodec.E_TAKEN
		DraftSession.Err.E_UNKNOWN_HERO:
			code = MatchmakingCodec.E_BAD_REQUEST
		DraftSession.Err.E_NOT_YOUR_TURN, DraftSession.Err.E_CLOSED:
			code = MatchmakingCodec.E_NOT_ALLOWED
	_ack(peer, MatchmakingCodec.OP_PICK, code)
	_step_pick(m, t)


func _aram(peer: int, me: String, r: Dictionary, t: float) -> void:
	var op: int = r.op
	var m: Match = _account_match.get(me)
	if m == null or m.state != State.PICK or m.aram == null:
		_ack(peer, op, MatchmakingCodec.E_NOT_ALLOWED)
		return
	var e: int = AllRandomSession.Err.OK
	match op:
		MatchmakingCodec.OP_ARAM_REROLL:
			e = m.aram.reroll(me, t)
		MatchmakingCodec.OP_ARAM_BENCH:
			e = m.aram.take_from_bench(me, _hero_id(int(r.hero)), t)
		MatchmakingCodec.OP_ARAM_SWAP_REQUEST, MatchmakingCodec.OP_ARAM_SWAP_ACCEPT:
			var si := int(r.seat)
			if si >= m.seats.size():
				e = AllRandomSession.Err.E_NOT_TEAMMATE
			elif op == MatchmakingCodec.OP_ARAM_SWAP_REQUEST:
				e = m.aram.request_swap(me, str(m.seats[si].id), t)
			else:
				e = m.aram.accept_swap(me, str(m.seats[si].id), t)
	var code := MatchmakingCodec.OK
	match e:
		AllRandomSession.Err.E_NO_REROLLS, AllRandomSession.Err.E_EMPTY:
			code = MatchmakingCodec.E_NO_REROLLS
		AllRandomSession.Err.E_NOT_ON_BENCH, AllRandomSession.Err.E_NO_REQUEST:
			code = MatchmakingCodec.E_NOT_FOUND
		AllRandomSession.Err.OK:
			code = MatchmakingCodec.OK
		_:
			code = MatchmakingCodec.E_NOT_ALLOWED
	_ack(peer, op, code)
	_step_pick(m, t)


func _report(peer: int, me: String, r: Dictionary) -> void:
	var op: int = r.op
	var rec: Dictionary = _recent.get(str(r.match), {})
	if rec.is_empty() or now() > float(rec.until):
		_ack(peer, op, MatchmakingCodec.E_NOT_FOUND)
		return
	var res: int
	var now_unix := int(now())
	if op == MatchmakingCodec.OP_REPORT:
		var ci := int(r.category)
		if ci >= rules.report_categories.size():
			_ack(peer, op, MatchmakingCodec.E_BAD_REQUEST)
			return
		res = reports.report(str(r.match), me, str(r.target), rules.report_categories[ci], rec.participants, now_unix)
	else:
		res = reports.honour(str(r.match), me, str(r.target), rec.participants, now_unix)
	var code := MatchmakingCodec.OK
	match res:
		ReportStore.Result.E_CATEGORY:
			code = MatchmakingCodec.E_BAD_REQUEST
		ReportStore.Result.E_SELF:
			code = MatchmakingCodec.E_NOT_ALLOWED
		ReportStore.Result.E_DUPLICATE:
			code = MatchmakingCodec.E_DUPLICATE
		ReportStore.Result.E_NOT_IN_MATCH:
			code = MatchmakingCodec.E_NOT_FOUND
		ReportStore.Result.E_STORE:
			code = MatchmakingCodec.E_BUSY
	_ack(peer, op, code)


# --- main loop ----------------------------------------------------------------------

## Call every frame (after the packets were handled).
func step() -> void:
	var t := now()
	var dt := maxf(0.0, t - _last_now) if _last_now > 0.0 else 0.0
	_last_now = t
	for p in matchmaker.tick(t):
		_on_proposal(p, t)
	for m: Match in _matches.values().duplicate():
		match m.state:
			State.READY:
				_step_ready(m, t)
			State.PICK:
				_watch_pick_connections(m, t)
				if _matches.has(m.id):
					_step_pick(m, t)
			State.STARTING:
				_step_starting(m, t)
	_since_status += dt
	if _since_status >= rules.queue_status_every_s:
		_since_status = 0.0
		_refresh_queued(t)
	for k in _recent.keys():
		if t > float(_recent[k].until):
			_recent.erase(k)
	if t - _last_housekeeping >= DAY:
		housekeeping(t)


## Daily retention work (and at start): reports, history, lockouts.
func housekeeping(t: float) -> void:
	_last_housekeeping = t
	var n_rep := reports.purge(int(t)) if reports != null else 0
	var n_hist := history.purge(int(t)) if history != null else 0
	lockouts.sweep(t)
	var cutoff := t - rules.lockout_retention_days * DAY
	var n_lock := 0
	for id in _last_strike.keys():
		if float(_last_strike[id]) < cutoff:
			lockouts.erase(str(id))
			_last_strike.erase(id)
			n_lock += 1
	for id in lockouts.ids():
		if not _last_strike.has(id):
			lockouts.erase(str(id))  # no strike time known (old file): nothing to keep
	_save_lockouts()
	if n_rep + n_hist + n_lock > 0:
		_log("[front] retention: deleted %d report(s), %d history entr(ies), %d lockout record(s)" % [
			n_rep, n_hist, n_lock])


func _on_proposal(p: Dictionary, t: float) -> void:
	var m := Match.new()
	m.id = JoinTicket.new_match_id()
	m.queue = rules.queue(p.queue)
	m.proposal = p
	m.rated = bool(p.rated) and String(m.queue.rating_track) != ""
	m.map = MAP_NAMES.get(m.queue.map_id, String(m.queue.map_id))
	m.since = t
	m.rc = ReadyCheck.new(Matchmaker.human_ids(p), t, rules.ready_check_s)
	for side in 2:
		for seat: Dictionary in p.teams[side]:
			var ident := _identity_of(str(seat.id)) if not seat.bot else {}
			m.seats.append({"id": str(seat.id), "team": side, "lane": seat.lane, "bot": bool(seat.bot),
				"name": str(ident.get("name", "")), "accent": int(ident.get("accent", 0)), "hero": &""})
	_matches[m.id] = m
	for id in Matchmaker.human_ids(p):
		_account_match[id] = m
		_queued.erase(id)
	_log("[front] match %s found (%s, %d bot(s)): ready check" % [m.id, m.queue.id, int(p.bots)])
	_send_found(m, t)


func _step_ready(m: Match, t: float) -> void:
	match m.rc.tick(t):
		ReadyCheck.State.ACCEPTED:
			matchmaker.confirm(m.proposal)
			for id in _humans(m):
				_send(id, MatchmakingCodec.EV_READY_RESULT, MatchmakingCodec.OK, {"outcome": MatchmakingCodec.RR_GO})
			_start_pick(m, t)
		ReadyCheck.State.FAILED:
			_fail(m, m.rc.failed_ids(), t, false)


## The ready check failed or someone dodged: strikes, re-queue the others.
func _fail(m: Match, failed: Array, t: float, dodge: bool) -> void:
	var res := matchmaker.resolve_ready_check(m.proposal, failed, t)
	_end(m)
	for id in res.locked:
		_strike(str(id), t)
		if dodge and m.queue.ranked:
			ratings.apply_dodge_penalty(str(id), m.queue.rating_track, int(t))
	_save_lockouts()
	for id in _humans(m):
		var out := MatchmakingCodec.RR_REQUEUED
		var locked := 0.0
		if res.locked.has(id):
			out = MatchmakingCodec.RR_LOCKED
			locked = lockouts.locked_until(id, t) - t
			_send_lockout(id, locked, false, MatchmakingCodec.LK_DECLINE)
		elif res.removed.has(id):
			out = MatchmakingCodec.RR_REMOVED
		_send(id, MatchmakingCodec.EV_READY_RESULT, MatchmakingCodec.OK, {"outcome": out, "locked": ceili(maxf(0.0, locked))})
	for tid in res.requeued:
		var tk := matchmaker.ticket(int(tid))
		var ids: Array = tk.members.map(func(x: Dictionary) -> String: return str(x.id))
		for id in ids:
			_queued[id] = ids
			_send_status(id)
	_log("[front] match %s cancelled (%s): %d failed, %d party(ies) re-queued" % [m.id,
		"dodge" if dodge else "ready check", failed.size(), res.requeued.size()])


func _start_pick(m: Match, t: float) -> void:
	m.state = State.PICK
	m.since = t
	var teams := [[], []]
	for s in m.seats:
		teams[s.team].append(s.id)
	var seed_ := m.id.hash()
	if m.queue.pick_mode == MatchQueueDef.PickMode.ALL_RANDOM:
		m.aram = AllRandomSession.new(teams[0], teams[1], heroes, rules, t, seed_)
	else:
		m.draft = DraftSession.new(teams[0], teams[1], heroes, rules, t, seed_, seed_ & 1)
	_step_pick(m, t)


func _watch_pick_connections(m: Match, t: float) -> void:
	for id in _humans(m):
		if _peer_of(id) >= 0:
			m.gone_since.erase(id)
		elif not m.gone_since.has(id):
			m.gone_since[id] = t
		elif t - float(m.gone_since[id]) >= rules.pick_disconnect_grace_s:
			_dodge(m, id, t)
			return


func _dodge(m: Match, id: String, t: float) -> void:
	if m.draft != null:
		m.draft.dodge(id)
	_fail(m, [id], t, true)


func _step_pick(m: Match, t: float) -> void:
	var done := false
	if m.draft != null:
		done = m.draft.tick(t) == DraftSession.State.DONE
	elif m.aram != null:
		done = m.aram.tick(t) == AllRandomSession.State.LOCKED
	var sig := _pick_signature(m)
	if sig != m.pick_sig or done:
		m.pick_sig = sig
		for id in _humans(m):
			_send(id, MatchmakingCodec.EV_PICK_STATE, MatchmakingCodec.OK, _pick_state_for(m, id, t))
	if done:
		for s in m.seats:
			s.hero = m.draft.picks.get(s.id, &"") if m.draft != null else m.aram.hero_of.get(s.id, &"")
		_allocate(m, t)


func _pick_signature(m: Match) -> String:
	if m.draft != null:
		return var_to_str([m.draft.turn, m.draft.picks])
	return var_to_str([m.aram.hero_of, m.aram.bench, m.aram.rerolls_left, m.aram._requests.keys()])


## PICK_STATE for one viewer: enemy seats carry no id and no name.
func _pick_state_for(m: Match, viewer: String, t: float) -> Dictionary:
	var my_team := _team_of(m, viewer)
	var seats: Array = []
	var you := 0
	var pickers: Array = m.draft.current_pickers() if m.draft != null else []
	for i in m.seats.size():
		var s: Dictionary = m.seats[i]
		var hero: StringName = &""
		var flags := MatchmakingCodec.SEAT_BOT if s.bot else 0
		if m.draft != null:
			hero = m.draft.picks.get(s.id, &"")
			if m.draft.auto_picked.has(s.id):
				flags |= MatchmakingCodec.SEAT_AUTO
			if pickers.has(s.id):
				flags |= MatchmakingCodec.SEAT_PICKING
		else:
			hero = m.aram.hero_of.get(s.id, &"")
			flags |= MatchmakingCodec.SEAT_AUTO
		if hero != &"":
			flags |= MatchmakingCodec.SEAT_PICKED
		if s.id == viewer:
			flags |= MatchmakingCodec.SEAT_YOU
			you = i
		var mine: bool = s.team == my_team
		seats.append({"id": s.id if mine and not s.bot else "", "team": s.team,
			"lane": MatchmakingCodec.lane_byte(s.lane), "hero": _hero_index(hero), "flags": flags,
			"name": s.name if mine else ""})
	var st := {"mode": MatchmakingCodec.PM_ALL_RANDOM if m.aram != null else MatchmakingCodec.PM_DRAFT,
		"you": you, "seats": seats, "rerolls": 0, "bench": [], "swap_from": []}
	if m.draft != null:
		st.turn = maxi(0, m.draft.turn)
		st.turn_team = m.draft.turn_team
		st.seconds = ceili(maxf(0.0, m.draft.deadline - t))
	else:
		st.turn = 0
		st.turn_team = my_team
		st.seconds = ceili(maxf(0.0, m.aram.deadline - t))
		st.rerolls = int(m.aram.rerolls_left.get(viewer, 0))
		st.bench = (m.aram.bench[my_team] as Array).map(func(h: StringName) -> int: return _hero_index(h))
		var from: Array = m.aram.swap_requests_to(viewer, t)
		st.swap_from = from.map(func(id: String) -> int: return _seat_index(m, id))
	return st


func _allocate(m: Match, t: float) -> void:
	m.state = State.STARTING
	m.since = t
	m.mood = _rng.randi() & 0x7FFFFFFF
	_try_allocate(m, t)


func _try_allocate(m: Match, t: float) -> void:
	m.last_try = t
	var err: int = supervisor.request_match(build_setup(m)) if supervisor != null else ERR_UNAVAILABLE
	if err == OK:
		m.requested = true
		_log("[front] match %s picks done: waiting for a match process" % m.id)
	elif err == ERR_UNAVAILABLE:
		_void(m, "draining")
	elif err != ERR_BUSY:
		_void(m, "setup_rejected")


func _step_starting(m: Match, t: float) -> void:
	if not m.requested and t - m.last_try >= ALLOCATE_RETRY_S:
		_try_allocate(m, t)
	if _matches.has(m.id) and m.state == State.STARTING and t - m.since > rules.allocate_wait_s:
		_void(m, "no_match_server")


## The match setup ("Megapacket") for the match process (MatchSetup).
func build_setup(m: Match) -> Dictionary:
	var roster: Array = []
	for s in m.seats:
		roster.append({"account": "" if s.bot else s.id, "team": s.team, "hero": String(s.hero),
			"lane": String(s.lane), "bot": s.bot, "name": s.name, "accent": s.accent})
	var r := {"remake_window_s": rules.remake_window_s, "remake_vote_s": rules.remake_vote_s,
		"no_show_s": rules.no_show_s, "abandon_after_s": rules.abandon_after_s,
		"team_size": m.queue.team_size if m.queue != null else _team_size(m), "mood_seed": m.mood,
		"rated": m.rated, "custom": m.custom, "bots": _has_bots(m)}
	for k in setup_rules:
		r[k] = setup_rules[k]
	return {"match_id": m.id, "mode": String(m.queue.id) if m.queue != null else "custom", "map": m.map,
		"rules": r, "roster": roster}


# --- supervisor events -------------------------------------------------------------

func _on_match_started(match_id: String, endpoint: Dictionary) -> void:
	var m: Match = _matches.get(match_id)
	if m == null:
		return
	var t := now()
	m.state = State.RUNNING
	m.started_at = t
	var pid := -1
	if supervisor.has_method("find_match"):
		var p: Variant = supervisor.find_match(match_id)
		if p != null:
			pid = int(p.pid)
	_log("[front] match_started id=%s pid=%d port=%d players=%d" % [match_id, pid, int(endpoint.get("port", 0)),
		_humans(m).size()])
	for id in _humans(m):
		_send_assigned(m, id, t)


func _send_assigned(m: Match, id: String, t: float) -> bool:
	var tk: Dictionary = supervisor.issue_join_ticket(m.id, id, t)
	if tk.is_empty():
		return false
	var seat := m.seats[_seat_index(m, id)] as Dictionary
	return _send(id, MatchmakingCodec.EV_MATCH_ASSIGNED, MatchmakingCodec.OK, {"host": str(tk.host),
		"port": int(tk.port), "ticket": str(tk.ticket), "match": m.id, "team": seat.team,
		"hero": _hero_index(seat.hero), "map": m.map})


func _on_abandon(match_id: String, account_id: String) -> void:
	var m: Match = _matches.get(match_id)
	if m != null:
		m.leavers[account_id] = true


func _on_match_voided(match_id: String, reason: String) -> void:
	var m: Match = _matches.get(match_id)
	if m == null:
		return
	_void(m, reason)


## No rating change; players are told and (matchmade) re-queued with priority.
func _void(m: Match, reason: String) -> void:
	var t := now()
	_log("[front] match_voided id=%s reason=%s" % [m.id, reason.left(64)])
	var was_running := m.state == State.RUNNING
	_end(m)
	if was_running and history != null:
		history.add(_history_entry(m, -1, true, t - m.started_at, {}))
	for id in _humans(m):
		_send(id, MatchmakingCodec.EV_READY_RESULT, MatchmakingCodec.OK, {"outcome": MatchmakingCodec.RR_VOIDED})
	if m.custom:
		return
	for tk: Dictionary in m.proposal.get("tickets", []):
		var online := true
		for mem in tk.members:
			online = online and _peer_of(str(mem.id)) >= 0
		if not online:
			continue
		if matchmaker.requeue(tk.queue, tk.members, float(tk.enqueued_at)) != 0:
			var ids: Array = tk.members.map(func(x: Dictionary) -> String: return str(x.id))
			for id in ids:
				_queued[id] = ids
				_send_status(id)


## Match result from the match process (MatchHostAgent.report_result).
func _on_match_result(match_id: String, res: Dictionary) -> void:
	var m: Match = _matches.get(match_id)
	if m == null:
		return
	var t := now()
	var winner := int(res.get("winner", -1))
	var remake := bool(res.get("remake", false))
	var voided := remake or winner < 0 or winner > 1
	var humans := _humans(m)
	for a in res.get("abandons", []):
		if humans.has(str(a)):
			m.leavers[str(a)] = true
	var leavers: Array = m.leavers.keys()
	var team_ids := [[], []]
	for s in m.seats:
		team_ids[s.team].append(s.id)
	var deltas := {}
	if m.rated and not m.custom:
		deltas = ratings.apply_result(m.queue.rating_track, team_ids[0], team_ids[1], maxi(winner, 0), int(t),
			leavers, voided)
		if not rate_guests:
			for id in humans:
				if bool(_identity_of(id).get("guest", false)):
					ratings.store.erase_account(id)
	var struck := {}
	if not m.custom:
		if not voided:
			for id in leavers:
				struck[id] = lockouts.record(str(id), LockoutTracker.Kind.LEAVE, t)
		if remake:
			var absent: Array = (res.get("remake_absent", []) as Array).filter(func(x: Variant) -> bool:
				return humans.has(str(x)))
			struck.merge(RemakeVote.strike_absent(lockouts, absent, t))
		for id in struck:
			_strike(str(id), t)
		_save_lockouts()
	var stats := {}
	for p: Variant in res.get("players", []):
		if p is Dictionary:
			stats[str(p.get("account", ""))] = p
	var duration := float(res.get("duration_s", t - m.started_at))
	if history != null:
		history.add(_history_entry(m, -1 if voided else winner, voided, duration, m.leavers))
	_recent[m.id] = {"participants": humans.duplicate(), "until": t + rules.report_window_s}
	_end(m)
	_log("[front] match_result id=%s winner=%d voided=%s rated=%s changes=%d leavers=%d" % [m.id, winner, voided,
		m.rated and not deltas.is_empty(), deltas.size(), leavers.size()])
	for id in humans:
		var team := _team_of(m, id)
		var players: Array = []
		for s in m.seats:
			var st: Dictionary = stats.get(s.id, {})
			var flags := (MatchmakingCodec.MEM_BOT if s.bot else 0) | (MatchmakingCodec.MEM_YOU if s.id == id else 0)
			if m.leavers.has(s.id):
				flags |= MatchmakingCodec.MEM_LEAVER
			players.append({"id": "" if s.bot else s.id, "team": s.team, "hero": _hero_index(s.hero), "flags": flags,
				"kills": int(st.get("kills", 0)), "deaths": int(st.get("deaths", 0)),
				"assists": int(st.get("assists", 0)), "name": s.name})
		var d: Dictionary = deltas.get(id, {})
		_send(id, MatchmakingCodec.EV_MATCH_RESULT, MatchmakingCodec.OK, {"match": m.id,
			"queue": _queue_index(m), "won": 1 if (not voided and team == winner) else 0, "voided": 1 if voided else 0,
			"duration": int(duration), "rated": 1 if not d.is_empty() else 0,
			"delta": roundi(float(d.get("delta", 0.0)) * 10.0), "players": players})
		if struck.has(id):
			_send_lockout(id, lockouts.locked_until(id, t, true) - t, true, MatchmakingCodec.LK_LEAVE)
		if m.queue != null and m.queue.ranked:
			send_ranked_info(id)


func _history_entry(m: Match, winner: int, voided: bool, duration: float, leavers: Dictionary) -> Dictionary:
	var players: Array = []
	for s in m.seats:
		if not s.bot:
			players.append({"id": s.id, "team": s.team, "hero": String(s.hero), "left": leavers.has(s.id)})
	return {"match_id": m.id, "queue": String(m.queue.id) if m.queue != null else "custom", "ended_at": int(now()),
		"duration_s": int(duration), "winner": winner, "voided": voided, "bots": _has_bots(m), "players": players}


## Removes a match from every index.
func _end(m: Match) -> void:
	_matches.erase(m.id)
	for id in _humans(m):
		if _account_match.get(id) == m:
			_account_match.erase(id)


# --- custom games ---------------------------------------------------------------------

func _custom(peer: int, who: Dictionary, r: Dictionary, t: float) -> void:
	var me := str(who.id)
	var op: int = r.op
	var code := MatchmakingCodec.OK
	match op:
		MatchmakingCodec.OP_CUSTOM_CREATE:
			if _custom_of.has(me) or _account_match.has(me) or matchmaker.ticket_of(me) != 0:
				code = MatchmakingCodec.E_ALREADY
			elif int(r.map) >= MatchmakingCodec.CUSTOM_MAPS.size() or not (int(r.mode) in [MatchmakingCodec.PM_CUSTOM,
					MatchmakingCodec.PM_ALL_RANDOM]) or int(r.team_size) < 1 or int(r.team_size) > 5:
				code = MatchmakingCodec.E_BAD_REQUEST
			else:
				_customs[me] = {"host": me, "map": int(r.map), "mode": int(r.mode), "bots": int(r.bots) != 0,
					"team_size": int(r.team_size), "members": [{"id": me, "team": 0, "hero": 0}], "invites": {}}
				_custom_of[me] = me
				_log("[front] custom lobby opened (%s, %dv%d)" % [MatchmakingCodec.CUSTOM_MAPS[int(r.map)],
					int(r.team_size), int(r.team_size)])
				_send_custom(_customs[me])
		MatchmakingCodec.OP_CUSTOM_INVITE:
			var c: Dictionary = _customs.get(me, {})
			if c.is_empty():
				code = MatchmakingCodec.E_NOT_ALLOWED
			else:
				var targets: Array = []
				if LobbyCodec.is_none_id(str(r.id)):
					targets = accounts.parties.mates_of(me) if accounts.parties != null else []
				elif _is_friend(me, str(r.id)) or (accounts.parties != null and accounts.parties.mates_of(me).has(str(r.id))):
					targets = [str(r.id)]
				if targets.is_empty():
					code = MatchmakingCodec.E_NOT_FOUND
				for id in targets:
					c.invites[id] = true
					_send(str(id), MatchmakingCodec.EV_CUSTOM_STATE, MatchmakingCodec.OK, _custom_fields(c, str(id)))
		MatchmakingCodec.OP_CUSTOM_JOIN:
			var c: Dictionary = _customs.get(str(r.host), {})
			if c.is_empty() or not c.invites.has(me):
				code = MatchmakingCodec.E_NOT_FOUND
			elif _custom_of.has(me) or _account_match.has(me) or matchmaker.ticket_of(me) != 0:
				code = MatchmakingCodec.E_ALREADY
			elif (c.members as Array).size() >= 2 * int(c.team_size):
				code = MatchmakingCodec.E_NOT_ALLOWED
			else:
				var n0 := _custom_team_count(c, 0)
				var team := 0 if n0 <= _custom_team_count(c, 1) and n0 < int(c.team_size) else 1
				(c.members as Array).append({"id": me, "team": team, "hero": 0})
				c.invites.erase(me)
				_custom_of[me] = c.host
				_send_custom(c)
		MatchmakingCodec.OP_CUSTOM_LEAVE:
			_custom_leave(me)
		MatchmakingCodec.OP_CUSTOM_TEAM:
			var c := _custom_lobby_of(me)
			var mem := _custom_member(c, me)
			if mem.is_empty() or int(r.team) > 1 or _custom_team_count(c, int(r.team)) >= int(c.team_size):
				code = MatchmakingCodec.E_NOT_ALLOWED
			else:
				mem.team = int(r.team)
				mem.hero = 0
				_send_custom(c)
		MatchmakingCodec.OP_CUSTOM_PICK:
			var c := _custom_lobby_of(me)
			var mem := _custom_member(c, me)
			var h := int(r.hero)
			if mem.is_empty() or h < 1 or h > content.count(ContentDB.HERO):
				code = MatchmakingCodec.E_NOT_ALLOWED
			else:
				for o: Dictionary in c.members:
					if o.id != me and o.team == mem.team and int(o.hero) == h:
						code = MatchmakingCodec.E_TAKEN
				if code == MatchmakingCodec.OK:
					mem.hero = h
					_send_custom(c)
		MatchmakingCodec.OP_CUSTOM_START:
			var c: Dictionary = _customs.get(me, {})
			if c.is_empty():
				code = MatchmakingCodec.E_NOT_ALLOWED
			else:
				_custom_start(c, t)
	_ack(peer, op, code)


func _custom_start(c: Dictionary, t: float) -> void:
	var m := Match.new()
	m.id = JoinTicket.new_match_id()
	m.custom = true
	m.custom_mode = int(c.mode)
	m.map = MAP_NAMES.get(MatchmakingCodec.CUSTOM_MAPS[int(c.map)], "front")
	m.since = t
	var rng := RandomNumberGenerator.new()
	rng.seed = m.id.hash()
	var bot_n := 0
	for side in 2:
		var taken := {}
		var team: Array = (c.members as Array).filter(func(x: Dictionary) -> bool: return int(x.team) == side)
		for mem: Dictionary in team:
			var hero := _hero_id(int(mem.hero)) if int(c.mode) == MatchmakingCodec.PM_CUSTOM else &""
			if hero == &"" or taken.has(hero):
				hero = _random_free(taken, rng)
			taken[hero] = true
			var ident := _identity_of(str(mem.id))
			m.seats.append({"id": str(mem.id), "team": side, "lane": &"", "bot": false,
				"name": str(ident.get("name", "")), "accent": int(ident.get("accent", 0)), "hero": hero})
		if bool(c.bots):
			for i in range(team.size(), int(c.team_size)):
				bot_n += 1
				var hero := _random_free(taken, rng)
				taken[hero] = true
				m.seats.append({"id": "%s%d" % [MatchmakingRulesDef.BOT_PREFIX, bot_n], "team": side, "lane": &"",
					"bot": true, "name": "", "accent": 0, "hero": hero})
	c.phase = MatchmakingCodec.CP_STARTING
	_send_custom(c)
	_close_custom(c, false)
	_matches[m.id] = m
	for id in _humans(m):
		_account_match[id] = m
	_log("[front] custom match %s starting (%d player(s), %d bot(s))" % [m.id, _humans(m).size(), bot_n])
	_allocate(m, t)


func _custom_leave(me: String) -> void:
	var c := _custom_lobby_of(me)
	if c.is_empty():
		return
	if c.host == me:
		c.phase = MatchmakingCodec.CP_CLOSED
		_send_custom(c)
		_close_custom(c, true)
		return
	c.members = (c.members as Array).filter(func(x: Dictionary) -> bool: return x.id != me)
	_custom_of.erase(me)
	_send_custom(c)


func _close_custom(c: Dictionary, _closed: bool) -> void:
	for mem: Dictionary in c.members:
		_custom_of.erase(str(mem.id))
	_customs.erase(c.host)


func _custom_lobby_of(id: String) -> Dictionary:
	return _customs.get(_custom_of.get(id, ""), {})


static func _custom_member(c: Dictionary, id: String) -> Dictionary:
	for mem: Dictionary in c.get("members", []):
		if mem.id == id:
			return mem
	return {}


static func _custom_team_count(c: Dictionary, team: int) -> int:
	return (c.members as Array).filter(func(x: Dictionary) -> bool: return int(x.team) == team).size()


func _custom_fields(c: Dictionary, viewer: String) -> Dictionary:
	var members: Array = []
	for mem: Dictionary in c.members:
		var ident := _identity_of(str(mem.id))
		var flags := (MatchmakingCodec.MEM_HOST if mem.id == c.host else 0) | (MatchmakingCodec.MEM_YOU if mem.id == viewer else 0)
		members.append({"id": mem.id, "team": mem.team, "hero": mem.hero, "flags": flags,
			"name": str(ident.get("name", ""))})
	return {"host": c.host, "phase": int(c.get("phase", MatchmakingCodec.CP_OPEN)), "map": c.map, "mode": c.mode,
		"bots": 1 if c.bots else 0, "team_size": c.team_size, "members": members}


func _send_custom(c: Dictionary) -> void:
	for mem: Dictionary in c.members:
		_send(str(mem.id), MatchmakingCodec.EV_CUSTOM_STATE, MatchmakingCodec.OK, _custom_fields(c, str(mem.id)))


func _is_friend(me: String, other: String) -> bool:
	if accounts.store == null:
		return false
	return (accounts.store.get_by_id(me).get("friends", []) as Array).has(other)


func _random_free(taken: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var free: Array = heroes.filter(func(h: StringName) -> bool: return not taken.has(h))
	if free.is_empty():
		return heroes[rng.randi_range(0, heroes.size() - 1)] if not heroes.is_empty() else &""
	return free[rng.randi_range(0, free.size() - 1)]


# --- connections, queue status ---------------------------------------------------------

## A connection closed. Queued players get a grace (rules.pick_disconnect_grace_s)
## to come back; a custom lobby member leaves the lobby at once.
func on_peer_left(peer: int) -> void:
	var who := accounts.identity(peer)
	if who.is_empty():
		return
	_custom_leave(str(who.id))


func _refresh_queued(t: float) -> void:
	for id: String in _queued.keys():
		if not _queued.has(id):
			continue
		if matchmaker.ticket_of(id) == 0:
			_queued.erase(id)
			continue
		var mates: Array = _queued[id]
		var now_party: Array = [id]
		if accounts.parties != null and str(accounts.parties.state_of(id, t).party) != "":
			now_party = accounts.parties.state_of(id, t).members
		var changed := now_party.size() != mates.size() or now_party.any(func(x: String) -> bool: return not mates.has(x))
		var away := false
		if _peer_of(id) < 0:
			_away_since.get_or_add(id, t)
			away = t - float(_away_since[id]) >= rules.pick_disconnect_grace_s
		else:
			_away_since.erase(id)
		if changed or away:
			matchmaker.leave(id)
			for x in mates:
				_queued.erase(str(x))
				_away_since.erase(str(x))
				_send_status(str(x))
			_log("[front] a party left the queue (%s)" % ("party changed" if changed else "disconnected"))
			continue
		_send_status(id)


func _send_status(id: String, code: int = MatchmakingCodec.OK, locked_s: float = 0.0) -> void:
	var st := MatchmakingCodec.QS_IDLE
	var qi := 255
	var waited := 0.0
	var est := 0.0
	var players := 0
	var tid := matchmaker.ticket_of(id)
	var m: Match = _account_match.get(id)
	if m != null:
		st = [MatchmakingCodec.QS_READY_CHECK, MatchmakingCodec.QS_PICKING, MatchmakingCodec.QS_PICKING,
			MatchmakingCodec.QS_IN_MATCH][m.state]
		qi = _queue_index(m)
	elif tid != 0:
		var tk := matchmaker.ticket(tid)
		st = MatchmakingCodec.QS_QUEUED
		qi = MatchmakingClient.queue_index(tk.queue)
		waited = now() - float(tk.enqueued_at)
		var info := matchmaker.queue_info(tk.queue)
		est = float(info.estimated_wait_s)
		players = int(info.players)
	if locked_s > 0.0:
		st = MatchmakingCodec.QS_LOCKED
	_send(id, MatchmakingCodec.EV_QUEUE_STATUS, code, {"state": st, "queue": qi, "waited": int(waited),
		"estimate": int(est), "players": players, "locked": ceili(maxf(0.0, locked_s))})


func _send_found(m: Match, t: float) -> void:
	var humans := _humans(m)
	for id in humans:
		_send(id, MatchmakingCodec.EV_MATCH_FOUND, MatchmakingCodec.OK, {"match": m.id, "queue": _queue_index(m),
			"seconds": ceili(maxf(0.0, m.rc.deadline - t)), "humans": humans.size(),
			"accepted": m.rc.accepted_count(), "you_accepted": 1 if m.rc._accepted.has(id) else 0})


func _send_lockout(id: String, seconds: float, ranked: bool, reason: int) -> void:
	if seconds <= 0.0:
		return
	_send(id, MatchmakingCodec.EV_LOCKOUT, MatchmakingCodec.OK, {"seconds": ceili(seconds), "ranked": 1 if ranked else 0,
		"reason": reason})


## RANKED_INFO for `id` (ranked track: visible number + medal, or calibrating).
func send_ranked_info(id: String) -> void:
	var d := ratings.ranked_display(id)
	var medal: Dictionary = d.medal
	_send(id, MatchmakingCodec.EV_RANKED_INFO, MatchmakingCodec.OK, {"tracks": [{
		"track": MatchmakingCodec.TRACKS.find(RatingService.TRACK_RANKED),
		"rating": MatchmakingCodec.RATING_HIDDEN if int(d.rating) < 0 else int(d.rating),
		"games_left": int(d.games_left), "band": int(medal.get("band", 255)),
		"division": int(medal.get("division", 0))}]})


# --- account deletion, lockout persistence ------------------------------------------

## Account deletion cascade: ratings, reports, match history, lockouts.
func erase_account(id: String) -> void:
	if ratings != null:
		ratings.store.erase_account(id)
	if reports != null:
		reports.erase_account(id)
	if history != null:
		history.erase_account(id)
	lockouts.erase(id)
	_last_strike.erase(id)
	_save_lockouts()
	matchmaker.leave(id)
	_queued.erase(id)
	_custom_leave(id)


func _strike(id: String, t: float) -> void:
	_last_strike[id] = t


func _save_lockouts() -> void:
	if mm_dir == "":
		return
	var state := {}
	var raw := lockouts.to_dict()
	for id in raw:
		var per := {}
		for k in raw[id]:
			per[str(k)] = raw[id][k]
		state[id] = per
	JsonFileStore.save_json(mm_dir, LOCKOUT_FILE, {"v": 1, "state": state, "last_strike": _last_strike})


func _load_lockouts() -> void:
	if mm_dir == "":
		return
	var data: Variant = JsonFileStore.load_json(mm_dir, LOCKOUT_FILE)
	if not data is Dictionary:
		return
	var state := {}
	var raw: Variant = data.get("state", {})
	if raw is Dictionary:
		for id in raw:
			if not (raw[id] is Dictionary) or not RatingStore.is_valid_id(str(id)):
				continue
			var per := {}
			for k in raw[id]:
				var e: Variant = raw[id][k]
				if str(k).is_valid_int() and e is Dictionary:
					per[int(k)] = {"strikes": int(e.get("strikes", 0)), "since": float(e.get("since", 0.0)),
						"until": float(e.get("until", 0.0))}
			state[str(id)] = per
	lockouts.from_dict(state)
	var last: Variant = data.get("last_strike", {})
	if last is Dictionary:
		for id in last:
			_last_strike[str(id)] = float(last[id])


# --- helpers ---------------------------------------------------------------------------

func _send(id: String, op: int, code: int, fields: Dictionary = {}) -> bool:
	var peer := _peer_of(id)
	if peer < 0:
		return false
	transport.send(peer, Transport.CH_CONTROL, MatchmakingCodec.encode_event(op, code, fields))
	return true


func _ack(peer: int, req: int, code: int) -> void:
	transport.send(peer, Transport.CH_CONTROL, MatchmakingCodec.encode_event(MatchmakingCodec.EV_ACK, code,
		{"req": req}))


func _peer_of(id: String) -> int:
	for p in accounts.peers:
		if str(accounts.peers[p].get("id", "")) == id:
			return int(p)
	return -1


func _identity_of(id: String) -> Dictionary:
	var p := _peer_of(id)
	return accounts.identity(p) if p >= 0 else {}


func _rating_of(id: String, track: StringName) -> float:
	if String(track) == "":
		return rules.rating_initial
	return float(ratings.entry(id, track).rating)


func _humans(m: Match) -> Array:
	var out: Array = []
	for s in m.seats:
		if not s.bot:
			out.append(s.id)
	return out


func _has_bots(m: Match) -> bool:
	return m.seats.any(func(s: Dictionary) -> bool: return s.bot)


func _team_size(m: Match) -> int:
	var n := [0, 0]
	for s in m.seats:
		n[s.team] += 1
	return maxi(n[0], n[1])


func _team_of(m: Match, id: String) -> int:
	for s in m.seats:
		if s.id == id:
			return int(s.team)
	return 0


func _seat_index(m: Match, id: String) -> int:
	for i in m.seats.size():
		if m.seats[i].id == id:
			return i
	return 0


func _queue_index(m: Match) -> int:
	return MatchmakingClient.queue_index(m.queue.id) if m.queue != null else MatchmakingClient.queue_index(&"custom")


func _hero_index(hero: StringName) -> int:
	return content.index_of(ContentDB.HERO, hero) if hero != &"" else 0


func _hero_id(index: int) -> StringName:
	if index < 1 or index > content.count(ContentDB.HERO):
		return &""
	return content.id_at(ContentDB.HERO, index)


func _log(line: String) -> void:
	log_fn.call(line)
