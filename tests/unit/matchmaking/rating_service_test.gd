extends GdUnitTestSuite
## W17-MM: team rating updates (worked example from an independent
## reference implementation), deviation scaling, void, leaver, bots, dodge,
## calibration and medal bands.

const NOW := 1_800_000_000
const A_SEED: Array = [[1500.0, 350.0], [1600.0, 80.0], [1400.0, 200.0], [1550.0, 120.0], [1450.0, 300.0]]
const B_SEED: Array = [[1520.0, 100.0], [1480.0, 150.0], [1500.0, 90.0], [1510.0, 200.0], [1490.0, 60.0]]


static func _id(n: int) -> String:
	return "%032x" % n


func _rules() -> MatchmakingRulesDef:
	var r := MatchmakingRulesDef.new()
	r.queues = MatchmakingRulesDef.standard_queues()
	return r


func _seed(store: RatingStore, base: int, seeds: Array) -> Array:
	var ids: Array = []
	for i in seeds.size():
		var id := _id(base + i)
		store.put_entry(id, &"normal", {"rating": seeds[i][0], "rd": seeds[i][1], "vol": 0.06, "games": 20, "updated_at": 0})
		ids.append(id)
	return ids


func test_worked_team_example() -> void:
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, _rules())
	var a := _seed(store, 1, A_SEED)
	var b := _seed(store, 100, B_SEED)
	var res := svc.apply_result(&"normal", a, b, 0, NOW)
	assert_int(res.size()).is_equal(10)
	assert_float(store.get_entry(a[0], &"normal").rating).is_equal_approx(1674.643, 0.01)
	assert_float(store.get_entry(a[0], &"normal").rd).is_equal_approx(256.167, 0.01)
	assert_float(store.get_entry(a[1], &"normal").rating).is_equal_approx(1616.558, 0.01)
	assert_float(store.get_entry(b[1], &"normal").rating).is_equal_approx(1433.374, 0.01)
	assert_float(store.get_entry(b[4], &"normal").rating).is_equal_approx(1481.594, 0.01)
	assert_float(store.get_entry(b[4], &"normal").rd).is_equal_approx(60.304, 0.01)
	assert_int(store.get_entry(a[0], &"normal").games).is_equal(21)


func test_change_scales_with_own_deviation() -> void:
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, _rules())
	var a := _seed(store, 1, A_SEED)
	var b := _seed(store, 100, B_SEED)
	var res := svc.apply_result(&"normal", a, b, 0, NOW)
	# Same team, same expected score: RD 350 moves far more than RD 80.
	assert_float(res[a[0]].delta).is_greater(res[a[1]].delta * 3.0)


func test_void_changes_nothing() -> void:
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, _rules())
	var a := _seed(store, 1, A_SEED)
	var b := _seed(store, 100, B_SEED)
	assert_dict(svc.apply_result(&"normal", a, b, 0, NOW, [], true)).is_empty()
	assert_float(store.get_entry(a[0], &"normal").rating).is_equal(1500.0)
	assert_int(store.get_entry(a[0], &"normal").games).is_equal(20)


func test_leaver_rule() -> void:
	var ref_store := MemoryRatingStore.new()
	var ref := RatingService.new(ref_store, _rules())
	var ra := _seed(ref_store, 1, A_SEED)
	var rb := _seed(ref_store, 100, B_SEED)
	var normal := ref.apply_result(&"normal", ra, rb, 1, NOW)  # A loses, nobody left
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, _rules())
	var a := _seed(store, 1, A_SEED)
	var b := _seed(store, 100, B_SEED)
	var res := svc.apply_result(&"normal", a, b, 1, NOW, [a[2]])
	var rules := _rules()
	assert_float(res[a[2]].delta).is_equal_approx(normal[a[2]].delta - rules.leaver_penalty, 0.001)
	assert_float(res[a[0]].delta).is_equal_approx(normal[a[0]].delta * rules.leaver_teammate_loss_scale, 0.001)
	assert_float(res[b[0]].delta).is_equal_approx(normal[b[0]].delta, 0.001)


func test_leaver_loses_even_if_team_wins() -> void:
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, _rules())
	var a := _seed(store, 1, A_SEED)
	var b := _seed(store, 100, B_SEED)
	var res := svc.apply_result(&"normal", a, b, 0, NOW, [a[3]])
	assert_float(res[a[3]].delta).is_less(-15.0)
	assert_float(res[a[0]].delta).is_greater(0.0)


func test_bot_match_is_unrated_by_default() -> void:
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, _rules())
	var a := _seed(store, 1, A_SEED)
	var b := _seed(store, 100, B_SEED.slice(0, 4))
	b.append(MatchmakingRulesDef.BOT_PREFIX + "1")
	assert_dict(svc.apply_result(&"normal", a, b, 0, NOW)).is_empty()


func test_bot_match_rated_when_enabled_never_stores_bot() -> void:
	var rules := _rules()
	rules.rate_bot_matches = true
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, rules)
	var a := _seed(store, 1, A_SEED)
	var bot := MatchmakingRulesDef.BOT_PREFIX + "1"
	var res := svc.apply_result(&"normal", a, [bot], 0, NOW)
	assert_int(res.size()).is_equal(5)
	assert_bool(res.has(bot)).is_false()
	assert_int(store.ids().size()).is_equal(5)


func test_new_player_defaults_and_calibration() -> void:
	var rules := _rules()
	rules.calibration_games = 3
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, rules)
	var me := _id(7)
	var foe := _id(8)
	assert_float(svc.entry(me, &"ranked").rating).is_equal(1500.0)
	assert_int(svc.visible_rating(me)).is_equal(-1)
	for i in 3:
		assert_bool(svc.ranked_display(me).calibrating).is_true()
		svc.apply_result(&"ranked", [me], [foe], 0, NOW + i)
	var d := svc.ranked_display(me)
	assert_bool(d.calibrating).is_false()
	assert_int(d.rating).is_equal(roundi(store.get_entry(me, &"ranked").rating))
	assert_str(d.medal.name).is_not_empty()


func test_tracks_are_separate() -> void:
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, _rules())
	svc.apply_result(&"all_random", [_id(1)], [_id(2)], 0, NOW)
	assert_dict(store.get_entry(_id(1), &"normal")).is_empty()
	assert_dict(store.get_entry(_id(1), &"ranked")).is_empty()
	assert_float(store.get_entry(_id(1), &"all_random").rating).is_greater(1500.0)


func test_dodge_penalty() -> void:
	var store := MemoryRatingStore.new()
	var svc := RatingService.new(store, _rules())
	assert_float(svc.apply_dodge_penalty(_id(3), &"ranked", NOW)).is_equal(-5.0)
	assert_float(store.get_entry(_id(3), &"ranked").rating).is_equal(1495.0)
	assert_int(store.get_entry(_id(3), &"ranked").games).is_equal(0)


func test_medal_bands() -> void:
	var svc := RatingService.new(MemoryRatingStore.new(), _rules())
	assert_str(svc.medal_for(0).label).is_equal("Iron I")
	assert_str(svc.medal_for(1099).label).is_equal("Iron V")  # clamped to the band
	assert_str(svc.medal_for(1300).label).is_equal("Silver I")
	assert_str(svc.medal_for(1385).label).is_equal("Silver III")
	assert_str(svc.medal_for(2600).label).is_equal("Master")
	assert_int(svc.medal_for(1500).band).is_equal(3)
	var names: Array = []
	for b in MatchmakingRulesDef.load_default().medal_bands:
		names.append(b.name)
	assert_array(names).is_equal(["Iron", "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Master"])
