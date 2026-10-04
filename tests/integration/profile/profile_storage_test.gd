extends GdUnitTestSuite
## Local storage and data rights: profile / friends / moderation save + load,
## "Export my data" (readable JSON) and "Delete my profile & data". Uses
## throwaway user:// files and removes them afterwards.

const DIR := "user://test_profile_storage"

var _files: LocalData.Files


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_files = LocalData.Files.new()
	_files.profile = DIR + "/profile.cfg"
	_files.friends = DIR + "/friends.cfg"
	_files.moderation = DIR + "/moderation.cfg"
	_files.menu = DIR + "/menu.cfg"


func after_test() -> void:
	LocalData.delete_all(_files, DIR + "/export.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_profile_save_load_round_trip_with_consent() -> void:
	var p := PlayerProfile.create("Neo", 5, 3)
	p.privacy_ack = PlayerProfile.PRIVACY_VERSION
	assert_int(p.save(_files.profile)).is_equal(OK)
	var q := PlayerProfile.load_or_null(_files.profile)
	assert_object(q).is_not_null()
	assert_str(q.id).is_equal(p.id)
	assert_str(q.key).is_equal(p.key)
	assert_str(q.name).is_equal("Neo")
	assert_int(q.emblem).is_equal(5)
	assert_int(q.accent).is_equal(3)
	assert_bool(q.can_play_online()).is_true()


func test_missing_or_tampered_profile_loads_null() -> void:
	assert_object(PlayerProfile.load_or_null(_files.profile)).is_null()
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "id", ProfileFixtures.id(1))
	cfg.set_value("profile", "key", ProfileFixtures.id(2))
	cfg.set_value("profile", "name", "<script>")
	cfg.save(_files.profile)
	assert_object(PlayerProfile.load_or_null(_files.profile)).is_null()


func test_friends_and_moderation_round_trip() -> void:
	var fl := FriendList.new()
	fl.add("Trin#0B0B")
	fl.add_known(ProfileFixtures.id(3), "Ann")
	fl.save(_files.friends)
	var back := FriendList.load_from(_files.friends)
	assert_int(back.friends.size()).is_equal(2)
	assert_object(back.find_id(ProfileFixtures.id(3))).is_not_null()
	var m := LocalModeration.new()
	m.mute(ProfileFixtures.id(4), "Bo")
	m.report(ProfileFixtures.id(4), "Bo", "spam", 1000.0)
	m.save(_files.moderation)
	var m2 := LocalModeration.load_from(_files.moderation)
	assert_bool(m2.is_muted(ProfileFixtures.id(4))).is_true()
	assert_int(m2.reports.size()).is_equal(1)


func test_export_writes_readable_json_with_everything() -> void:
	ProfileFixtures.profile(1, "Neo").save(_files.profile)
	var fl := FriendList.new()
	fl.add_known(ProfileFixtures.id(3), "Ann")
	fl.save(_files.friends)
	var m := LocalModeration.new()
	m.mute(ProfileFixtures.id(4), "Bo")
	m.save(_files.moderation)
	var out := LocalData.export_json(_files, DIR + "/export.json")
	assert_str(out).is_not_empty()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/export.json"))
	assert_bool(data is Dictionary).is_true()
	assert_str(data.profile.display_name).is_equal("Neo")
	assert_str(data.profile.player_id).is_equal(ProfileFixtures.id(1))
	assert_int(data.friends.size()).is_equal(1)
	assert_bool(data.muted.has(ProfileFixtures.id(4))).is_true()


func test_delete_removes_every_local_file() -> void:
	ProfileFixtures.profile(1, "Neo").save(_files.profile)
	FriendList.new().save(_files.friends)
	LocalModeration.new().save(_files.moderation)
	var menu := ConfigFile.new()
	menu.set_value("menu", "hero_id", "brannoc")
	menu.save(_files.menu)
	LocalData.export_json(_files, DIR + "/export.json")
	var n := LocalData.delete_all(_files, DIR + "/export.json")
	assert_int(n).is_equal(5)
	for p in _files.all():
		assert_bool(FileAccess.file_exists(p)).is_false()
	assert_bool(FileAccess.file_exists(DIR + "/export.json")).is_false()
	assert_object(PlayerProfile.load_or_null(_files.profile)).is_null()
