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
## W20-WEB public leaderboard opt-in: {public: bool, available: bool}.
signal leaderboard_changed(state: Dictionary)
## A request failed: a HUD_MM_ERR_* key.
signal failed(key: String)
## P1: the server-side player state (MatchmakingClient PHASE fields; phase =
## PhaseMachine.Player). Only the status bar listens; the fake has no such signal.
signal phase_changed(state: Dictionary)
## P2: a party chat line arrived (read party_chat_lines()).
signal party_chat_changed()
## v20: loading percent per seat (pick-state seat order; bots 100).
signal load_progress(loads: Array)
## v20: the hero select team chat changed (select_chat_lines()).
signal select_chat_changed()

const QS := {0: &"idle", 1: &"queued", 2: &"busy", 3: &"busy", 4: &"busy", 5: &"locked"}
const RR := {0: &"go", 1: &"requeued", 2: &"removed", 3: &"locked", 4: &"voided"}

var mm: MatchmakingClient
## The front connection that feeds `mm` (stepped by step(); null = fed elsewhere).
var lobby: Object
var rules: MatchmakingRulesDef
var _outgoing: Array = []
## W21-U2: seconds the pending "join queue" has waited for the server's first status (-1 = none pending).
var _join_wait_s: float = -1.0
var _watch_config: ConnectionWatchConfig = ConnectionWatchConfig.load_default()
var _remake_voted: bool = false
var _custom_cfg := {"map": 0, "mode": MatchmakingCodec.PM_CUSTOM, "bots": true, "team_size": 5}
## P1: last client-side network events for the diagnostics panel.
var events := ClientEventLog.new()
## P2: the account's social state (party, party chat); null = guests / fake.
var social: SocialModel
## P1: seconds online without a PHASE event (-1 = got one); resync once at the limit.
var _phase_wait_s: float = 0.0
## v20: hero select team chat of the current match ([{name, text, mine}]), memory only.
var select_chat: Array = []


