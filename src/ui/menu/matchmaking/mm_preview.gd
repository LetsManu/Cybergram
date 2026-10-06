extends CanvasLayer
## W17B-UI: debug preview of the matchmaking screens, driven by the offline
## MatchmakingFakeClient (evidence screenshots, look-and-feel checks).
## Usage: tools/ci/capture_scene.sh res://src/ui/menu/matchmaking/mm_preview.tscn out.png 40 --mm <state>
## States: play, play_ranked, queued, locked, ready, ready_accepted,
## draft_enemy, draft_mine, draft_late, aram, aram_swap, loading, reconnect,
## post_ranked, post_normal, post_report, profile, profile_public, profile_guest,
## custom, custom_bots (v17), remake, remake_open, draft_hover, blind_trade (P3), party, social (P2).
## Not part of the game flow (never loaded by AppRoot).

const REF_SIZE := Vector2(1440, 810)

var fake := MatchmakingFakeClient.new()
var flow: MatchmakingFlow
var _root: Control


func _ready() -> void:
	HudStrings.ensure_loaded()
	_root = Control.new()
	_root.theme = UiKit.theme()
	add_child(_root)
	get_viewport().size_changed.connect(_fit)
	_fit()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--mm")
	var st := args[i + 1] if i >= 0 and i + 1 < args.size() else "play"
	_build(st)


func _fit() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := vp.y / REF_SIZE.y
	_root.scale = Vector2(s, s)
	_root.size = Vector2(vp.x / s, REF_SIZE.y)


func _flow() -> MatchmakingFlow:
	flow = MatchmakingFlow.new()
	flow.client = fake
	flow.drive_client = false
	flow.hold_on_assigned = true
	flow.friends = [{"id": "f1", "name": "Nyx"}, {"id": "f2", "name": "Orrin"}, {"id": "f3", "name": "Talia"}]
	_root.add_child(flow)
	fake.set_party(["Nyx", "Orrin"])
	return flow


func _to_pick(q: StringName) -> void:
	fake.join_queue(q, [&"north", &"center"])
	fake.step(fake.found_after_s)
	fake.reply_ready(true)
	fake.step(fake.think_s)


