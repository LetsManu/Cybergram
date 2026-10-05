extends GdUnitTestSuite
## W12-L2: champ-select view logic (LobbyPhase): phase title, countdown bar,
## lock-in detection, hero filter / search, skill blurb keys.


func test_title_follows_phase() -> void:
	assert_str(LobbyPhase.title_key(LobbyCodec.PHASE_WAITING, false)).is_equal("HUD_LOBBY_PHASE_PICK")
	assert_str(LobbyPhase.title_key(LobbyCodec.PHASE_WAITING, true)).is_equal("HUD_LOBBY_PHASE_LOCKED_WAIT")
	assert_str(LobbyPhase.title_key(LobbyCodec.PHASE_COUNTDOWN, true)).is_equal("HUD_LOBBY_PHASE_LOCK")
	assert_str(LobbyPhase.title_key(LobbyCodec.PHASE_LOCKED, true)).is_equal("HUD_LOBBY_PHASE_START")


func test_timer_only_in_countdown_and_locked() -> void:
	assert_bool(LobbyPhase.has_timer(LobbyCodec.PHASE_WAITING)).is_false()
	assert_bool(LobbyPhase.has_timer(LobbyCodec.PHASE_COUNTDOWN)).is_true()
	assert_bool(LobbyPhase.has_timer(LobbyCodec.PHASE_LOCKED)).is_true()


func test_bar_fill_is_clamped() -> void:
	assert_float(LobbyPhase.bar_fill(5, 5)).is_equal(1.0)
	assert_float(LobbyPhase.bar_fill(0, 5)).is_equal(0.0)
	assert_float(LobbyPhase.bar_fill(9, 5)).is_equal(1.0)
	assert_float(LobbyPhase.bar_fill(3, 0)).is_equal(1.0)


func test_locked_count_and_newly_locked() -> void:
	var slots := [{"id": "a", "ready": true}, {"id": "b", "ready": false}, {"id": "c", "ready": true}]
	assert_int(LobbyPhase.locked_count(slots)).is_equal(2)
	assert_array(LobbyPhase.newly_locked({}, slots)).is_empty()  # first state: no flash
	assert_array(LobbyPhase.newly_locked({"a": true, "c": false}, slots)).is_equal(["c"])


func test_filter_by_search_and_role() -> void:
	var all := HeroCatalog.entries()
	assert_int(LobbyPhase.filter_heroes(all, "", "").size()).is_equal(all.size())
	var first: Dictionary = all[0]
	var hit := LobbyPhase.filter_heroes(all, str(first.name).to_upper().substr(0, 3), "")
	assert_bool(hit.has(first)).is_true()
	assert_int(LobbyPhase.filter_heroes(all, "zzzz-no-hero", "").size()).is_equal(0)
	var role := LobbyPhase.role_key(str(first.stem))
	for h: Dictionary in LobbyPhase.filter_heroes(all, "", role):
		assert_str(LobbyPhase.role_key(str(h.stem))).is_equal(role)
	assert_int(LobbyPhase.roles_of(all).size()).is_greater(1)


func test_every_hero_skill_has_blurb_and_role_chip_text() -> void:
	HudStrings.ensure_loaded()
	for h: Dictionary in HeroCatalog.entries():
		var def := load("res://assets/data/heroes/hero_%s.tres" % h.stem) as HeroDef
		for sk in def.skills:
			var key := LobbyPhase.skill_desc_key(sk)
			assert_str(tr(key)).is_not_equal(key)
		var short := LobbyPhase.role_short_key(LobbyPhase.role_key(str(h.stem)))
		assert_str(tr(short)).is_not_equal(short)
