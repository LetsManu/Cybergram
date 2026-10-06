class_name Matchmaker
extends RefCounted
## Queues and match forming (W17-MM, design/gdd/matchmaking.md §3). Pure
## logic: no network, no clock, no storage. The front (phase B) feeds it
## parties with their ratings for the queue's track, calls tick(now), runs
## the ready check and hands the result back.
##
## A ticket is one party (1..party_max members) in one queue:
##   {id, queue, members: [{id, rating, lanes}], size, rating (mean),
##    enqueued_at, priority}
## A proposal is a found match:
##   {match_id, queue, team_size, teams: [[seat], [seat]], tickets: [ticket],
##    bots: int, rated: bool, created_at}
##   seat = {id, rating, lane, ticket (-1 for bots), bot: bool}
##
## Forming (per queue, every tick):
## 1. Tickets sorted: priority first (re-queued after someone else's
##    decline), then oldest, then lowest id. Each in turn is the anchor.
## 2. Search window of the anchor: min(max, base + growth * waited).
##    Candidates: tickets whose mean rating is within the window.
## 3. Selection fills 2 * team_size players greedily, keeping a split into
##    two teams possible. If the anchor is a premade (2+), candidates of a
##    similar party size are tried first (premades meet premades where
##    possible); otherwise, or if that fails, oldest first.
## 4. Split: every assignment of tickets to two full teams is scored
##      |sum A - sum B| (summed rating)
##      + premade_mismatch_weight * premade mismatch (sorted party sizes)
##      + lane_mismatch_weight * unmet lane-preference steps
##    and the lowest wins (ties: the first found, deterministic).
## 5. Bot fill (Normal, 3v3; never ranked): when the anchor has waited
##    bot_fill_delay_s and no full match exists, the in-window tickets that
##    fit are split as evenly as possible and the rest are labelled bots
##    (rating bot_rating). Such a match is unrated unless rate_bot_matches.
## Ranked parties: highest minus lowest member rating <= ranked_party_gap_max.

enum Err { OK, E_QUEUE, E_PARTY_SIZE, E_PARTY_GAP, E_LOCKED, E_ALREADY, E_LANES }

var rules: MatchmakingRulesDef
var lockouts: LockoutTracker
var _tickets: Dictionary = {}       # ticket id -> ticket
var _by_account: Dictionary = {}    # account id -> ticket id (queued)
var _held: Dictionary = {}          # account id -> match id (in a proposal)
var _wait_samples: Dictionary = {}  # queue id -> Array[float]
var _next_ticket: int = 1
var _next_match: int = 1


func _init(rules_: MatchmakingRulesDef = null, lockouts_: LockoutTracker = null) -> void:
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()
	lockouts = lockouts_ if lockouts_ != null else LockoutTracker.new(rules)


## Queues a party. `members`: [{id: String, rating: float, lanes: Array}]
## (lanes: [primary, secondary] or [&"fill"]; ignored without lane slots).
## Returns {err: Err, ticket: int, locked_until: float}.
func enqueue(queue_id: StringName, members: Array, now: float) -> Dictionary:
	var q := rules.queue(queue_id)
	if q == null or not q.matchmade:
		return _err(Err.E_QUEUE)
	if members.is_empty() or members.size() > mini(rules.party_max, q.team_size):
		return _err(Err.E_PARTY_SIZE)
	var lo := INF
	var hi := -INF
	var until := 0.0
	for m in members:
		var id := String(m.get("id", ""))
		if id == "" or MatchmakingRulesDef.is_bot(id) or _by_account.has(id) or _held.has(id):
			return _err(Err.E_ALREADY)
		if not q.lane_slots.is_empty() and not LaneAssigner.valid_prefs(m.get("lanes", [])):
			return _err(Err.E_LANES)
		lo = minf(lo, float(m.get("rating", 0.0)))
		hi = maxf(hi, float(m.get("rating", 0.0)))
		until = maxf(until, lockouts.locked_until(id, now, q.ranked))
	if until > 0.0:
		var e := _err(Err.E_LOCKED)
		e.locked_until = until
		return e
	if q.ranked and hi - lo > rules.ranked_party_gap_max:
		return _err(Err.E_PARTY_GAP)
	var t := _make_ticket(queue_id, members, now, false)
	return {"err": Err.OK, "ticket": t.id, "locked_until": 0.0}


