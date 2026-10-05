class_name MatchmakingFlow
extends Control
## W17B-UI: the matchmaking screen flow (design/gdd/matchmaking.md, LoL
## client style). Owns one page at a time and routes the client's signals:
##   PLAY (queue) --match_found--> READY CHECK popup over PLAY
##     --ready_result go--> DRAFT (5v5) or ALL RANDOM (3v3) --match_assigned-->
##   LOADING (ticket) --> start_requested(--connect host:port --ticket t --hero h)
##   connection_lost --> LOADING with RECONNECT; post_match --> POST-MATCH;
##   Custom --> CUSTOM LOBBY.
## `client` is MatchmakingFakeClient (tests, previews) or MmClientAdapter
## (network). The flow never decides a rule: it shows what the client says.
##
## Example (MainMenu):
##   var f := MatchmakingFlow.new()
##   f.client = MmClientAdapter.new(online.matchmaking, online)
##   f.start_requested.connect(func(args): start_requested.emit(args))
##   lobby_box.add_child(f)

signal start_requested(args: PackedStringArray)
signal closed()

## Seconds the loading screen shows before the game client takes over.
const HANDOFF_S := 1.5

var client: Object
## Step the client every frame (the fake; the adapter steps its LobbyClient).
var drive_client: bool = true
## Previews / tests: stay on the loading screen instead of starting the match.
var hold_on_assigned: bool = false
var with_model: bool = DisplayServer.get_name() != "headless"
## [{id, name}] for custom-lobby invites.
var friends: Array = []
var rules: MatchmakingRulesDef

var page: Control
var page_name: StringName = &""
var ready_popup: MmReadyCheck
var play: MmPlayScreen
var assigned: Dictionary = {}
var _last_pick: Dictionary = {}
var _handoff: float = -1.0
var _toast_root: Control


func _ready() -> void:
	HudStrings.ensure_loaded()
	if rules == null:
		rules = MatchmakingRulesDef.load_default()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	add_child(UiKit.background())
	_toast_root = MmKit.stage("Toasts")
	_bind()
	if page == null:
		show_play()
	add_child(_toast_root)


func _bind() -> void:
	if client == null:
		return
	var routes := {"queue_changed": _on_queue, "match_found": _on_found, "ready_result": _on_ready_result,
		"pick_state": _on_pick, "match_assigned": _on_assigned, "connection_lost": _on_lost,
		"post_match": show_post, "party_changed": _on_party, "custom_changed": _on_custom,
		"failed": func(key: String) -> void: toast(tr(key), &"warn")}
	for sig: String in routes:
		if client.has_signal(sig):
			client.connect(sig, routes[sig])


func _process(delta: float) -> void:
	if drive_client and client != null and client.has_method("step"):
		client.call("step", delta)
	if _handoff >= 0.0:
		_handoff -= delta
		if _handoff < 0.0:
			start_requested.emit(match_args(assigned, _my_hero()))


# --- pages ----------------------------------------------------------------------

func _set_page(c: Control, n: StringName) -> void:
	if page != null:
		page.queue_free()
	page = c
	page_name = n
	add_child(c)
	if _toast_root.get_parent() == self:
		move_child(_toast_root, -1)
	UiKit.transition_in(c, Vector2.ZERO)


func show_play() -> MmPlayScreen:
	play = MmPlayScreen.new()
	play.client = client
	play.rules = rules
	play.back_requested.connect(func() -> void:
		if play.state == MmPlayScreen.State.QUEUED and client != null:
			client.call("leave_queue")
		closed.emit())
	play.custom_requested.connect(func() -> void:
		show_custom()
		if client != null:
			client.call("custom_open"))
	_set_page(play, &"play")
	if client != null and client.has_signal("profile_received"):
		if not client.is_connected("profile_received", _on_profile):
			client.connect("profile_received", _on_profile)
		client.call("request_profile")
	return play


func show_custom() -> MmCustomLobby:
	var c := MmCustomLobby.new()
	c.client = client
	c.friends = friends
	c.back_requested.connect(func() -> void:
		if client != null and client.has_method("custom_leave"):
			client.call("custom_leave")
		show_play())
	_set_page(c, &"custom")
	return c


func show_post(result: Dictionary) -> MmPostMatchScreen:
	var p := MmPostMatchScreen.new()
	p.client = client
	p.rules = rules
	p.result = result
	p.closed.connect(func() -> void: show_play())
	_set_page(p, &"post")
	return p


