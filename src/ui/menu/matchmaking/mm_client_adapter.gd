class_name MmClientAdapter
extends RefCounted
## W17B-UI: puts the network MatchmakingClient (W17B-SRV, protocol 17,
## docs/architecture/matchmaking-client-api.md) behind the screen-facing
## interface of MatchmakingFakeClient: the same signals with normalised
## Dictionaries (hero ids instead of HERO indexes, lane / queue ids instead
## of bytes, "seconds left" instead of local deadlines, string error keys).
## The screens only ever see that one interface, so they are tested with the
## fake and run on the network with this adapter.
##
## Example (main menu, after login):
##   var mm := MmClientAdapter.new(lobby_client.matchmaking, lobby_client)
##   flow.client = mm

signal queue_changed(status: Dictionary)
signal match_found(info: Dictionary)
signal ready_result(result: Dictionary)
signal pick_state(state: Dictionary)
signal match_assigned(info: Dictionary)
signal connection_lost()
signal remake_state(state: Dictionary)
signal post_match(result: Dictionary)
signal profile_received(profile: Dictionary)
signal party_changed(party: Dictionary)
signal custom_changed(lobby: Dictionary)
signal feedback_result(result: Dictionary)
## A request failed: a HUD_MM_ERR_* key.
signal failed(key: String)

const QS := {0: &"idle", 1: &"queued", 2: &"busy", 3: &"busy", 4: &"busy", 5: &"locked"}
const RR := {0: &"go", 1: &"requeued", 2: &"removed", 3: &"locked", 4: &"voided"}

var mm: MatchmakingClient
## The front connection that feeds `mm` (stepped by step(); null = fed elsewhere).
var lobby: Object
var rules: MatchmakingRulesDef
var _outgoing: Array = []
var _remake_voted: bool = false
var _custom_cfg := {"map": 0, "mode": MatchmakingCodec.PM_CUSTOM, "bots": true, "team_size": 5}


func _init(mm_: MatchmakingClient, lobby_: Object = null, rules_: MatchmakingRulesDef = null) -> void:
	mm = mm_
	lobby = lobby_
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()
	mm.queue_detail.connect(func(d: Dictionary) -> void: queue_changed.emit(status_of(d)))
	mm.lockout.connect(func(d: Dictionary) -> void:
		queue_changed.emit({"state": &"locked", "queue": &"", "waited_s": 0.0, "estimate_s": 0.0, "in_queue": 0,
			"locked_s": float(d.get("seconds", 0)), "err": "HUD_MM_ERR_LOCKED"}))
	mm.ready_check.connect(func(deadline: float) -> void: match_found.emit(found_of(mm.last_ready, deadline - _now())))
	mm.ready_result.connect(func(d: Dictionary) -> void:
		ready_result.emit({"outcome": RR.get(int(d.get("outcome", 0)), &"requeued"), "locked_s": float(d.get("locked", 0)),
			"reason": "HUD_MM_READY_DECLINED" if int(d.get("outcome", 0)) == MatchmakingCodec.RR_LOCKED else "HUD_MM_READY_OTHERS"}))
	mm.draft_state.connect(func(d: Dictionary) -> void: pick_state.emit(draft_of(d, _queue(), rules)))
	mm.aram_state.connect(func(d: Dictionary) -> void: pick_state.emit(aram_of(d, _outgoing)))
	mm.match_assigned.connect(func(host: String, port: int, ticket: String) -> void:
		_outgoing.clear()
		var a := mm.last_assigned
		match_assigned.emit({"match_id": str(a.get("match", "")), "host": host, "port": port, "ticket": ticket,
			"queue": _queue(), "hero": hero_id(int(a.get("hero", 0)))}))
	mm.remake_prompt.connect(func(d: Dictionary) -> void:
		if int(d.get("state", 0)) != MatchmakingCodec.RV_OPEN:
			_remake_voted = false
		remake_state.emit(remake_of(d, _remake_voted)))
	mm.match_result.connect(func(d: Dictionary) -> void: post_match.emit(result_of(d, mm.last_ranked, rules)))
	mm.rating_update.connect(func(d: Dictionary) -> void: profile_received.emit(profile_of(d, rules)))
	mm.custom_state.connect(func(d: Dictionary) -> void: custom_changed.emit(custom_of(d)))
	mm.request_failed.connect(func(_op: int, code: int) -> void: failed.emit(error_key(code)))