## Removes the party of `account_id` from its queue. True if it was queued.
func leave(account_id: String) -> bool:
	var tid: int = _by_account.get(account_id, 0)
	if tid == 0:
		return false
	_drop_ticket(tid)
	return true


## Ticket id of a queued account, or 0.
func ticket_of(account_id: String) -> int:
	return _by_account.get(account_id, 0)


## A copy of a queued ticket, or {}.
func ticket(ticket_id: int) -> Dictionary:
	return (_tickets.get(ticket_id, {}) as Dictionary).duplicate(true)


## Puts a party back with priority and its original queue time (a match
## was voided before it could be played). `members` as in enqueue().
## Returns the ticket id, or 0 when a member is already queued or held.
func requeue(queue_id: StringName, members: Array, enqueued_at: float) -> int:
	if rules.queue(queue_id) == null or members.is_empty():
		return 0
	for m in members:
		var id := String(m.get("id", ""))
		if id == "" or _by_account.has(id) or _held.has(id):
			return 0
	return int(_make_ticket(queue_id, members, enqueued_at, true).id)


## Forms every match possible now. Tickets in a proposal leave the queue
## until resolve_ready_check() or confirm().
func tick(now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in rules.queues:
		if not q.matchmade:
			continue
		var formed := true
		while formed:
			formed = false
			for anchor in _sorted(q.id):
				var p := _form(q, anchor, now)
				if not p.is_empty():
					out.append(p)
					formed = true
					break
	return out


## Players and parties waiting, and the estimated wait for a new entry.
func queue_info(queue_id: StringName) -> Dictionary:
	var players := 0
	var parties := 0
	for t in _tickets.values():
		if t.queue == queue_id:
			players += int(t.size)
			parties += 1
	return {"players": players, "parties": parties, "estimated_wait_s": estimated_wait_s(queue_id)}


## Mean wait of the last wait_estimate_samples matches formed in the queue,
## or default_wait_estimate_s with no history.
func estimated_wait_s(queue_id: StringName) -> float:
	var s: Array = _wait_samples.get(queue_id, [])
	if s.is_empty():
		return rules.default_wait_estimate_s
	var sum := 0.0
	for x in s:
		sum += float(x)
	return sum / s.size()


## Human account ids of a proposal (the ready-check participants).
static func human_ids(proposal: Dictionary) -> Array:
	var out: Array = []
	for team in proposal.teams:
		for seat in team:
			if not seat.bot:
				out.append(seat.id)
	return out


## Everyone accepted: the proposal's players leave the matchmaker.
func confirm(proposal: Dictionary) -> void:
	for id in human_ids(proposal):
		_held.erase(id)


## A ready check (or pick phase) failed. `failed_ids` declined, timed out or
## dodged: each gets a DECLINE strike and lockout; their whole party leaves
## the queue with them. Every other party is re-queued with priority and
## keeps its original queue time. Returns {requeued: [ticket ids],
## removed: [account ids], locked: {account id: seconds}}.
func resolve_ready_check(proposal: Dictionary, failed_ids: Array, now: float,
		kind: LockoutTracker.Kind = LockoutTracker.Kind.DECLINE) -> Dictionary:
	var res := {"requeued": [], "removed": [], "locked": {}}
	for id in human_ids(proposal):
		_held.erase(id)
	for t in proposal.tickets:
		var failed := false
		for m in t.members:
			if failed_ids.has(m.id):
				failed = true
		if failed:
			for m in t.members:
				res.removed.append(m.id)
				if failed_ids.has(m.id):
					res.locked[m.id] = lockouts.record(m.id, kind, now)
		else:
			var nt := _make_ticket(t.queue, t.members, float(t.enqueued_at), true)
			res.requeued.append(nt.id)
	return res


# --- forming -----------------------------------------------------------------

func _form(q: MatchQueueDef, anchor: Dictionary, now: float) -> Dictionary:
	var n := q.team_size
	var window := minf(rules.search_window_max,
		rules.search_window_base + rules.search_window_growth_per_s * maxf(0.0, now - float(anchor.enqueued_at)))
	var cands: Array = []
	for t in _sorted(q.id):
		if t.id != anchor.id and absf(float(t.rating) - float(anchor.rating)) <= window:
			cands.append(t)
	var picked: Array = []
	if int(anchor.size) >= 2:
		var by_size := cands.duplicate()
		by_size.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da := absi(int(a.size) - int(anchor.size))
			var db := absi(int(b.size) - int(anchor.size))
			return da < db if da != db else _before(a, b))
		picked = _select(anchor, by_size, n, true)
	if picked.is_empty():
		picked = _select(anchor, cands, n, true)
	var bots := false
	if picked.is_empty():
		if not q.bots_allowed or q.ranked or now - float(anchor.enqueued_at) < rules.bot_fill_delay_s:
			return {}
		picked = _select(anchor, cands, n, false)
		bots = true
	var split := _best_split(q, picked, bots)
	if split.is_empty():
		return {}
	return _make_proposal(q, picked, split, now)


