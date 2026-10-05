extends GdUnitTestSuite
## W17-MM: MemoryRatingStore / FileRatingStore: round trip, minimal data,
## atomic files, owner-only permissions, malformed input, account deletion.

const DIR := "user://test_ratings"


func before_test() -> void:
	_wipe()


func after_test() -> void:
	_wipe()


func _wipe() -> void:
	var d := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


static func _id(n: int) -> String:
	return "%032x" % n


static func _e(r: float) -> Dictionary:
	return {"rating": r, "rd": 120.0, "vol": 0.06, "games": 4, "updated_at": 1_800_000_000}


func test_memory_store_round_trip_and_copies() -> void:
	var st := MemoryRatingStore.new()
	assert_int(st.open()).is_equal(OK)
	assert_bool(st.put_entry(_id(1), &"ranked", _e(1600.0))).is_true()
	var got := st.get_entry(_id(1), &"ranked")
	got.rating = 0.0
	assert_float(st.get_entry(_id(1), &"ranked").rating).is_equal(1600.0)
	assert_dict(st.get_entry(_id(1), &"normal")).is_empty()


func test_rejects_bad_ids_and_entries() -> void:
	var st := MemoryRatingStore.new()
	assert_bool(st.put_entry("../../etc", &"ranked", _e(1.0))).is_false()
	assert_bool(st.put_entry(_id(1), &"", _e(1.0))).is_false()
	var extra := _e(1500.0)
	extra["ip"] = "198.51.100.4"
	assert_bool(st.put_entry(_id(1), &"ranked", extra)).is_false()
	assert_bool(st.put_entry(_id(1), &"ranked", {"rating": 1.0})).is_false()


func test_file_store_persists_and_reloads() -> void:
	var st := FileRatingStore.new(DIR)
	assert_int(st.open()).is_equal(OK)
	st.put_entry(_id(1), &"ranked", _e(1650.0))
	st.put_entry(_id(1), &"normal", _e(1400.0))
	st.put_entry(_id(2), &"all_random", _e(1500.0))
	var again := FileRatingStore.new(DIR)
	assert_int(again.open()).is_equal(OK)
	assert_int(again.ids().size()).is_equal(2)
	assert_float(again.get_entry(_id(1), &"ranked").rating).is_equal(1650.0)
	assert_int(again.get_entry(_id(1), &"normal").games).is_equal(4)
	var path := ProjectSettings.globalize_path(DIR).path_join(_id(1) + ".json")
	var body := FileAccess.get_file_as_string(path)
	assert_bool(body.contains("ip") or body.contains("username")).is_false()
	if OS.get_name() == "Linux":
		assert_int(FileAccess.get_unix_permissions(path) & 63).is_equal(0)


func test_file_store_skips_garbage_and_leftover_tmp() -> void:
	var d := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(d)
	var f := FileAccess.open(d.path_join(_id(5) + ".json"), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	f = FileAccess.open(d.path_join(_id(6) + ".json.tmp"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	var st := FileRatingStore.new(DIR)
	assert_int(st.open()).is_equal(OK)
	assert_int(st.ids().size()).is_equal(0)
	assert_bool(FileAccess.file_exists(d.path_join(_id(6) + ".json.tmp"))).is_false()


func test_erase_account_deletes_file() -> void:
	var st := FileRatingStore.new(DIR)
	st.open()
	st.put_entry(_id(1), &"ranked", _e(1650.0))
	assert_bool(st.erase_account(_id(1))).is_true()
	assert_bool(st.erase_account(_id(1))).is_false()
	var again := FileRatingStore.new(DIR)
	again.open()
	assert_int(again.ids().size()).is_equal(0)