# --- requests (MatchmakingFakeClient's interface) -------------------------------

func join_queue(queue_id: StringName, prefs: Array) -> void:
	mm.queue_join(queue_id, prefs if not prefs.is_empty() else [&"fill"])


func leave_queue() -> void:
	mm.queue_leave()


func reply_ready(accept: bool) -> void:
	if accept:
		mm.ready_accept()
	else:
		mm.ready_decline()


func pick(hero: StringName) -> void:
	mm.draft_pick(hero_index(hero))


func reroll() -> void:
	mm.aram_reroll()


func take_bench(hero: StringName) -> void:
	mm.aram_take_bench(hero_index(hero))


func request_swap(seat_id: String) -> void:
	_outgoing.append(seat_id)
	mm.aram_swap_request(seat_index(seat_id))


func answer_swap(from: String, accept: bool) -> void:
	if accept:
		mm.aram_swap_accept(seat_index(from))
	# A decline is local: the request expires on the server.


## Leaving the pick phase (a dodge: the server applies lockout / penalty).
func dodge() -> void:
	mm.queue_leave()


func remake_vote(yes: bool) -> void:
	_remake_voted = true
	mm.remake_vote(yes)


func reconnect() -> void:
	mm.rejoin()


func honour(match_id: Variant, target: String) -> void:
	mm.honour(target, str(match_id))
	feedback_result.emit({"op": &"honour", "target": target, "ok": true})


func report(match_id: Variant, target: String, category: StringName) -> void:
	mm.report(target, rules.report_categories.find(category), str(match_id))
	feedback_result.emit({"op": &"report", "target": target, "ok": true})


func request_profile() -> void:
	mm.request_ranked_info()


func custom_open() -> void:
	mm.custom_create(_custom_cfg.map, _custom_cfg.mode, _custom_cfg.bots, _custom_cfg.team_size)


## `map_id` in MatchmakingCodec.CUSTOM_MAPS, `mode` &"custom" / &"all_random".
func custom_set(map_id: StringName, mode: StringName, bots: bool, team_size: int = 5) -> void:
	_custom_cfg = {"map": maxi(0, MatchmakingCodec.CUSTOM_MAPS.find(map_id)),
		"mode": MatchmakingCodec.PM_ALL_RANDOM if mode == &"all_random" else MatchmakingCodec.PM_CUSTOM,
		"bots": bots, "team_size": clampi(team_size, 1, 5)}
	custom_open()


func custom_invite(id: String) -> void:
	mm.custom_invite(id)


func custom_start() -> void:
	mm.custom_start()


func step(_delta: float) -> void:
	if lobby != null and lobby.has_method("step"):
		lobby.call("step")


# --- conversions (static, unit tested) --------------------------------------------

static func hero_id(index: int) -> StringName:
	var e := HeroCatalog.find_index(index)
	return StringName(MmView.HERO_PREFIX + str(e.stem)) if not e.is_empty() else &""


static func hero_index(hero: StringName) -> int:
	return MmView.hero_index(hero)


static func seat_index(seat_id: String) -> int:
	return seat_id.trim_prefix("seat").to_int()


static func queue_id(index: int) -> StringName:
	return MatchmakingClient.QUEUE_IDS[index] if index >= 0 and index < MatchmakingClient.QUEUE_IDS.size() else &""


static func lane_id(b: int) -> StringName:
	return MatchmakingCodec.LANES[b] if b >= 0 and b < MatchmakingCodec.LANES.size() else &""


static func error_key(code: int) -> String:
	match code:
		MatchmakingCodec.E_PARTY_SIZE:
			return "HUD_MM_ERR_PARTY_SIZE"
		MatchmakingCodec.E_PARTY_GAP:
			return "HUD_MM_ERR_PARTY_GAP"
		MatchmakingCodec.E_LOCKED:
			return "HUD_MM_ERR_LOCKED"
		MatchmakingCodec.E_NOT_LEADER:
			return "HUD_MM_LEADER_ONLY"
		MatchmakingCodec.E_GUEST:
			return "HUD_MM_ERR_GUEST"
		MatchmakingCodec.E_IN_MATCH:
			return "HUD_MM_ERR_IN_MATCH"
		MatchmakingCodec.E_TAKEN:
			return "HUD_MM_TAKEN_BY_TEAM"
		MatchmakingCodec.E_NO_REROLLS:
			return "HUD_MM_ERR_NO_REROLLS"
		MatchmakingCodec.E_NOT_FOUND:
			return "HUD_MM_ERR_NOT_FOUND"
		MatchmakingCodec.E_BUSY, MatchmakingCodec.E_DRAINING:
			return "HUD_MM_ERR_BUSY"
		MatchmakingCodec.E_TOO_LATE:
			return "HUD_MM_ERR_TOO_LATE"
	return "HUD_MM_ERR_GENERIC"