func _build(st: String) -> void:
	match st:
		"profile", "profile_public", "profile_guest":
			fake.leaderboard_public = st == "profile_public"  # W20-WEB opt-in toggle
			fake.leaderboard_available = st != "profile_guest"
			var bg := UiKit.background()
			_root.add_child(bg)
			var p := MmProfilePanel.new()
			p.client = fake
			p.position = Vector2(500, 60)
			_root.add_child(p)
			return
		"remake", "remake_open":
			_remake(st == "remake_open")
			return
		"career":
			_career()
			return
		"social":
			_social()
			return
	_flow()
	match st:
		"play_ranked":
			flow.play.select_queue(MmView.Q_RANKED)
			flow.play.set_lanes(&"center", &"flex")
		"queued":
			fake.found_after_s = 9999.0
			fake.join_queue(MmView.Q_NORMAL, [&"north", &"south"])
			fake.step(83.0)
			flow.play.on_queue_changed(fake._status(&"queued"))
		"locked":
			fake.lock_out(95.0)
		"ready", "ready_accepted":
			fake.think_s = 3.0
			fake.join_queue(MmView.Q_RANKED, [&"center", &"flex"])
			fake.step(fake.found_after_s)
			fake.think_s = 1.0
			fake.step(1.0)  # some players accept
			if st == "ready_accepted":
				flow.ready_popup.accept()
				fake._found.accepted = 6
				fake.match_found.emit(fake._found_info())
			flow.ready_popup.tick(3.2)
		"draft_enemy":
			_to_pick(MmView.Q_RANKED)
		"draft_mine":
			_to_pick(MmView.Q_RANKED)
			fake.step(fake.think_s + 0.1)
		"party":
			fake.party_say("duo bot?")
			fake.party_chat.append({"name": "Nyx", "text": "sure, I go support", "mine": false})
			fake.party_chat_changed.emit()
		"draft_hover", "blind_trade":
			_to_pick(MmView.Q_RANKED if st == "draft_hover" else MmView.Q_NORMAL)
			(flow.page as MmDraftScreen).set_state(_p3_state(st))
		"draft_late":
			_to_pick(MmView.Q_NORMAL)
			fake.step(fake.think_s + 0.1)
			fake.pick(&"hero_brannoc")
			for k in 3:
				fake.step(fake.think_s + 0.1)
			(flow.page as MmDraftScreen).preview(&"hero_brannoc")
		"aram", "aram_swap":
			_to_pick(MmView.Q_ARAM)
			fake.reroll()
			if st == "aram_swap":
				fake.step(fake.think_s + 0.1)
		"loading", "reconnect":
			_to_pick(MmView.Q_NORMAL)
			for k in 40:  # P3 added the finalize window: step until the match is assigned
				if fake.phase == &"assigned":
					break
				fake.step(fake.think_s + 0.1)
				if fake.phase == &"pick" and fake._draft != null and fake._draft.current_pickers().has(MatchmakingFakeClient.ME):
					var legal := fake._draft.legal_heroes(0)
					fake.pick(legal[0])
			if st == "reconnect":
				fake.drop_connection()
			else:
				fake.step(fake.load_s * 0.6)  # v20: the other players are part-way loaded
		"post_ranked":
			fake.queue = MmView.Q_RANKED
			fake.finish_match(true)
		"post_normal":
			fake.queue = MmView.Q_NORMAL
			fake.finish_match(false)
		"post_report":
			fake.queue = MmView.Q_RANKED
			fake.finish_match(false)
			var p := flow.page as MmPostMatchScreen
			p.honour("p2")
			p.open_report.call_deferred("p7", "Juno")
		"custom":
			flow.play.select_queue(MmView.Q_CUSTOM)
			flow.play.find_match()
		"custom_bots":
			flow.play.select_queue(MmView.Q_CUSTOM)
			flow.play.find_match()
			var c := flow.page as MmCustomLobby
			c.bump_bots(0, -1)
			c.set_bots(c._slots(), &"hard")


## W21-U2: the CAREER page as the main menu builds it (profile + ranks in a
## CareerLayout, content right of the 300 px friends dock, 64 px top bar).
func _career() -> void:
	_root.add_child(UiKit.background())
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 64
	content.offset_right = -300
	_root.add_child(content)
	var page := CareerLayout.new()
	content.add_child(page)
	var prof := ProfileScreen.new()
	prof.session = {"token": "x", "id": "0", "username": "neo", "display_name": "Neo", "emblem": 0, "accent": 0,
		"favourite_hero": 0, "guest": 0}
	page.add_panel(prof)
	var ranks := MmProfilePanel.new()
	ranks.client = fake
	page.add_panel(ranks)


func _remake(open: bool) -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1b2730")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var zone := Control.new()
	zone.anchor_left = 0.3
	zone.anchor_right = 0.7
	zone.anchor_top = 0.17
	zone.anchor_bottom = 0.3
	_root.add_child(zone)
	var w := RemakePrompt.new()
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.bind(HudContext.new(null, HudSettings.new(), HudTuningDef.new()))
	zone.add_child(w)
	fake.remake_state.connect(w.apply)
	fake.start_remake(true)
	if not open:
		w.apply({"eligible": true, "open": false, "yes": 0, "no": 0, "needed": 4, "deadline_s": 0.0, "voted": false,
			"outcome": &""})
	else:
		fake.step(7.0)
		fake.remake_vote(true)
		w.left_s = 23.0


