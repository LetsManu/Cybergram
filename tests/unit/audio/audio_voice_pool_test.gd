extends GdUnitTestSuite
## W21-A1: voice limit — free slot first, per-event max_voices steals its own
## oldest, a full pool steals the lowest-priority oldest, never a more important voice.


func test_free_slots_are_used_first() -> void:
	var p := AudioVoicePool.new(3)
	assert_int(p.claim(&"a", 1, 4, 0)).is_equal(0)
	assert_int(p.claim(&"b", 1, 4, 1)).is_equal(1)
	assert_int(p.claim(&"c", 1, 4, 2)).is_equal(2)


func test_event_limit_steals_its_own_oldest() -> void:
	var p := AudioVoicePool.new(4)
	var first := p.claim(&"shot", 1, 2, 0)
	p.claim(&"shot", 1, 2, 1)
	var third := p.claim(&"shot", 1, 2, 2)
	assert_int(third).is_equal(first)
	assert_int(p.count(&"shot")).is_equal(2)


func test_full_pool_steals_lowest_priority_oldest() -> void:
	var p := AudioVoicePool.new(3)
	p.claim(&"hi", 0, 4, 0)
	var low_old := p.claim(&"lo1", 3, 4, 1)
	p.claim(&"lo2", 3, 4, 2)
	assert_int(p.claim(&"new", 1, 4, 3)).is_equal(low_old)
	assert_str(String(p.event_at(low_old))).is_equal("new")


func test_more_important_voices_are_never_stolen() -> void:
	var p := AudioVoicePool.new(2)
	p.claim(&"a", 0, 4, 0)
	p.claim(&"b", 0, 4, 1)
	assert_int(p.claim(&"c", 2, 4, 2)).is_equal(-1)
	# equal priority steals the oldest
	assert_int(p.claim(&"d", 0, 4, 3)).is_equal(0)


func test_released_slot_is_reused() -> void:
	var p := AudioVoicePool.new(2)
	p.claim(&"a", 0, 4, 0)
	p.claim(&"b", 0, 4, 1)
	p.release(1)
	assert_int(p.claim(&"c", 3, 4, 2)).is_equal(1)


func test_same_millisecond_falls_back_to_call_order() -> void:
	var p := AudioVoicePool.new(2)
	p.claim(&"a", 2, 4, 5)
	p.claim(&"b", 2, 4, 5)
	assert_int(p.claim(&"c", 2, 4, 5)).is_equal(0)