static func status_of(d: Dictionary) -> Dictionary:
	var st: StringName = QS.get(int(d.get("state", 0)), &"idle")
	return {"state": st, "queue": queue_id(int(d.get("queue", 255))), "waited_s": float(d.get("waited", 0)),
		"estimate_s": float(d.get("estimate", 0)), "in_queue": int(d.get("players", 0)),
		"locked_s": float(d.get("locked", 0)),
		"err": "" if int(d.get("code", 0)) == MatchmakingCodec.OK else error_key(int(d.get("code", 0)))}


static func found_of(d: Dictionary, left: float) -> Dictionary:
	return {"match_id": str(d.get("match", "")), "queue": queue_id(int(d.get("queue", 0))),
		"deadline_s": maxf(0.0, left), "humans": int(d.get("humans", 10)), "accepted": int(d.get("accepted", 0)),
		"me_accepted": int(d.get("you_accepted", 0)) != 0}


static func _seats(d: Dictionary) -> Array:
	var out: Array = []
	var raw: Array = d.get("seats", [])
	for i in raw.size():
		var s: Dictionary = raw[i]
		var f := int(s.get("flags", 0))
		out.append({"id": "seat%d" % i, "name": str(s.get("name", "")), "team": int(s.get("team", 0)),
			"lane": lane_id(int(s.get("lane", 255))), "hero": hero_id(int(s.get("hero", 0))),
			"bot": f & MatchmakingCodec.SEAT_BOT != 0, "auto": f & MatchmakingCodec.SEAT_AUTO != 0,
			"picking": f & MatchmakingCodec.SEAT_PICKING != 0})
	return out


static func draft_of(d: Dictionary, queue: StringName, rules: MatchmakingRulesDef) -> Dictionary:
	var seats := _seats(d)
	var you := int(d.get("you", 0))
	var turn := int(d.get("turn", 0))
	var turn_team := int(d.get("turn_team", 0))
	return {"mode": &"draft", "queue": queue, "ranked": queue == MmView.Q_RANKED, "me": "seat%d" % you,
		"my_team": int(seats[you].team) if you < seats.size() else 0, "turn": turn, "turn_team": turn_team,
		"order": rules.draft_order, "first_team": posmod(turn_team - turn, 2), "deadline_s": float(d.get("seconds", 0)),
		"turn_s": rules.pick_turn_s, "done": turn >= rules.draft_order.size(), "seats": seats}


static func aram_of(d: Dictionary, outgoing: Array) -> Dictionary:
	var seats := _seats(d)
	var you := int(d.get("you", 0))
	var bench: Array = []
	for h in d.get("bench", []):
		bench.append(hero_id(int(h)))
	var reqs: Array = []
	for i in d.get("swap_from", []):
		var s: Dictionary = seats[int(i)] if int(i) < seats.size() else {}
		reqs.append({"from": "seat%d" % int(i), "name": str(s.get("name", "")), "hero": s.get("hero", &"")})
	return {"mode": &"all_random", "queue": MmView.Q_ARAM, "me": "seat%d" % you,
		"my_team": int(seats[you].team) if you < seats.size() else 0, "open": int(d.get("seconds", 0)) > 0,
		"deadline_s": float(d.get("seconds", 0)), "turn_s": 45.0, "rerolls_left": int(d.get("rerolls", 0)),
		"bench": bench, "seats": seats, "swap_requests": reqs, "outgoing": outgoing.duplicate()}


static func remake_of(d: Dictionary, voted: bool) -> Dictionary:
	var st := int(d.get("state", 0))
	return {"eligible": true, "open": st == MatchmakingCodec.RV_OPEN, "yes": int(d.get("yes", 0)), "no": 0,
		"needed": int(d.get("needed", 0)), "deadline_s": float(d.get("seconds", 0)), "voted": voted,
		"outcome": &"passed" if st == MatchmakingCodec.RV_PASSED else (&"failed" if st == MatchmakingCodec.RV_FAILED else &"")}