func _init(mm_: MatchmakingClient, lobby_: Object = null, rules_: MatchmakingRulesDef = null) -> void:
	mm = mm_
	lobby = lobby_
	rules = rules_ if rules_ != null else MatchmakingRulesDef.load_default()
	mm.phase_changed.connect(func(d: Dictionary) -> void:
		_phase_wait_s = -1.0
		events.add("phase", "%s -> %s" % [PhaseMachine.name_of(PhaseMachine.Kind.PLAYER, int(d.prev)),
			PhaseMachine.name_of(PhaseMachine.Kind.PLAYER, int(d.phase))], {"seq": int(d.seq),
			"snap": int(d.snap), "queue": int(d.queue), "party": int(d.party_size), "locked": int(d.locked)})
		phase_changed.emit(d))
	mm.load_progress.connect(func(l: Array) -> void: load_progress.emit(l))
	mm.ready_result.connect(func(d: Dictionary) -> void:
		events.add("ready", "result", {"outcome": int(d.get("outcome", 0)), "locked": int(d.get("locked", 0))}))
	mm.match_assigned.connect(func(_h: String, port: int, _t: String) -> void:
		events.add("match", "assigned", {"port": port}))  # never the ticket
	mm.match_result.connect(func(d: Dictionary) -> void:
		events.add("match", "result", {"won": int(d.get("won", 0)), "voided": int(d.get("voided", 0))}))
	mm.request_failed.connect(func(op: int, code: int) -> void:
		events.add("error", "request refused", {"op": op, "code": code}))
	mm.lockout.connect(func(d: Dictionary) -> void:
		events.add("lockout", "%ds" % int(d.get("seconds", 0)), {"reason": int(d.get("reason", 0))}))
	mm.queue_detail.connect(func(d: Dictionary) -> void:
		events.add("queue", "status", {"state": int(d.get("state", 0)), "waited": int(d.get("waited", 0)),
			"estimate": int(d.get("estimate", 0)), "code": int(d.get("code", 0))})
		if _join_wait_s >= 0.0:
			print("[net] queue status received after %.1fs (state %d)" % [_join_wait_s, int(d.get("state", 0))])
		_join_wait_s = -1.0
		queue_changed.emit(status_of(d)))
	mm.lockout.connect(func(d: Dictionary) -> void:
		_join_wait_s = -1.0
		queue_changed.emit({"state": &"locked", "queue": &"", "waited_s": 0.0, "estimate_s": 0.0, "in_queue": 0,
			"locked_s": float(d.get("seconds", 0)), "err": "HUD_MM_ERR_LOCKED"}))
	mm.select_chat.connect(_on_select_chat)
	mm.ready_check.connect(func(deadline: float) -> void:
		_join_wait_s = -1.0
		select_chat.clear()
		match_found.emit(found_of(mm.last_ready, deadline - _now())))
	mm.ready_result.connect(func(d: Dictionary) -> void:
		ready_result.emit({"outcome": RR.get(int(d.get("outcome", 0)), &"requeued"), "locked_s": float(d.get("locked", 0)),
			"reason": "HUD_MM_READY_DECLINED" if int(d.get("outcome", 0)) == MatchmakingCodec.RR_LOCKED else "HUD_MM_READY_OTHERS"}))
	mm.draft_state.connect(func(d: Dictionary) -> void: pick_state.emit(draft_of(d, _queue(), rules)))
	mm.aram_state.connect(func(d: Dictionary) -> void: pick_state.emit(aram_of(d, _outgoing)))
	mm.match_assigned.connect(func(host: String, port: int, ticket: String) -> void:
		_join_wait_s = -1.0
		_outgoing.clear()
		var a := mm.last_assigned
		match_assigned.emit({"match_id": str(a.get("match", "")), "host": host, "port": port, "ticket": ticket,
			"queue": _queue(), "hero": hero_id(int(a.get("hero", 0))), "hero_index": int(a.get("hero", 0)),
			"map": map_of(str(a.get("map", "")), _queue())}))
	mm.remake_prompt.connect(func(d: Dictionary) -> void:
		if int(d.get("state", 0)) != MatchmakingCodec.RV_OPEN:
			_remake_voted = false
		remake_state.emit(remake_of(d, _remake_voted)))
	mm.match_result.connect(func(d: Dictionary) -> void: post_match.emit(result_of(d, mm.last_ranked, rules)))
	mm.rating_update.connect(func(d: Dictionary) -> void: profile_received.emit(profile_of(d, rules)))
	mm.custom_state.connect(func(d: Dictionary) -> void: custom_changed.emit(custom_of(d)))
	mm.request_failed.connect(func(_op: int, code: int) -> void:
		_join_wait_s = -1.0  # an answer, even a refusal, ends the wait
		failed.emit(error_key(code)))
	if lobby != null and lobby.has_signal("account_result"):
		lobby.connect("account_result", _on_account_result)


# --- requests (MatchmakingFakeClient's interface) -------------------------------

func join_queue(queue_id: StringName, prefs: Array) -> void:
	mm.queue_join(queue_id, prefs if not prefs.is_empty() else [&"fill"])
	events.add("send", "queue join", {"queue": queue_id})
	_join_wait_s = 0.0
	print("[net] queue join sent (%s)" % queue_id)


func leave_queue() -> void:
	_join_wait_s = -1.0
	mm.queue_leave()
	events.add("send", "queue leave")


func reply_ready(accept: bool) -> void:
	events.add("send", "ready %s" % ("accept" if accept else "decline"))
	if accept:
		mm.ready_accept()
	else:
		mm.ready_decline()


func pick(hero: StringName) -> void:
	mm.draft_pick(hero_index(hero))
	events.add("send", "lock %s" % hero)


## P2: follow the real party (members, leader, ready flags, party chat).
func set_social(s: SocialModel) -> void:
	social = s
	if not s.party_changed.is_connected(_on_party):
		s.party_changed.connect(_on_party)
		s.changed.connect(func() -> void: party_chat_changed.emit())
	if not s.party.is_empty():
		_on_party(s.party)


func _on_party(p: Dictionary) -> void:
	party_changed.emit(party_of(p, social.me if social != null else ""))


