extends GdUnitTestSuite
## Server-side chat hygiene (ChatFilter) and the connection-scoped presence
## registry (PresenceRegistry).


func test_sanitize_strips_control_bidi_and_zero_width() -> void:
	assert_str(ChatFilter.sanitize("hi\u0007 there")).is_equal("hi there")
	assert_str(ChatFilter.sanitize((String.chr(0x202E) + "evil" + String.chr(0x202C)))).is_equal("evil")
	assert_str(ChatFilter.sanitize(("a" + String.chr(0x200B) + "b" + String.chr(0xFEFF) + "c"))).is_equal("abc")
	assert_str(ChatFilter.sanitize("  lots \n\t of   space  ")).is_equal("lots of space")
	assert_str(ChatFilter.sanitize("[b]x[/b]")).is_equal("[b]x[/b]")  # shown with BBCode off


func test_sanitize_empty_and_length_cap() -> void:
	assert_str(ChatFilter.sanitize((String.chr(0x200B) + " \u0001 "))).is_equal("")
	assert_int(ChatFilter.sanitize("x".repeat(300)).length()).is_equal(LobbyCodec.CHAT_MAX_CHARS)


func test_rate_limiter_burst_then_refill() -> void:
	var rl := ChatFilter.RateLimiter.new()
	for i in ChatFilter.BURST:
		assert_bool(rl.allow(10.0)).is_true()
	assert_bool(rl.allow(10.0)).is_false()
	assert_bool(rl.allow(10.0 + ChatFilter.REFILL_S * 0.5)).is_false()
	assert_bool(rl.allow(10.0 + ChatFilter.REFILL_S * 1.1)).is_true()


func test_claim_refuses_other_key_while_present() -> void:
	var reg := PresenceRegistry.new()
	assert_bool(reg.claim(ProfileFixtures.id(1), ProfileFixtures.id(101), "Ann", 0.0)).is_true()
	assert_bool(reg.claim(ProfileFixtures.id(1), ProfileFixtures.id(55), "Ann", 0.0)).is_false()
	assert_bool(reg.claim(ProfileFixtures.id(1), ProfileFixtures.id(101), "Annie", 0.0)).is_true()
	assert_bool(reg.claim("nothex", ProfileFixtures.id(101), "Ann", 0.0)).is_false()


func test_forget_drops_everything_about_the_player() -> void:
	var reg := PresenceRegistry.new()
	reg.claim(ProfileFixtures.id(1), ProfileFixtures.id(101), "Ann", 0.0)
	reg.set_status(ProfileFixtures.id(1), LobbyCodec.STATUS_IN_LOBBY, 0.0)
	reg.forget(ProfileFixtures.id(1))
	assert_int(reg.entries.size()).is_equal(0)
	assert_int(reg.status_of(ProfileFixtures.id(1), 1.0)).is_equal(LobbyCodec.STATUS_OFFLINE)
	# After forgetting, the id can be claimed with a new key (nothing remembered).
	assert_bool(reg.claim(ProfileFixtures.id(1), ProfileFixtures.id(55), "Ann", 2.0)).is_true()


func test_menu_check_in_expires_and_is_purged() -> void:
	var reg := PresenceRegistry.new()
	reg.claim(ProfileFixtures.id(1), ProfileFixtures.id(101), "Ann", 100.0)
	assert_int(reg.status_of(ProfileFixtures.id(1), 110.0)).is_equal(LobbyCodec.STATUS_ONLINE)
	assert_int(reg.status_of(ProfileFixtures.id(1), 100.0 + PresenceRegistry.ONLINE_TTL_S + 1.0)) \
		.is_equal(LobbyCodec.STATUS_OFFLINE)
	reg.purge(100.0 + PresenceRegistry.ONLINE_TTL_S + 1.0)
	assert_int(reg.entries.size()).is_equal(0)


func test_end_match_forgets_match_players() -> void:
	var reg := PresenceRegistry.new()
	reg.claim(ProfileFixtures.id(1), ProfileFixtures.id(101), "Ann", 0.0)
	reg.set_status(ProfileFixtures.id(1), LobbyCodec.STATUS_IN_MATCH, 0.0)
	reg.end_match(1.0)
	assert_int(reg.entries.size()).is_equal(0)