static func result_of(d: Dictionary, ranked: Dictionary, rules: MatchmakingRulesDef) -> Dictionary:
	var players: Array = []
	var stats := {}
	for p: Dictionary in d.get("players", []):
		var f := int(p.get("flags", 0))
		var me := f & MatchmakingCodec.MEM_YOU != 0
		players.append({"id": str(p.get("id", "")), "name": str(p.get("name", "")), "team": int(p.get("team", 0)),
			"hero": hero_id(int(p.get("hero", 0))), "kills": int(p.get("kills", 0)), "deaths": int(p.get("deaths", 0)),
			"assists": int(p.get("assists", 0)), "me": me, "bot": f & MatchmakingCodec.MEM_BOT != 0})
		if me:
			stats = {"kills": int(p.kills), "deaths": int(p.deaths), "assists": int(p.assists)}
	var queue := queue_id(int(d.get("queue", 0)))
	var rating := {}
	if bool(d.get("rated", 0)) and queue == MmView.Q_RANKED:
		var track := _track(ranked, &"ranked")
		var delta := float(d.get("delta", 0.0))
		var after := float(track.get("rating", -1))
		var svc := RatingService.new(MemoryRatingStore.new(), rules)
		rating = {"delta": roundi(delta), "calibrating": after < 0.0,
			"games_played": rules.calibration_games - int(track.get("games_left", 0)), "games_needed": rules.calibration_games}
		if after >= 0.0:
			rating.merge({"before": roundi(after - delta), "after": roundi(after), "medal_before": svc.medal_for(after - delta),
				"medal_after": svc.medal_for(after), "progress": MmView.medal_progress(after, rules.medal_division_span, rules.medal_bands)})
	return {"match_id": str(d.get("match", "")), "queue": queue, "won": bool(d.get("won", 0)),
		"voided": bool(d.get("voided", 0)), "duration_s": int(d.get("duration", 0)), "stats": stats,
		"rating": rating, "players": players}


static func _track(info: Dictionary, id: StringName) -> Dictionary:
	for t: Dictionary in info.get("tracks", []):
		if StringName(t.get("track_id", &"")) == id:
			return t
	return {}


static func profile_of(d: Dictionary, rules: MatchmakingRulesDef) -> Dictionary:
	var tracks := {}
	var svc := RatingService.new(MemoryRatingStore.new(), rules)
	for t: Dictionary in d.get("tracks", []):
		var r := int(t.get("rating", -1))
		var e := {"calibrating": r < 0, "games_left": int(t.get("games_left", 0)), "rating": r,
			"medal": {} if r < 0 else svc.medal_for(r), "progress": 0.0 if r < 0 else MmView.medal_progress(r, rules.medal_division_span, rules.medal_bands)}
		tracks[StringName(t.get("track_id", &""))] = e
	return {"calibration_games": rules.calibration_games, "tracks": tracks, "history": []}


static func custom_of(d: Dictionary) -> Dictionary:
	var members: Array = []
	var me := ""
	for m: Dictionary in d.get("members", []):
		var f := int(m.get("flags", 0))
		members.append({"id": str(m.get("id", "")), "name": str(m.get("name", "")), "team": int(m.get("team", 0)),
			"bot": f & MatchmakingCodec.MEM_BOT != 0})
		if f & MatchmakingCodec.MEM_YOU != 0:
			me = str(m.get("id", ""))
	var mi := int(d.get("map", 0))
	return {"host": str(d.get("host", "")), "me": me,
		"map": MatchmakingCodec.CUSTOM_MAPS[mi] if mi < MatchmakingCodec.CUSTOM_MAPS.size() else &"",
		"mode": &"all_random" if int(d.get("mode", 0)) == MatchmakingCodec.PM_ALL_RANDOM else &"custom",
		"bots": int(d.get("bots", 0)) != 0, "team_size": int(d.get("team_size", 5)),
		"maps": MatchmakingCodec.CUSTOM_MAPS.duplicate(), "modes": [&"custom", &"all_random"],
		"members": members, "invited": [], "starting": int(d.get("phase", 0)) == MatchmakingCodec.CP_STARTING}


func _queue() -> StringName:
	return queue_id(int(mm.last_ready.get("queue", mm.last_status.get("queue", 0))))


func _now() -> float:
	return float(mm.clock.call())