func _select(anchor: Dictionary, cands: Array, n: int, need_full: bool) -> Array:
	var sel: Array = [anchor]
	var total := int(anchor.size)
	for c in cands:
		if total == 2 * n:
			break
		if total + int(c.size) > 2 * n:
			continue
		var sizes := _sizes(sel)
		sizes.append(int(c.size))
		if _can_split(sizes, n, false):
			sel.append(c)
			total += int(c.size)
	if need_full and (total != 2 * n or not _can_split(_sizes(sel), n, true)):
		return []
	return sel


static func _sizes(tickets: Array) -> Array:
	return tickets.map(func(t: Dictionary) -> int: return int(t.size))


## Can `sizes` go into two teams of at most (exact: exactly) n players?
static func _can_split(sizes: Array, n: int, exact: bool) -> bool:
	var total := 0
	for s in sizes:
		total += int(s)
	var reach := {0: true}
	for s in sizes:
		var next := reach.duplicate()
		for r in reach:
			next[int(r) + int(s)] = true
		reach = next
	for a in reach:
		var b := total - int(a)
		if exact and int(a) == n and b == n:
			return true
		if not exact and int(a) <= n and b <= n:
			return true
	return false


## Best assignment of `picked` to two teams: {mask (bit i = ticket i on
## team B), lanes: [Array, Array]} or {} when none fits.
func _best_split(q: MatchQueueDef, picked: Array, bots: bool) -> Dictionary:
	var n := q.team_size
	var k := picked.size()
	var best := {}
	var best_score := INF
	for mask in range(0, 1 << k, 2):  # ticket 0 (the anchor) always on team A
		var teams := [[], []]
		for i in k:
			teams[(mask >> i) & 1].append(picked[i])
		var sa := _team_size(teams[0])
		var sb := _team_size(teams[1])
		if (bots and (sa > n or sb > n)) or (not bots and (sa != n or sb != n)):
			continue
		var score := absf(_team_sum(teams[0], n) - _team_sum(teams[1], n))
		score += rules.premade_mismatch_weight * _premade_mismatch(teams[0], teams[1])
		var lanes := []
		for t in teams:
			var a := LaneAssigner.assign(_prefs(t), q.lane_slots)
			lanes.append(a.lanes)
			score += rules.lane_mismatch_weight * int(a.misses)
		if score < best_score:
			best_score = score
			best = {"mask": mask, "lanes": lanes, "score": score}
	return best


func _team_sum(team: Array, n: int) -> float:
	var s := 0.0
	var count := 0
	for t in team:
		for m in t.members:
			s += float(m.rating)
			count += 1
	return s + (n - count) * rules.bot_rating


static func _team_size(team: Array) -> int:
	var s := 0
	for t in team:
		s += int(t.size)
	return s


