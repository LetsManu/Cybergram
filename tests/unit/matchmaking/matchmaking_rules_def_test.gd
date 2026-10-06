extends GdUnitTestSuite
## W17-MM: MatchmakingRulesDef loads from data, holds the four design queues
## and validates its own invariants (ranked never allows bots, draft sizes).


func test_shipped_rules_load_and_are_valid() -> void:
	var r := MatchmakingRulesDef.load_default()
	assert_array(Array(r.validate())).is_empty()
	assert_int(r.queues.size()).is_equal(4)
	assert_float(r.ready_check_s).is_equal(12.0)  # P3: 12 s (design consult 2026-10-06)
	assert_array(Array(r.draft_order)).is_equal([1, 2, 2, 2, 2, 1])


func test_standard_queues_match_the_design_table() -> void:
	var r := MatchmakingRulesDef.load_default()
	var ranked := r.queue(&"ranked_5v5")
	assert_bool(ranked.ranked).is_true()
	assert_bool(ranked.bots_allowed).is_false()
	assert_bool(r.queue(&"normal_5v5").bots_allowed).is_true()
	var aram := r.queue(&"all_random_3v3")
	assert_int(aram.team_size).is_equal(3)
	assert_int(aram.pick_mode).is_equal(MatchQueueDef.PickMode.ALL_RANDOM)
	assert_bool(r.queue(&"custom").matchmade).is_false()
	assert_object(r.queue(&"nope")).is_null()


func test_validate_flags_ranked_bots_and_bad_draft() -> void:
	var r := MatchmakingRulesDef.new()
	r.queues = MatchmakingRulesDef.standard_queues()
	r.queue(&"ranked_5v5").bots_allowed = true
	r.draft_order = PackedInt32Array([1, 2, 2])
	var v := r.validate()
	assert_bool(v.size() >= 2).is_true()
	assert_bool(" ".join(v).contains("allows bots")).is_true()
	assert_bool(" ".join(v).contains("draft_order")).is_true()