## P3 evidence: a hand-made draft state (ally hovers + bans, or blind finalize with trades).
func _p3_state(st: String) -> Dictionary:
	var hs := MmView.all_heroes()
	var seats: Array = []
	for i in 10:
		var team := 0 if i < 5 else 1
		var s := {"id": "seat%d" % i, "name": ["You", "Nyx", "Orrin", "Talia", "Brin", "", "", "", "", ""][i],
			"team": team, "lane": [&"north", &"center", &"south", &"flex", &"flex"][i % 5], "hero": &"", "hover": &"",
			"ban": &"", "bot": false, "auto": false, "picking": false}
		seats.append(s)
	if st == "draft_hover":
		seats[0].picking = true
		seats[0].hover = hs[1]
		seats[1].hover = hs[2]
		seats[2].hero = hs[3]
		seats[5].hero = hs[3]
		return {"mode": &"draft", "blind": false, "stage": &"pick", "queue": MmView.Q_RANKED, "ranked": true,
			"me": "seat0", "my_team": 0, "turn": 2, "turn_team": 0, "order": PackedInt32Array([1, 2, 2, 2, 2, 1]),
			"first_team": 0, "deadline_s": 21.0, "turn_s": 30.0, "done": false, "seats": seats,
			"bans": [hs[0]], "trade_s": 0.0, "trades": []}
	for i in 10:
		seats[i].hero = hs[i % 5 + (1 if i >= 5 else 0)]
	return {"mode": &"draft", "blind": true, "stage": &"finalize", "queue": MmView.Q_NORMAL, "ranked": false,
		"me": "seat0", "my_team": 0, "turn": 0, "turn_team": 2, "order": PackedInt32Array([5]), "first_team": 0,
		"deadline_s": 17.0, "turn_s": 45.0, "done": true, "seats": seats, "bans": [], "trade_s": 12.0,
		"trades": [{"from": "seat2", "name": "Orrin", "hero": seats[2].hero}]}


## P2 evidence: friends panel with the new presence states, a party invite, a
## join request, unread DMs, and an open DM window.
func _social() -> void:
	var bg := UiKit.background()
	_root.add_child(bg)
	var m := SocialModel.new()
	m.me = "me"
	var fp := FriendsPanel.new()
	fp.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	fp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(fp)
	fp.social = m
	fp.set_session(true, func(_op: int, _f: Dictionary) -> void: pass)
	m.on_result({"op": AccountCodec.OP_PARTY, "code": AccountCodec.OK, "party": "", "leader": "", "members": [
		{"id": "f9", "kind": AccountCodec.PARTY_INVITE_IN, "status": 1, "display_name": "Brin", "emblem": 2,
			"accent": 3, "flags": 0}]})
	for n in [["f3", "Talia", "gg wp, again?"], ["f3", "Talia", "I am in queue"]]:
		m.on_result({"op": AccountCodec.OP_NOTIFY, "code": AccountCodec.OK, "kind": AccountCodec.N_DM, "id": n[0],
			"name": n[1], "text": n[2], "mode": 255})
	m.on_result({"op": AccountCodec.OP_NOTIFY, "code": AccountCodec.OK, "kind": AccountCodec.N_JOIN_REQUEST,
		"id": "f7", "name": "Kael", "text": "", "mode": 255})
	var st := [[LobbyCodec.STATUS_IN_MATCH, 1], [LobbyCodec.STATUS_IN_SELECT, 0], [LobbyCodec.STATUS_IN_QUEUE, 1],
		[LobbyCodec.STATUS_ONLINE, 255], [LobbyCodec.STATUS_AWAY, 255], [LobbyCodec.STATUS_ONLINE, 255]]
	var names := ["Nyx", "Orrin", "Talia", "Kael", "Mira", "Juno"]
	var list: Array = []
	for i in names.size():
		list.append({"id": "f%d" % (i + 1), "status": st[i][0], "mode": st[i][1], "relation": 0,
			"username": names[i].to_lower(), "display_name": names[i], "emblem": i % 6, "accent": i % 4})
	fp.apply_friends(list)
	var w := SocialDmWindow.new()
	w.social = m
	w.friend_id = "f2"
	w.friend_name = "Orrin"
	w.position = Vector2(560, 380)
	_root.add_child(w)
	m.on_result({"op": AccountCodec.OP_NOTIFY, "code": AccountCodec.OK, "kind": AccountCodec.N_DM, "id": "f2",
		"name": "Orrin", "text": "picking support this time", "mode": 255})
	m.send_dm("f2", "nice, I take center")