## Sum of |a_i - b_i| over the sorted premade (2+) sizes of both teams.
static func _premade_mismatch(a: Array, b: Array) -> int:
	var pa: Array = _sizes(a).filter(func(s: int) -> bool: return s >= 2)
	var pb: Array = _sizes(b).filter(func(s: int) -> bool: return s >= 2)
	pa.sort()
	pa.reverse()
	pb.sort()
	pb.reverse()
	var out := 0
	for i in maxi(pa.size(), pb.size()):
		out += absi((pa[i] if i < pa.size() else 0) - (pb[i] if i < pb.size() else 0))
	return out


static func _prefs(team: Array) -> Array:
	var out: Array = []
	for t in team:
		for m in t.members:
			out.append(m.get("lanes", []))
	return out


func _make_proposal(q: MatchQueueDef, picked: Array, split: Dictionary, now: float) -> Dictionary:
	var teams := [[], []]
	var bot_count := 0
	for side in 2:
		var li := 0
		for i in picked.size():
			if ((int(split.mask) >> i) & 1) != side:
				continue
			for m in picked[i].members:
				teams[side].append({"id": m.id, "rating": float(m.rating), "lane": split.lanes[side][li],
					"ticket": int(picked[i].id), "bot": false})
				li += 1
		while teams[side].size() < q.team_size:
			bot_count += 1
			var lane: StringName = q.lane_slots[teams[side].size()] if not q.lane_slots.is_empty() else &""
			teams[side].append({"id": "%s%d" % [MatchmakingRulesDef.BOT_PREFIX, bot_count],
				"rating": rules.bot_rating, "lane": lane, "ticket": -1, "bot": true})
	_fill_free_lanes(q, teams)
	var mid := _next_match
	_next_match += 1
	var tickets: Array = []
	for t in picked:
		tickets.append(t.duplicate(true))
		_sample_wait(q.id, now - float(t.enqueued_at))
		_drop_ticket(int(t.id))
		for m in t.members:
			_held[m.id] = mid
	return {"match_id": mid, "queue": q.id, "team_size": q.team_size, "teams": teams, "tickets": tickets,
		"bots": bot_count, "rated": bot_count == 0 or rules.rate_bot_matches, "created_at": now}


## Bots take the lane slots the humans left free.
static func _fill_free_lanes(q: MatchQueueDef, teams: Array) -> void:
	if q.lane_slots.is_empty():
		return
	for team in teams:
		var free: Array = q.lane_slots.duplicate()
		for seat in team:
			if not seat.bot:
				free.erase(seat.lane)
		for seat in team:
			if seat.bot:
				seat.lane = free.pop_front()


func _sample_wait(queue_id: StringName, waited: float) -> void:
	var s: Array = _wait_samples.get_or_add(queue_id, [])
	s.append(waited)
	while s.size() > rules.wait_estimate_samples:
		s.pop_front()


# --- tickets -------------------------------------------------------------------

func _make_ticket(queue_id: StringName, members: Array, enqueued_at: float, priority: bool) -> Dictionary:
	var ms: Array = []
	var sum := 0.0
	for m in members:
		ms.append({"id": String(m.id), "rating": float(m.get("rating", 0.0)), "lanes": Array(m.get("lanes", [])).duplicate()})
		sum += float(m.get("rating", 0.0))
	var t := {"id": _next_ticket, "queue": queue_id, "members": ms, "size": ms.size(),
		"rating": sum / ms.size(), "enqueued_at": enqueued_at, "priority": priority}
	_next_ticket += 1
	_tickets[t.id] = t
	for m in ms:
		_by_account[m.id] = t.id
	return t


func _drop_ticket(tid: int) -> void:
	var t: Dictionary = _tickets.get(tid, {})
	for m in t.get("members", []):
		_by_account.erase(m.id)
	_tickets.erase(tid)


func _sorted(queue_id: StringName) -> Array:
	var out: Array = _tickets.values().filter(func(t: Dictionary) -> bool: return t.queue == queue_id)
	out.sort_custom(_before)
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.priority != b.priority:
		return a.priority
	if float(a.enqueued_at) != float(b.enqueued_at):
		return float(a.enqueued_at) < float(b.enqueued_at)
	return int(a.id) < int(b.id)


static func _err(e: Err) -> Dictionary:
	return {"err": e, "ticket": 0, "locked_until": 0.0}
