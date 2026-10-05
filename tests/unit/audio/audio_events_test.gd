extends GdUnitTestSuite
## W21-A1: AudioEvents — deterministic variation from an injected RNG, owner
## filter, cooldown (fake clock), max-distance cull, night-mode offset, bounded nodes.

var _now: int = 0


func _bank() -> AudioEventBank:
	var d := AudioEventBankDef.new()
	d.pool_2d = 4
	d.pool_3d = 4
	d.pool_loops = 2
	var shot := AudioEventDef.new()
	shot.id = &"shot"
	shot.folder = "weapons"
	shot.file_stem = "weapons_rifle_shot"
	shot.vol_jitter_db = 2.0
	shot.pitch_jitter = 0.1
	shot.owner_filter = AudioEventDef.OwnerFilter.OWN
	var far := AudioEventDef.new()
	far.id = &"far"
	far.folder = "weapons"
	far.file_stem = "weapons_rifle_shot"
	far.spatial = AudioEventDef.Spatial.POSITIONAL_3D
	far.max_distance_m = 20.0
	var cd := AudioEventDef.new()
	cd.id = &"cd"
	cd.folder = "ui"
	cd.file_stem = "ui_menu_click"
	cd.cooldown_ms = 100
	var big := AudioEventDef.new()
	big.id = &"big"
	big.folder = "abilities/shared"
	big.file_stem = "abilities_shared_explosion"
	big.vol_jitter_db = 0.0
	big.night_db = -4.0
	d.events = [shot, far, cd, big]
	return AudioEventBank.new(d)


func _player(seed_: int) -> AudioEvents:
	var ev := AudioEvents.new(_bank())
	ev.rng.seed = seed_
	ev.clock_fn = func() -> int: return _now
	var gs := GameSettings.new()
	ev.settings = gs
	add_child(auto_free(ev))
	return ev


func test_variation_is_deterministic_with_the_same_seed() -> void:
	var a := _player(7)
	var b := _player(7)
	for i in 20:
		var pa := a.play(&"shot", AudioEventDef.OwnerFilter.OWN) as AudioStreamPlayer
		var pb := b.play(&"shot", AudioEventDef.OwnerFilter.OWN) as AudioStreamPlayer
		assert_object(pa.stream).is_same(pb.stream)
		assert_float(pa.pitch_scale).is_equal(pb.pitch_scale)
		assert_float(pa.volume_db).is_equal(pb.volume_db)
		assert_float(absf(pa.volume_db)).is_less_equal(2.0)


func test_owner_filter_rejects_other_relations() -> void:
	var ev := _player(1)
	assert_object(ev.play(&"shot", AudioEventDef.OwnerFilter.ENEMY)).is_null()
	assert_object(ev.play(&"shot", AudioEventDef.OwnerFilter.OWN)).is_not_null()


func test_cooldown_uses_the_injected_clock() -> void:
	var ev := _player(1)
	_now = 1000
	assert_object(ev.play(&"cd")).is_not_null()
	_now = 1050
	assert_object(ev.play(&"cd")).is_null()
	_now = 1101
	assert_object(ev.play(&"cd")).is_not_null()


func test_positional_event_beyond_max_distance_is_culled() -> void:
	var ev := _player(1)
	ev.listener_fn = func() -> Variant: return Vector3.ZERO
	assert_object(ev.play(&"far", 0, Vector3(0, 0, 25))).is_null()
	assert_object(ev.play(&"far", 0, Vector3(0, 0, 15))).is_not_null()


func test_night_mode_lowers_big_events() -> void:
	var ev := _player(1)
	var day := (ev.play(&"big") as AudioStreamPlayer).volume_db
	ev.settings.night_mode = true
	var night := (ev.play(&"big") as AudioStreamPlayer).volume_db
	assert_float(night).is_equal_approx(day - 4.0, 0.001)


func test_node_count_is_bounded() -> void:
	var ev := _player(3)
	var n := ev.get_child_count()
	for i in 100:
		ev.play(&"shot", AudioEventDef.OwnerFilter.OWN)
		ev.play(&"far", 0, Vector3.ZERO)
	assert_int(ev.get_child_count()).is_equal(n)
	assert_int(n).is_equal(4 + 4 + 2)