## OP_PARTY -> the play screen's party: {members: [{id, name, leader, me,
## ready, rating_label}], leader}. Without a party: just me.
static func party_of(p: Dictionary, me: String) -> Dictionary:
	var lead := str(p.get("leader", ""))
	var out: Array = []
	for m: Dictionary in p.get("members", []):
		var k := int(m.kind)
		if k != AccountCodec.PARTY_LEADER and k != AccountCodec.PARTY_MEMBER:
			continue
		out.append({"id": str(m.id), "name": str(m.display_name), "leader": str(m.id) == lead,
			"me": str(m.id) == me, "ready": int(m.get("flags", 0)) & AccountCodec.PF_READY != 0,
			"status": int(m.status), "rating_label": ""})
	if out.is_empty():
		out.append({"id": me, "name": TranslationServer.translate("HUD_LOBBY_YOU"), "leader": true, "me": true,
			"ready": false, "rating_label": ""})
		lead = me
	return {"members": out, "leader": lead}


func party_promote(id: String) -> void:
	if social != null:
		social.promote(id)


func party_kick(id: String) -> void:
	if social != null:
		social.kick(id)


func party_ready(on: bool) -> void:
	if social != null:
		social.set_ready(on)


func party_leave() -> void:
	if social != null:
		social.leave_party()


func party_say(text: String) -> void:
	if social != null:
		social.say_party(text)


## [{name, text, mine}] for the party chat box.
func party_chat_lines() -> Array:
	if social == null:
		return []
	return social.party_chat.map(func(l: Dictionary) -> Dictionary:
		return {"name": l.name, "text": l.text, "mine": str(l.id) == social.me})


## v20: say `text` to the own team in hero select.
func select_say(text: String) -> void:
	mm.select_say(text)


func select_chat_lines() -> Array:
	return select_chat


func _on_select_chat(seat: int, text: String) -> void:
	var seats: Array = mm.last_pick.get("seats", [])
	var name := str((seats[seat] as Dictionary).get("name", "")) if seat < seats.size() else ""
	select_chat.append({"name": name, "text": text, "mine": seat == int(mm.last_pick.get("you", -1))})
	if select_chat.size() > 50:
		select_chat.pop_front()
	select_chat_changed.emit()


## v20: own loading percent for the other players' loading screens.
func report_load(pct: int) -> void:
	mm.report_load(pct)


## P3: declare `hero` (allies see it); &"" clears.
func hover(hero: StringName) -> void:
	mm.draft_hover(hero_index(hero) if hero != &"" else 0)


## P3: offer the teammate in `seat_id` to trade heroes (finalize window).
func offer_trade(seat_id: String) -> void:
	mm.aram_swap_request(seat_index(seat_id))
	events.add("send", "trade offer", {"seat": seat_id})


## P3: accept the trade the teammate in `seat_id` offered.
func accept_trade(seat_id: String) -> void:
	mm.aram_swap_accept(seat_index(seat_id))
	events.add("send", "trade accept", {"seat": seat_id})


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
	mm.request_state_sync()  # P1: the bar shows the server's view at once
	events.add("send", "rejoin + state sync")


func honour(match_id: Variant, target: String) -> void:
	mm.honour(target, str(match_id))
	feedback_result.emit({"op": &"honour", "target": target, "ok": true})


func report(match_id: Variant, target: String, category: StringName) -> void:
	mm.report(target, rules.report_categories.find(category), str(match_id))
	feedback_result.emit({"op": &"report", "target": target, "ok": true})


func request_profile() -> void:
	mm.request_ranked_info()


## W20-WEB: asks the front for the leaderboard opt-in (-> leaderboard_changed).
func request_leaderboard() -> void:
	if lobby != null and lobby.has_method("request"):
		lobby.call("request", AccountCodec.OP_LEADERBOARD, {"set": AccountCodec.LB_QUERY})


## W20-WEB: opts in to (true) or out of the public leaderboard (stored on
## the account by the front; PRIVACY.md).
func set_leaderboard_public(on: bool) -> void:
	if lobby != null and lobby.has_method("request"):
		lobby.call("request", AccountCodec.OP_LEADERBOARD, {"set": AccountCodec.LB_ON if on else AccountCodec.LB_OFF})


