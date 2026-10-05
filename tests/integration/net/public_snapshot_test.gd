extends GdUnitTestSuite
## W20-WEB public snapshot: MatchmakingFront.leaderboard() lists only
## opted-in, calibrated ranked players (sorted, capped, no ids), the snapshot
## carries counts and queue estimates, the file is written atomically on the
## configured cadence, and an opt-out or a deleted account leaves the
## leaderboard at the next recomputation.

const ACC_DIR := "user://test_public_snapshot_accounts"
const OUT_DIR := "user://test_public_snapshot_out"
const T0 := 1_800_000_000.0

var _acc: AccountService
var _ratings: RatingService
var _front: MatchmakingFront
var _rules: MatchmakingRulesDef
var _t: float = T0


func before_test() -> void:
	_wipe(ACC_DIR)
	_wipe(OUT_DIR)
	_t = T0
	var st := FileAccountStore.new(ACC_DIR)
	st.open()
	_acc = AccountService.new(st, AuthRulesDef.new(), true, PresenceRegistry.new())
	_rules = MatchmakingRulesDef.new()
	_rules.queues = MatchmakingRulesDef.standard_queues()
	_ratings = RatingService.new(MemoryRatingStore.new(), _rules)
	_front = MatchmakingFront.new(null, _acc, null, _ratings, ReportStore.new("", _rules),
		MatchHistoryStore.new("", _rules), _rules, "")
	_front.clock = func() -> float: return _t
	_front.log_fn = func(_l: String) -> void: pass


func after_test() -> void:
	_wipe(ACC_DIR)
	_wipe(OUT_DIR)


func _wipe(dir: String) -> void:
	var d := ProjectSettings.globalize_path(dir)
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)


## Account `n` named `name` with a ranked rating after `games` games.
func _player(n: int, name: String, rating: float, games: int, public: bool) -> String:
	var id := ProfileFixtures.id(n)
	var a := AccountStore.new_account(id, name.to_lower(), {"algo": "x", "hash": "", "salt": "", "iterations": 1},
		{"display_name": name, "emblem": 0, "accent": 0, "favourite_hero": ""}, int(T0))
	AccountService.set_leaderboard_public(a, public)
	_acc.store.put(a)
	_ratings.store.put_entry(id, RatingService.TRACK_RANKED, {"rating": rating, "rd": 60.0, "vol": 0.06,
		"games": games, "updated_at": 0})
	return id


func _snapshot() -> Dictionary:
	var f := ProjectSettings.globalize_path(OUT_DIR).path_join(PublicSnapshot.FILE_NAME)
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
	return v if v is Dictionary else {}


func test_leaderboard_lists_only_opted_in_calibrated_players_sorted() -> void:
	var cal := _rules.calibration_games
	_player(1, "Vex", 1720.4, cal + 3, true)
	_player(2, "Hidden", 2300.0, cal + 30, false)   # did not opt in
	_player(3, "Rookie", 1900.0, cal - 1, true)     # still calibrating
	_player(4, "Ash", 1720.0, cal, true)            # ties Vex on 1720: name decides
	_player(5, "Iris", 2150.0, cal + 9, true)
	var rows := _front.leaderboard(10)
	assert_array(rows.map(func(r: Dictionary) -> String: return r.name)).contains_exactly(["Iris", "Ash", "Vex"])
	assert_int(int(rows[0].rank)).is_equal(1)
	assert_int(int(rows[0].rating)).is_equal(2150)
	assert_str(str(rows[0].medal)).is_equal("Master")
	assert_str(str(rows[2].band)).is_equal("Platinum")
	for r: Dictionary in rows:
		assert_array(r.keys()).contains_exactly_in_any_order(["rank", "name", "rating", "medal", "band"])


func test_leaderboard_is_capped_to_top_n() -> void:
	for i in 6:
		_player(10 + i, "P%d" % i, 1500.0 + i * 10.0, _rules.calibration_games, true)
	var rows := _front.leaderboard(3)
	assert_int(rows.size()).is_equal(3)
	assert_str(str(rows[0].name)).is_equal("P5")
	assert_array(_front.leaderboard(0)).is_empty()


func test_snapshot_has_counts_queues_and_no_ids() -> void:
	var id := _player(1, "Vex", 1720.0, _rules.calibration_games, true)
	var d := PublicSnapshot.build(_front, 7, int(T0), _front.leaderboard(5), int(T0))
	assert_int(int(d.schema)).is_equal(PublicSnapshot.SCHEMA)
	assert_str(str(d.status)).is_equal("up")
	assert_int(int(d.players_online)).is_equal(7)
	assert_int(int(d.matches_running)).is_equal(0)
	var qids: Array = (d.queues as Array).map(func(q: Dictionary) -> String: return q.id)
	assert_array(qids).contains_exactly(["normal_5v5", "ranked_5v5", "all_random_3v3"])
	assert_int(int(d.queues[0].estimated_wait_s)).is_equal(roundi(_rules.default_wait_estimate_s))
	var text := JSON.stringify(d)
	assert_str(text).not_contains(id)
	assert_str(text).not_contains("vex\"")  # the username (lower case) never leaves


func test_tick_writes_on_cadence_and_drops_opt_outs_and_deleted_accounts() -> void:
	var online := OnlineRulesDef.new()
	online.public_snapshot_every_s = 5.0
	online.public_leaderboard_every_s = 60.0
	var snap := PublicSnapshot.new(ProjectSettings.globalize_path(OUT_DIR), online)
	var vex := _player(1, "Vex", 1720.0, _rules.calibration_games, true)
	_player(2, "Ash", 1600.0, _rules.calibration_games, true)
	assert_bool(snap.tick(0.1, _front, 3)).is_true()  # the first tick writes at once
	assert_bool(FileAccess.file_exists(snap.path() + ".tmp")).is_false()
	var d := _snapshot()
	assert_int(int(d.players_online)).is_equal(3)
	assert_int((d.leaderboard.entries as Array).size()).is_equal(2)
	assert_bool(snap.tick(1.0, _front, 4)).is_false()  # within the cadence: no write
	# Vex opts out, Ash deletes the account: gone after the next leaderboard pass.
	var a := _acc.store.get_by_id(vex)
	AccountService.set_leaderboard_public(a, false)
	_acc.store.put(a)
	_acc.store.delete_cascade(ProfileFixtures.id(2))
	_t += 10.0
	assert_bool(snap.tick(5.0, _front, 4)).is_true()
	assert_int((_snapshot().leaderboard.entries as Array).size()).is_equal(2)  # not yet recomputed
	_t += 60.0
	for i in 12:
		snap.tick(5.0, _front, 4)
	d = _snapshot()
	assert_array(d.leaderboard.entries).is_empty()
	assert_int(int(d.updated)).is_equal(int(_t))


func test_disabled_without_a_directory() -> void:
	var snap := PublicSnapshot.new("", OnlineRulesDef.new())
	snap.dir = ""
	assert_bool(snap.enabled()).is_false()
	assert_bool(snap.tick(100.0, _front, 1)).is_false()
	assert_bool(snap.write_now("{}")).is_false()
