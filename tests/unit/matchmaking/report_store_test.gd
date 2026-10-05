extends GdUnitTestSuite
## W17-MM: reports (categories, one per target per match, retention purge),
## honour (positive, once per match), persistence and the review CLI.

const DIR := "user://test_reports"
const NOW := 1_800_000_000
const DAY := 86400
const PLAYERS: Array = ["a", "b", "c", "bot:1"]


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


func test_report_rules() -> void:
	var st := ReportStore.new()
	assert_int(st.report("m1", "a", "b", &"griefing", PLAYERS, NOW)).is_equal(ReportStore.Result.OK)
	assert_int(st.report("m1", "a", "b", &"cheating", PLAYERS, NOW)).is_equal(ReportStore.Result.E_DUPLICATE)
	assert_int(st.report("m2", "a", "b", &"cheating", PLAYERS, NOW)).is_equal(ReportStore.Result.OK)
	assert_int(st.report("m1", "c", "b", &"cheating", PLAYERS, NOW)).is_equal(ReportStore.Result.OK)
	assert_int(st.report("m1", "a", "a", &"cheating", PLAYERS, NOW)).is_equal(ReportStore.Result.E_SELF)
	assert_int(st.report("m1", "a", "x", &"cheating", PLAYERS, NOW)).is_equal(ReportStore.Result.E_NOT_IN_MATCH)
	assert_int(st.report("m1", "a", "bot:1", &"cheating", PLAYERS, NOW)).is_equal(ReportStore.Result.E_NOT_IN_MATCH)
	assert_int(st.report("m1", "a", "c", &"rude", PLAYERS, NOW)).is_equal(ReportStore.Result.E_CATEGORY)
	assert_int(st.list().size()).is_equal(3)


func test_honour_is_positive_and_once_per_match() -> void:
	var st := ReportStore.new()
	assert_int(st.honour("m1", "a", "b", PLAYERS, NOW)).is_equal(ReportStore.Result.OK)
	assert_int(st.honour("m1", "a", "c", PLAYERS, NOW)).is_equal(ReportStore.Result.E_DUPLICATE)
	assert_int(st.honour("m1", "b", "b", PLAYERS, NOW)).is_equal(ReportStore.Result.E_SELF)
	st.honour("m1", "c", "b", PLAYERS, NOW)
	assert_int(st.honour_count("b")).is_equal(2)
	assert_int(st.honour_count("a")).is_equal(0)


func test_retention_purge() -> void:
	var st := ReportStore.new()
	st.report("m1", "a", "b", &"afk", PLAYERS, NOW)
	st.report("m2", "a", "b", &"afk", PLAYERS, NOW + 10 * DAY)
	st.resolve("r1", "warned", NOW + DAY)
	assert_int(st.purge(NOW + 30 * DAY)).is_equal(0)
	assert_int(st.purge(NOW + 30 * DAY + 1)).is_equal(1)
	assert_int(st.list("").size()).is_equal(1)
	assert_str(st.list("")[0].match_id).is_equal("m2")


func test_resolve_and_erase_account() -> void:
	var st := ReportStore.new()
	st.report("m1", "a", "b", &"afk", PLAYERS, NOW)
	st.report("m1", "b", "c", &"afk", PLAYERS, NOW)
	assert_bool(st.resolve("r1", "maybe", NOW)).is_false()
	assert_bool(st.resolve("r1", "dismissed", NOW)).is_true()
	assert_int(st.list().size()).is_equal(1)
	st.honour("m1", "a", "b", PLAYERS, NOW)
	st.erase_account("b")
	assert_int(st.list("").size()).is_equal(0)
	assert_int(st.honour_count("b")).is_equal(0)


func test_persists_minimal_owner_only() -> void:
	var st := ReportStore.new(DIR)
	assert_int(st.open()).is_equal(OK)
	st.report("m1", "a", "b", &"cheating", PLAYERS, NOW)
	st.honour("m1", "a", "c", PLAYERS, NOW)
	var again := ReportStore.new(DIR)
	again.open()
	assert_int(again.list().size()).is_equal(1)
	assert_int(again.honour_count("c")).is_equal(1)
	assert_int(again.honour("m1", "a", "b", PLAYERS, NOW)).is_equal(ReportStore.Result.E_DUPLICATE)
	assert_int(again.report("m1", "c", "b", &"afk", PLAYERS, NOW)).is_equal(ReportStore.Result.OK)
	assert_str(again.list()[1].id).is_equal("r2")
	var path := ProjectSettings.globalize_path(DIR).path_join(ReportStore.FILE)
	var keys: Array = (JSON.parse_string(FileAccess.get_file_as_string(path)).reports[0] as Dictionary).keys()
	assert_array(keys).contains_exactly_in_any_order(["id", "match_id", "reporter", "target", "category",
		"created_at", "status", "resolution", "resolved_at"])
	if OS.get_name() == "Linux":
		assert_int(FileAccess.get_unix_permissions(path) & 63).is_equal(0)


func test_review_cli_commands() -> void:
	var st := ReportStore.new()
	st.report("m1", "a", "b", &"cheating", PLAYERS, NOW)
	st.report("m1", "c", "b", &"afk", PLAYERS, NOW)
	var out := ReportReview.run(st, ["list"], NOW)
	assert_int(out.code).is_equal(0)
	assert_str(out.text).contains("r1").contains("r2").contains("b  2")
	assert_int(ReportReview.run(st, ["resolve", "r1", "actioned"], NOW).code).is_equal(0)
	assert_str(ReportReview.run(st, ["list"], NOW).text).not_contains("r1 ")
	assert_str(ReportReview.run(st, ["list", "--all"], NOW).text).contains("(actioned)")
	assert_int(ReportReview.run(st, ["resolve", "r9", "warned"], NOW).code).is_equal(1)
	assert_int(ReportReview.run(st, ["bogus"], NOW).code).is_equal(2)
	assert_str(ReportReview.run(st, ["purge"], NOW + 31 * DAY).text).contains("purged 2")
	assert_str(ReportReview.run(st, ["list"], NOW + 31 * DAY).text).is_equal("no reports")
