extends GdUnitTestSuite
## Menu screens driven as a player would: the profile screen validates the
## name and records the privacy acknowledgement; the lobby screen (on an
## injected loopback transport) shows both teams, relays chat, hides muted
## players and hands over to the match with --connect/--token.

const DIR := "user://test_profile_screens"
const DT := 1.0 / 30.0


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func after_test() -> void:
	for f in ["profile.cfg", "moderation.cfg"]:
		if FileAccess.file_exists(DIR + "/" + f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_profile_screen_blocks_invalid_name_and_saves_consent() -> void:
	var ps := ProfileScreen.new()
	ps.path = DIR + "/profile.cfg"
	var saved: Array = []
	ps.saved.connect(func(p: PlayerProfile) -> void: saved.append(p))
	add_child(auto_free(ps))
	await get_tree().process_frame
	ps.set_fields("x!", 1, 1)
	assert_bool(ps._save.disabled).is_true()
	ps.set_fields("TheAdmin", 1, 1)  # name filter
	assert_bool(ps._save.disabled).is_true()
	ps.set_fields("Neo", 4, 2)
	ps.set_acknowledged(true)
	assert_bool(ps._save.disabled).is_false()
	ps._on_save()
	assert_int(saved.size()).is_equal(1)
	var back := PlayerProfile.load_or_null(DIR + "/profile.cfg")
	assert_str(back.name).is_equal("Neo")
	assert_int(back.emblem).is_equal(4)
	assert_bool(back.can_play_online()).is_true()


func test_profile_screen_without_ack_cannot_play_online() -> void:
	var ps := ProfileScreen.new()
	ps.path = DIR + "/profile.cfg"
	add_child(auto_free(ps))
	await get_tree().process_frame
	ps.set_fields("Neo", 0, 0)
	ps._on_save()
	assert_bool(PlayerProfile.load_or_null(DIR + "/profile.cfg").can_play_online()).is_false()


func test_lobby_screen_shows_players_chat_mute_and_start() -> void:
	var link := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var server := LobbyServer.new(link.create_endpoint(1), 3, PresenceRegistry.new())
	var other := LobbyClient.new(link.create_endpoint(3), ProfileFixtures.wire(2, "Bob"), 1)
	var screen := LobbyScreen.new()
	screen.address = "127.0.0.1:7851"
	screen.profile = ProfileFixtures.profile(1, "Ann")
	screen.transport = link.create_endpoint(2)
	screen.auto_ready = true
	screen.moderation = LocalModeration.new()
	screen.moderation_path = DIR + "/moderation.cfg"
	var args: Array = []
	screen.start_requested.connect(func(a: PackedStringArray) -> void: args.append(a))
	add_child(auto_free(screen))
	var pump := func(seconds: float) -> void:
		for i in roundi(seconds / DT):
			link.advance(DT)
			server.step(DT)
			other.step()
			screen._process(DT)
	await get_tree().process_frame
	pump.call(0.3)
	assert_int(screen._team_cols[0].get_child_count()).is_equal(3)  # Ann + 2 open slots
	assert_int(screen._team_cols[1].get_child_count()).is_equal(3)
	other.say("hello Ann")
	pump.call(0.2)
	assert_str(screen._chat_log.get_parsed_text()).contains("Bob: hello Ann")
	screen.moderation.mute(ProfileFixtures.id(2), "Bob")
	other.say("muted line")
	pump.call(0.2)
	assert_str(screen._chat_log.get_parsed_text()).not_contains("muted line")
	other.pick(1, true)
	pump.call(LobbyServer.COUNTDOWN_S + 0.5)
	assert_int(args.size()).is_equal(1)
	assert_str(args[0][0]).is_equal("--connect")
	assert_str(args[0][1]).is_equal("127.0.0.1:7851")
	assert_bool(args[0].has("--token")).is_true()
	# Let the rebuilt rows' queue_free() run (no orphans).
	await get_tree().process_frame
	await get_tree().process_frame
