extends GdUnitTestSuite
## W21-A1: MixDucker (weapon duck on Ambient within 15 m, big-moment duck on
## Music, glide) and AmbientZoneMixer (6 m positional crossfade, lane default).

func _mix() -> AudioMixDef:
	return load("res://assets/data/audio/audio_mix.tres") as AudioMixDef


func test_weapon_near_ducks_ambient_then_releases() -> void:
	var d := MixDucker.new(_mix())
	d.note_weapon(30.0)
	d.step(0.1)
	assert_float(d.ambient_db).is_equal(0.0)
	d.note_weapon(10.0)
	for i in 5:
		d.step(0.02)
	assert_float(d.ambient_db).is_equal_approx(-3.0, 0.01)
	for i in 100:
		d.step(0.02)
	assert_float(d.ambient_db).is_equal_approx(0.0, 0.01)


func test_big_moment_ducks_music_four_db() -> void:
	var d := MixDucker.new(_mix())
	d.note_big_moment()
	for i in 10:
		d.step(0.02)
	assert_float(d.music_db).is_equal_approx(-4.0, 0.01)


func test_zone_weights_crossfade_over_six_metres() -> void:
	var m := AmbientZoneMixer.new()
	m.crossfade_m = 6.0
	m.add_circle(&"base", Vector3.ZERO, 10.0)
	m.add_rect(&"water", Rect2(100, -5, 10, 10))
	var w := m.weights(Vector3(5, 0, 0))
	assert_float(w[&"base"]).is_equal(1.0)
	assert_float(w[&"lane"]).is_equal(0.0)
	w = m.weights(Vector3(13, 0, 0))  # 3 m outside: half way
	assert_float(w[&"base"]).is_equal_approx(0.5, 0.001)
	assert_float(w[&"lane"]).is_equal_approx(0.5, 0.001)
	w = m.weights(Vector3(50, 0, 0))
	assert_float(w[&"lane"]).is_equal(1.0)
	w = m.weights(Vector3(105, 3, 0))
	assert_float(w[&"water"]).is_equal(1.0)


func test_zones_from_the_front_map() -> void:
	var md := load("res://assets/data/match/map_front.tres") as MapDef
	assert_object(md).is_not_null()
	assert_int(md.hqs.size()).is_greater(0)
	var m := AmbientZoneMixer.from_map(md, 24.0, 6.0)
	var w := m.weights(md.hqs[0].sanctum)
	assert_float(w[&"base"]).is_equal(1.0)