func _on_account_result(d: Dictionary) -> void:
	var st := leaderboard_of(d)
	if not st.is_empty():
		leaderboard_changed.emit(st)


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


## v20 host: bots per team (-1 = fill the empty seats) and difficulty (&"easy" / &"normal" / &"hard").
func custom_bots(bots_a: int, bots_b: int, difficulty: StringName) -> void:
	mm.custom_bots(MatchmakingCodec.BOTS_FILL if bots_a < 0 else bots_a, MatchmakingCodec.BOTS_FILL if bots_b < 0 else bots_b,
		maxi(0, MatchmakingCodec.BOT_DIFFICULTIES.find(String(difficulty))))


func custom_start() -> void:
	mm.custom_start()


## Local timers (the flow calls this every frame): when the server never
## answers a queue join, the player gets an error and the queue view resets.
func tick(delta: float) -> void:
	_watch_phase(delta)
	if _join_wait_s < 0.0:
		return
	_join_wait_s += delta
	if _join_wait_s >= _watch_config.queue_ack_timeout_s:
		_join_wait_s = -1.0
		print("[net] queue join not acknowledged: timeout")
		failed.emit("HUD_NET_ERR_QUEUE_TIMEOUT")
		queue_changed.emit({"state": &"idle", "queue": &"", "waited_s": 0.0, "estimate_s": 0.0, "in_queue": 0,
			"locked_s": 0.0, "err": ""})


## P1: no PHASE event for phase_timeout_s while online: ask for a snapshot
## once (an older server that does not know OP_STATE_SYNC simply ignores it).
func _watch_phase(delta: float) -> void:
	if _phase_wait_s < 0.0 or int(connection_info().state) != MmStatusModel.Conn.ONLINE:
		return
	_phase_wait_s += delta
	if _phase_wait_s >= _watch_config.phase_timeout_s:
		_phase_wait_s = -1.0
		events.add("send", "state sync (no state from the server yet)")
		mm.request_state_sync()


## P1 status bar: {state: MmStatusModel.Conn, rtt_ms}.
func connection_info() -> Dictionary:
	var tr_: Object = lobby.get("transport") if lobby != null else mm.transport
	if tr_ == null:
		return {"state": MmStatusModel.Conn.LOST, "rtt_ms": -1}
	if tr_.has_method("is_server_connected"):
		if bool(tr_.call("is_server_connected")):
			return {"state": MmStatusModel.Conn.ONLINE, "rtt_ms": int(tr_.call("rtt_ms")) if tr_.has_method("rtt_ms") else -1}
		var err := str(tr_.get("error_text")) if "error_text" in tr_ else ""
		return {"state": MmStatusModel.Conn.LOST if err != "" else MmStatusModel.Conn.CONNECTING, "rtt_ms": -1}
	return {"state": MmStatusModel.Conn.ONLINE, "rtt_ms": -1}  # loopback / tests


## P1 diagnostics panel text (what "Copy" puts on the clipboard).
func diagnostics_text() -> String:
	var ci := connection_info()
	var head := "Cybergram %s, protocol %d, connection %s, ping %d ms, stale phase events %d" % [
		ProjectSettings.get_setting("application/config/version", "?"), MsgType.PROTOCOL_VERSION,
		["connecting", "online", "lost"][int(ci.state)], int(ci.rtt_ms), mm.stale_phases]
	return events.to_text(head)


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


