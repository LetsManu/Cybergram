extends GdUnitTestSuite
## W12-K1: the redesigned main menu shell keeps its behaviour: PLAY opens the
## mode select, CONFIRM launches the picked mode with the picked hero, the
## nav switches pages, Esc returns home and the friends sidebar collapses.

var _menu: MainMenu
var _args: Array = []


func before_test() -> void:
	UiKit.force_reduce_motion = 1
	_args.clear()
	_menu = (load("res://src/ui/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	_menu.start_requested.connect(func(a: PackedStringArray) -> void: _args.append(a))
	add_child(_menu)
	await get_tree().process_frame


func after_test() -> void:
	_menu.queue_free()
	UiKit.force_reduce_motion = -1


func test_play_opens_mode_select_and_confirm_launches_bots() -> void:
	_menu._play.pressed.emit()
	assert_bool(_menu._modes.visible).is_true()
	assert_bool(_menu._col.visible).is_false()
	_menu._mode_buttons[MainMenu.MODE_BOTS].pressed.emit()
	_menu._confirm.pressed.emit()
	assert_int(_args.size()).is_equal(1)
	var a: PackedStringArray = _args[0]
	assert_bool(a.has("--hero")).is_true()
	assert_str(a[a.find("--hero") + 1]).is_equal(_menu._hero_id())


func test_showcase_pick_is_the_launch_hero() -> void:
	var target := (_menu._hero_index + 1) % _menu._heroes.size()
	_menu._showcase.select(target)
	assert_int(_menu._hero_index).is_equal(target)
	assert_str(_menu._hero_id()).is_equal(str(_menu._heroes[target].stem))


func test_nav_pages() -> void:
	_menu._go(MainMenu.Nav.SETTINGS)
	assert_bool(_menu._settings.visible).is_true()
	assert_bool(_menu._col.visible).is_false()
	_menu._go(MainMenu.Nav.HEROES)
	assert_bool(_menu._col.visible).is_true()
	assert_bool(_menu._roster.visible).is_true()
	assert_bool(_menu._tiles.visible).is_false()
	_menu._go(MainMenu.Nav.HOME)
	assert_bool(_menu._tiles.visible).is_true()


func test_escape_returns_home() -> void:
	_menu._open_modes()
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	_menu._unhandled_input(ev)
	assert_bool(_menu._modes.visible).is_false()
	assert_bool(_menu._col.visible).is_true()


func test_friends_sidebar_collapses() -> void:
	var wide := _menu._friends.dock_width()
	_menu._friends.set_collapsed(true)
	assert_int(_menu._friends.dock_width()).is_less(wide)
	_menu._friends.set_collapsed(false)
	assert_int(_menu._friends.dock_width()).is_equal(wide)


func test_quit_asks_first() -> void:
	_menu._confirm_quit()
	assert_object(_menu._root.get_node_or_null("UiModal")).is_not_null()


## Regression (owner report 2026-10-06, v0.17.0): a server without
## CYBERGRAM_PUBLIC_HOST assigns matches with an empty host; the client must
## then use the address it reached the front with, not connect to ":7800".
func test_match_without_public_host_uses_the_front_address() -> void:
	assert_bool(_menu._connect("127.0.0.1:7999")).is_true()
	assert_str(_menu._online.matchmaking.server_host).is_equal("127.0.0.1")
	_menu._disconnect()
