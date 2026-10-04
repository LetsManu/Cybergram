extends Node
## Evidence capture for chunk L1 (tools/ci/capture_scene.sh): the main menu
## with the friends panel, the create-account screen, the full lobby with
## players (a real LobbyServer + bot clients on loopback, guest sessions) and
## the account screen. Pick with `-- --view menu|login|lobby|profile`.
## Display data for the friends panel is a fixture (no server needed).

const DT := 1.0 / 60.0

var _view := "menu"
var _menu: MainMenu
var _link: LoopbackLink
var _server: LobbyServer
var _bots: Array[LobbyClient] = []
var _t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		_view = args[i + 1]
	_menu = (load("res://src/ui/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(_menu)
	await get_tree().process_frame
	match _view:
		"login":
			_menu._col.visible = false
			var ls := LoginScreen.new()
			ls.server_text = tr("HUD_LOGIN_SERVER") % ["cyber.djboeck.at:7777", tr("HUD_LOGIN_ENCRYPTED")]
			ls.prefill_name = "Neo"
			ls.prefill_emblem = 3
			ls.prefill_accent = 1
			_menu._center.add_child(ls)
			await get_tree().process_frame
			ls.set_mode(LoginScreen.Mode.REGISTER)
			ls.fill_register("neo_runner", "correct horse", "Neo", true, false)
		"lobby":
			_start_lobby()
		"profile":
			_fake_session()
			_menu._show_profile()
		_:
			_fake_session()


func _fake_session() -> void:
	_link = LoopbackLink.new(null)
	var c := LobbyClient.new(_link.create_endpoint(2))
	c.session = {"token": "", "id": ProfileFixtures.id(0x3c), "username": "neo_runner", "display_name": "Neo",
		"emblem": 3, "accent": 1, "favourite_hero": "brannoc", "guest": 0}
	_menu._online = c
	_menu._refresh_chip()
	_menu._friends.apply_friends(_friends())


func _friends() -> Array:
	var f := func(n: int, name: String, st: int, rel: int, em: int, ac: int) -> Dictionary:
		return {"id": ProfileFixtures.id(n), "status": st, "relation": rel, "username": name.to_lower(),
			"display_name": name, "emblem": em, "accent": ac}
	return [f.call(1, "Trinity", LobbyCodec.STATUS_IN_MATCH, AccountCodec.REL_FRIEND, 1, 7),
		f.call(2, "Morpheus", LobbyCodec.STATUS_IN_LOBBY, AccountCodec.REL_FRIEND, 11, 4),
		f.call(3, "Switch", LobbyCodec.STATUS_ONLINE, AccountCodec.REL_FRIEND, 2, 1),
		f.call(4, "Apoc", LobbyCodec.STATUS_OFFLINE, AccountCodec.REL_FRIEND, 6, 6),
		f.call(5, "Niobe", 0, AccountCodec.REL_INCOMING, 9, 8),
		f.call(6, "Ghost", 0, AccountCodec.REL_OUTGOING, 5, 2)]


func _start_lobby() -> void:
	_link = LoopbackLink.new(null)
	var reg := PresenceRegistry.new()
	var acc := AccountService.new(null, AuthRulesDef.new(), false, reg)
	_server = LobbyServer.new(_link.create_endpoint(1), 3, reg, acc)
	var me := LobbyClient.new(_link.create_endpoint(2))
	me.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": "Neo", "emblem": 3,
		"accent": 1, "flags": AccountCodec.FLAG_PRIVACY})
	var bots := [["Trinity", 1, 7, &"hero_brannoc", true], ["Morpheus", 11, 4, &"hero_vesper_loom", false],
		["Switch", 2, 2, &"hero_brannoc", true]]
	for k in bots.size():
		var b := LobbyClient.new(_link.create_endpoint(3 + k))
		b.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": bots[k][0],
			"emblem": bots[k][1], "accent": bots[k][2], "flags": AccountCodec.FLAG_PRIVACY})
		var hero := ContentDB.shared().index_of(ContentDB.HERO, bots[k][3])
		b.join(hero)
		b.set_meta("ready", bots[k][4])
		b.set_meta("hero", hero)
		_bots.append(b)
	_bots.append(me)
	_pump(0.2)
	_bots.erase(me)  # the lobby view steps its own client from here on
	_menu._online = me
	me.session["guest"] = 0  # show the account-only row buttons in the evidence
	_menu._show_lobby("cyber.djboeck.at:7777", "")
	_menu._friends.set_session(true, Callable())
	_menu._friends.apply_friends(_friends())


func _pump(seconds: float) -> void:
	for i in roundi(seconds / DT):
		_link.advance(DT)
		_server.step(DT)
		for b in _bots:
			b.step()


func _process(delta: float) -> void:
	if _server == null:
		return
	_t += delta
	_link.advance(delta)
	_server.step(delta)
	for b in _bots:
		b.step()
	if _t > 0.4 and not _bots[0].has_meta("talked"):
		_bots[0].set_meta("talked", true)
		_bots[0].say("gl hf, I'll hold mid")
		_bots[1].say("Vesper again? :)")
		for b in _bots:
			if b.get_meta("ready"):
				b.pick(b.get_meta("hero"), true)
	if _t > 0.6 and not _bots[2].has_meta("talked"):
		_bots[2].set_meta("talked", true)
		_bots[2].say("ready when you are")
