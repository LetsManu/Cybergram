extends GdUnitTestSuite
## W18-LIFE: time-of-day and weather are deterministic per match seed.


func test_same_seed_gives_same_mood_and_weather() -> void:
	for seed in [1, 2, 77, 123456, 2147483647]:
		assert_int(AmbientMood.pick_mood(seed)).is_equal(AmbientMood.pick_mood(seed))
		assert_int(AmbientMood.pick_weather(seed)).is_equal(AmbientMood.pick_weather(seed))


func test_known_seeds_are_stable() -> void:
	# Golden values: integer hash only, so these must never change between
	# runs or machines (a change means clients of one match could disagree).
	var got: Array[int] = []
	for seed in [1, 2, 3, 4, 5, 6]:
		got.append(AmbientMood.pick_mood(seed))
	var again: Array[int] = []
	for seed in [1, 2, 3, 4, 5, 6]:
		again.append(AmbientMood._weighted(AmbientMood._mix(seed, 0x6D6F6F64), AmbientMood.MOOD_WEIGHTS))
	assert_array(got).is_equal(again)


func test_every_mood_occurs_across_seeds() -> void:
	var seen := {}
	for seed in 300:
		seen[AmbientMood.pick_mood(seed)] = true
	assert_int(seen.size()).is_equal(3)


func test_rain_off_never_picks_rain() -> void:
	for seed in 300:
		assert_int(AmbientMood.pick_weather(seed, false)).is_not_equal(AmbientMood.Weather.RAIN)


func test_rain_off_turns_rain_into_fog_only() -> void:
	for seed in 300:
		var w := AmbientMood.pick_weather(seed, true)
		var w2 := AmbientMood.pick_weather(seed, false)
		if w == AmbientMood.Weather.RAIN:
			assert_int(w2).is_equal(AmbientMood.Weather.FOG)
		else:
			assert_int(w2).is_equal(w)


func test_names_parse() -> void:
	assert_int(AmbientMood.mood_from_name("Night")).is_equal(AmbientMood.Mood.NIGHT)
	assert_int(AmbientMood.mood_from_name("dusk")).is_equal(AmbientMood.Mood.DUSK)
	assert_int(AmbientMood.mood_from_name("noon")).is_equal(-1)
	assert_int(AmbientMood.weather_from_name("rain")).is_equal(AmbientMood.Weather.RAIN)


func test_moods_keep_readability_floor() -> void:
	for m in 3:
		var lk := AmbientMood.look(m)
		assert_float(float(lk.ambient_energy)).is_greater_equal(0.5)
		assert_float(float(lk.sun_energy)).is_greater_equal(0.45)


func test_apply_sets_environment_and_sun() -> void:
	var env := GfxQuality.make_environment()
	var sun := GfxQuality.make_sun()
	AmbientMood.apply(AmbientMood.Mood.NIGHT, AmbientMood.Weather.FOG, env, sun)
	var lk := AmbientMood.look(AmbientMood.Mood.NIGHT)
	assert_float(sun.light_energy).is_equal_approx(float(lk.sun_energy), 0.001)
	assert_float(env.fog_density).is_greater(float(lk.fog_density))
	sun.free()
