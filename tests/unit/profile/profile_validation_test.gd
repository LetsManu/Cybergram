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


func test_friend_parse_name_and_tag() -> void:
	assert_array(FriendList.parse("Neo")).contains_exactly(["Neo", ""])
	assert_array(FriendList.parse("Neo#0a1b")).contains_exactly(["Neo", "0A1B"])
	assert_array(FriendList.parse("Neo#zz")).is_empty()
	assert_array(FriendList.parse("x")).is_empty()


func test_friend_add_rejects_duplicates_and_resolves_by_name_and_tag() -> void:
	var fl := FriendList.new()
	assert_object(fl.add("Neo")).is_not_null()
	assert_object(fl.add("neo")).is_null()
	var t := fl.add("Trin#0B0B")
	assert_object(t).is_not_null()
	# A Trin with another tag does not resolve the tagged friend.
	assert_bool(fl.resolve(ProfileFixtures.id(0x0c), "Trin")).is_false()
	assert_bool(fl.resolve(ProfileFixtures.id(0x0b), "Trin")).is_true()
	assert_str(t.id).is_equal(ProfileFixtures.id(0x0b))
	assert_bool(fl.resolve(ProfileFixtures.id(5), "NEO")).is_true()
	assert_int(fl.ids().size()).is_equal(2)
	assert_int(fl.unresolved().size()).is_equal(0)


func test_friend_add_known_and_rename() -> void:
	var fl := FriendList.new()
	assert_object(fl.add_known(ProfileFixtures.id(3), "Ann")).is_not_null()
	assert_object(fl.add_known(ProfileFixtures.id(3), "Ann")).is_null()
	assert_bool(fl.resolve(ProfileFixtures.id(3), "Annie")).is_true()
	assert_str(fl.find_id(ProfileFixtures.id(3)).name).is_equal("Annie")


func test_moderation_mute_block_report() -> void:
	var m := LocalModeration.new()
	m.mute(ProfileFixtures.id(1), "Ann")
	assert_bool(m.is_muted(ProfileFixtures.id(1))).is_true()
	m.unmute(ProfileFixtures.id(1))
	assert_bool(m.is_muted(ProfileFixtures.id(1))).is_false()
	m.block(ProfileFixtures.id(2), "Bo")
	assert_bool(m.is_muted(ProfileFixtures.id(2))).is_true()
	m.report(ProfileFixtures.id(2), "Bo", "x".repeat(500), 1000.0)
	assert_int(m.reports.size()).is_equal(1)
	assert_int(str(m.reports[0].reason).length()).is_equal(LocalModeration.REASON_MAX)
	m.mute("not-an-id", "X")
	assert_int(m.muted.size()).is_equal(1)