func toast(text: String, kind: StringName = &"info") -> void:
	UiKit.toast(_toast_root, text, kind)


# --- client routes -------------------------------------------------------------------

func _on_queue(st: Dictionary) -> void:
	if play != null and is_instance_valid(play):
		play.on_queue_changed(st)
	var err := str(st.get("err", ""))
	if err != "" and StringName(st.get("state", &"")) != &"locked":
		toast(tr(err), &"warn")


func _on_profile(p: Dictionary) -> void:
	if play != null and is_instance_valid(play):
		play.set_ranked((p.get("tracks", {}) as Dictionary).get(&"ranked", {}))


func _on_party(p: Dictionary) -> void:
	if play != null and is_instance_valid(play):
		play.set_party(p)


func _on_found(info: Dictionary) -> void:
	if ready_popup != null and is_instance_valid(ready_popup):
		ready_popup.update(info)
		return
	ready_popup = MmReadyCheck.new()
	ready_popup.client = client
	ready_popup.open_with(info)
	add_child(ready_popup)


func _close_ready() -> void:
	if ready_popup != null and is_instance_valid(ready_popup):
		ready_popup.queue_free()
	ready_popup = null


func _on_ready_result(r: Dictionary) -> void:
	_close_ready()
	match StringName(r.get("outcome", &"")):
		&"go":
			pass
		&"locked":
			toast(tr("HUD_MM_READY_DECLINED") % MmView.clock(float(r.get("locked_s", 0.0))), &"danger")
			if page_name != &"play":
				show_play()
		&"voided":
			toast(tr("HUD_MM_MATCH_VOIDED"), &"warn")
		&"removed":
			toast(tr("HUD_MM_READY_PARTY_MISSED"), &"warn")
			if page_name != &"play":
				show_play()
		_:
			toast(tr("HUD_MM_READY_OTHERS"), &"info")
			if page_name != &"play":
				show_play()


func _on_pick(s: Dictionary) -> void:
	_close_ready()
	_last_pick = s
	var aram := StringName(s.get("mode", &"draft")) == &"all_random"
	if aram:
		if page_name != &"aram":
			var a := MmAllRandomScreen.new()
			a.client = client
			a.with_model = with_model
			_set_page(a, &"aram")
		(page as MmAllRandomScreen).set_state(s)
	else:
		if page_name != &"draft":
			var d := MmDraftScreen.new()
			d.client = client
			d.rules = rules
			d.with_model = with_model
			d.left.connect(func() -> void: show_play())
			_set_page(d, &"draft")
		(page as MmDraftScreen).set_state(s)


func _on_assigned(info: Dictionary) -> void:
	assigned = info
	var l := _loading()
	l.set_state(MmLoadingScreen.State.CONNECTING)
	if not hold_on_assigned:
		_handoff = HANDOFF_S


func _loading() -> MmLoadingScreen:
	if page_name != &"loading":
		var l := MmLoadingScreen.new()
		l.reconnect_requested.connect(func() -> void:
			if client != null:
				client.call("reconnect"))
		l.leave_requested.connect(func() -> void:
			_handoff = -1.0
			show_play())
		_set_page(l, &"loading")
	var ld := page as MmLoadingScreen
	ld.setup(assigned, _last_pick.get("seats", []), int(_last_pick.get("my_team", 0)))
	return ld


func _on_lost() -> void:
	_handoff = -1.0
	_loading().set_state(MmLoadingScreen.State.DISCONNECTED)


func _on_custom(l: Dictionary) -> void:
	if page_name != &"custom":
		show_custom()
	(page as MmCustomLobby).set_lobby(l)


func _my_hero() -> StringName:
	var h := StringName(assigned.get("hero", &""))
	if h != &"":
		return h
	return StringName(MmView.seat(_last_pick.get("seats", []), str(_last_pick.get("me", ""))).get("hero", &""))


## The game client's launch args for a MATCH_ASSIGNED.
static func match_args(info: Dictionary, hero: StringName) -> PackedStringArray:
	var args := PackedStringArray(["--connect", "%s:%d" % [str(info.get("host", "")), int(info.get("port", 0))],
		"--ticket", str(info.get("ticket", ""))])
	var e := MmView.hero_entry(hero)
	if not e.is_empty():
		args.append_array(["--hero", str(e.stem)])
	return args
