extends GdUnitTestSuite
## PlayerProfile name rules, tags, FriendList parsing / resolution, the name
## filter and local moderation (pure logic, no files).


func test_valid_names_accepted() -> void:
	for n in ["Neo", "Ann_99", "Bo Bee", "x.y-z", "ABCDEFGHIJKLMNOP"]:
		assert_int(PlayerProfile.validate_name(n)).is_equal(PlayerProfile.NameError.OK)


func test_short_long_charset_and_space_rejected() -> void:
	assert_int(PlayerProfile.validate_name("ab")).is_equal(PlayerProfile.NameError.TOO_SHORT)
	assert_int(PlayerProfile.validate_name("ABCDEFGHIJKLMNOPQ")).is_equal(PlayerProfile.NameError.TOO_LONG)
	assert_int(PlayerProfile.validate_name("Nëo")).is_equal(PlayerProfile.NameError.BAD_CHAR)
	assert_int(PlayerProfile.validate_name("a<b>c")).is_equal(PlayerProfile.NameError.BAD_CHAR)
	assert_int(PlayerProfile.validate_name(("Neo" + String.chr(0x200B) + "1"))).is_equal(PlayerProfile.NameError.BAD_CHAR)
	assert_int(PlayerProfile.validate_name(" Neo")).is_equal(PlayerProfile.NameError.BAD_SPACE)
	assert_int(PlayerProfile.validate_name("Ne  o")).is_equal(PlayerProfile.NameError.BAD_SPACE)


func test_created_profile_has_hex_id_key_and_tag() -> void:
	var p := PlayerProfile.create("Neo", 3, 2)
	assert_bool(PlayerProfile.is_hex_id(p.id)).is_true()
	assert_bool(PlayerProfile.is_hex_id(p.key)).is_true()
	assert_str(p.id).is_not_equal(p.key)
	assert_str(p.tag()).is_equal(p.id.substr(0, 4).to_upper())
	assert_str(p.display_id()).is_equal("Neo#" + p.tag())
	assert_bool(p.is_valid()).is_true()
	assert_bool(p.can_play_online()).is_false()  # no consent until acknowledged


func test_out_of_range_fields_invalid() -> void:
	var p := ProfileFixtures.profile(1, "Neo")
	p.emblem = PlayerProfile.EMBLEM_COUNT
	assert_bool(p.is_valid()).is_false()
	p = ProfileFixtures.profile(1, "Neo")
	p.id = "XYZ"
	assert_bool(p.is_valid()).is_false()


func test_generated_profile_is_valid() -> void:
	assert_bool(PlayerProfile.generated().is_valid()).is_true()


func test_name_filter_blocks_fragments_and_lookalikes() -> void:
	var f := NameFilterDef.new()
	f.blocked = PackedStringArray(["admin", "nazi"])
	assert_bool(f.allows("Neo")).is_true()
	assert_bool(f.allows("TheAdmin")).is_false()
	assert_bool(f.allows("4dm1n")).is_false()
	assert_bool(f.allows("n.a.z.i")).is_false()


func test_shipped_name_filter_blocks_impersonation() -> void:
	assert_bool(PlayerProfile.name_allowed("Official Admin")).is_false()
	assert_bool(PlayerProfile.name_allowed("Pilot-1A2B")).is_true()








func test_legacy_profile_round_trip_for_import() -> void:
	var path := "user://test_legacy_profile.cfg"
	var p := PlayerProfile.create("Neo", 5, 3)
	assert_int(p.save(path)).is_equal(OK)
	var q := PlayerProfile.load_or_null(path)
	assert_str(q.name).is_equal("Neo")
	assert_int(q.emblem).is_equal(5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_object(PlayerProfile.load_or_null(path)).is_null()


func test_moderation_mute_and_report_in_memory() -> void:
	var m := LocalModeration.new()
	m.mute(ProfileFixtures.id(1), "Ann")
	assert_bool(m.is_muted(ProfileFixtures.id(1))).is_true()
	m.unmute(ProfileFixtures.id(1))
	assert_bool(m.is_muted(ProfileFixtures.id(1))).is_false()
	m.mute(ProfileFixtures.id(2), "Bo")
	assert_bool(m.is_muted(ProfileFixtures.id(2))).is_true()
	m.report(ProfileFixtures.id(2), "Bo", "x".repeat(500), 1000.0)
	assert_int(m.reports.size()).is_equal(1)
	assert_int(str(m.reports[0].reason).length()).is_equal(LocalModeration.REASON_MAX)
	m.mute("not-an-id", "X")
	assert_int(m.muted.size()).is_equal(1)
