extends GdUnitTestSuite
## W12-L2: LobbyScreen on a loopback server: hero filter chips, lock-in state
## of the LOCK IN button, title / subtitle, no 3D stage (headless safe).

const DT := 1.0 / 60.0

var _link: LoopbackLink
var _server: LobbyServer
var _me: LobbyClient
var _screen: LobbyScreen


func before_test() -> void:
	UiKit.force_reduce_motion = 1
	_link = LoopbackLink.new(null)
	var reg := PresenceRegistry.new()
	var acc := AccountService.new(null, AuthRulesDef.new(), false, reg)
	_server = LobbyServer.new(_link.create_endpoint(1), 3, reg, acc)
	_me = LobbyClient.new(_link.create_endpoint(2))
	_me.request(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": "Neo", "emblem": 1,
		"accent": 1, "flags": AccountCodec.FLAG_PRIVACY})
	for i in 12:
		_pump()
	_screen = LobbyScreen.new()
	_screen.online = _me
	_screen.with_model = false
	_screen.address = "127.0.0.1:7777"
	add_child(_screen)
	for i in 12:
		_pump()


func after_test() -> void:
	UiKit.force_reduce_motion = -1
	if _screen != null:
		_screen.queue_free()


func _pump() -> void:
	_link.advance(DT)
	_server.step(DT)
	if _screen != null and is_instance_valid(_screen):
		_screen._process(DT)
	else:
		_me.step()


func test_shows_pick_phase_and_waiting_counts() -> void:
	assert_str(_screen._title.text).is_equal(tr("HUD_LOBBY_PHASE_PICK").to_upper())
	assert_str(_screen._sub.text).contains(tr("HUD_LOBBY_WAIT_ALL"))


func test_lock_in_updates_button_and_title() -> void:
	assert_bool(_screen._lock_btn.button_pressed).is_false()
	_screen._lock_btn.button_pressed = true
	for i in 12:
		_pump()
	assert_bool(_me.own_slot().get("ready", false)).is_true()
	assert_str(_screen._lock_btn.text).is_equal(tr("HUD_LOBBY_LOCKED_CANCEL"))
	assert_str(_screen._title.text).is_not_equal(tr("HUD_LOBBY_PHASE_PICK").to_upper())
	# Tiles are disabled while locked in (picks are final until cancelled).
	for k in _screen._hero_tiles:
		assert_bool((_screen._hero_tiles[k] as Button).disabled).is_true()


func test_search_and_role_filter_hide_tiles() -> void:
	var all := HeroCatalog.entries()
	_screen._search.text_changed.emit("zzzz-no-hero")
	for k in _screen._hero_tiles:
		assert_bool((_screen._hero_tiles[k] as Button).visible).is_false()
	assert_bool(_screen._no_match.visible).is_true()
	_screen._search.text_changed.emit(str(all[0].name).substr(0, 2))
	assert_bool((_screen._hero_tiles[int(all[0].index)] as Button).visible).is_true()
	assert_bool(_screen._no_match.visible).is_false()


func test_picking_a_tile_sends_the_pick() -> void:
	var all := HeroCatalog.entries()
	var idx: int = int(all[all.size() - 1].index)
	(_screen._hero_tiles[idx] as Button).pressed.emit()
	for i in 12:
		_pump()
	assert_int(int(_me.own_slot().get("hero_index", 0))).is_equal(idx)
	assert_str(_screen._info_name.text).is_equal(str(all[all.size() - 1].name).to_upper())