## The match's map id: the server's, else the queue's map (3v3 = slice).
static func map_of(server_map: String, queue: StringName) -> StringName:
	if server_map != "":
		return StringName(server_map)
	return &"slice" if queue == MmView.Q_ARAM else &"shardline_front"


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
		MatchmakingCodec.E_RATE:
			return "HUD_SOCIAL_SLOW_DOWN"
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
		# v20: a hover or a ban travels in `hero` with a flag; "hero" stays the locked pick.
		var h := hero_id(int(s.get("hero", 0)))
		var hover := f & MatchmakingCodec.SEAT_HOVER != 0
		var banning := f & MatchmakingCodec.SEAT_BANNING != 0
		out.append({"id": "seat%d" % i, "name": str(s.get("name", "")), "team": int(s.get("team", 0)),
			"lane": lane_id(int(s.get("lane", 255))), "hero": h if not (hover or banning) else &"",
			"hover": h if hover and not banning else &"", "ban": h if banning else &"",
			"ban_locked": banning and not hover,
			"bot": f & MatchmakingCodec.SEAT_BOT != 0, "auto": f & MatchmakingCodec.SEAT_AUTO != 0,
			"picking": f & MatchmakingCodec.SEAT_PICKING != 0 or banning})
	return out


static func draft_of(d: Dictionary, queue: StringName, rules: MatchmakingRulesDef) -> Dictionary:
	var seats := _seats(d)
	var you := int(d.get("you", 0))
	var turn := int(d.get("turn", 0))
	var turn_team := int(d.get("turn_team", 0))
	var blind := int(d.get("mode", 0)) == MatchmakingCodec.PM_BLIND
	var stage: StringName = [&"pick", &"ban", &"finalize"][clampi(int(d.get("stage", 0)), 0, 2)]
	var trades: Array = []
	for i in d.get("swap_from", []):
		var s: Dictionary = seats[int(i)] if int(i) < seats.size() else {}
		trades.append({"from": "seat%d" % int(i), "name": str(s.get("name", "")), "hero": s.get("hero", &"")})
	var order: PackedInt32Array = PackedInt32Array([seats.size() / 2]) if blind else rules.draft_order
	return {"mode": &"draft", "blind": blind, "stage": stage, "queue": queue, "ranked": queue == MmView.Q_RANKED,
		"me": "seat%d" % you, "my_team": int(seats[you].team) if you < seats.size() else 0, "turn": turn,
		"turn_team": turn_team, "order": order, "first_team": posmod(turn_team - turn, 2) if not blind else 0,
		"deadline_s": float(d.get("seconds", 0)), "turn_s": rules.blind_pick_s if blind else rules.pick_turn_s,
		"done": stage == &"finalize", "seats": seats,
		"bans": (d.get("bans", []) as Array).map(func(x: int) -> StringName: return hero_id(x)),
		"trade_s": float(d.get("trade_s", 0)), "trades": trades}


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


## An ACCOUNT_RESULT as a leaderboard_changed state ({} = another op).
## Guests and plain (non-DTLS) links cannot opt in: available false. Any
## other failure keeps it available and sets error (the view keeps its state).
static func leaderboard_of(d: Dictionary) -> Dictionary:
	if int(d.get("op", -1)) != AccountCodec.OP_LEADERBOARD:
		return {}
	var code := int(d.get("code", AccountCodec.E_BAD_REQUEST))
	if code == AccountCodec.OK:
		return {"public": int(d.get("public", 0)) == 1, "available": true}
	var no_account := code in [AccountCodec.E_GUEST, AccountCodec.E_NOT_SECURE, AccountCodec.E_NOT_LOGGED_IN]
	return {"public": false, "available": not no_account, "error": not no_account}


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
		"bot_slots": [_slot(int(d.get("bots_a", MatchmakingCodec.BOTS_FILL))), _slot(int(d.get("bots_b", MatchmakingCodec.BOTS_FILL)))],
		"difficulty": StringName(MatchmakingCodec.BOT_DIFFICULTIES[clampi(int(d.get("difficulty", 1)), 0, 2)]),
		"maps": MatchmakingCodec.CUSTOM_MAPS.duplicate(), "modes": [&"custom", &"all_random"],
		"members": members, "invited": [], "starting": int(d.get("phase", 0)) == MatchmakingCodec.CP_STARTING}


static func _slot(v: int) -> int:
	return -1 if v == MatchmakingCodec.BOTS_FILL else v


func _queue() -> StringName:
	return queue_id(int(mm.last_ready.get("queue", mm.last_status.get("queue", 0))))


func _now() -> float:
	return float(mm.clock.call())
