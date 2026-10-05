extends GdUnitTestSuite
## W18-LIFE: route sampling (mirrored by the mover shader) and the fallback
## routes staying out of playable space.


func _square() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), Vector3(0, 0, 10)])


func test_closed_sample_wraps() -> void:
	var p := _square()
	assert_vector(TrafficPaths.sample(p, 0.0, true)).is_equal(Vector3(0, 0, 0))
	assert_vector(TrafficPaths.sample(p, 1.0, true)).is_equal(Vector3(0, 0, 0))
	assert_vector(TrafficPaths.sample(p, 0.125, true)).is_equal_approx(Vector3(5, 0, 0), Vector3(0.001, 0.001, 0.001))
	# Last segment closes the loop back to the start.
	assert_vector(TrafficPaths.sample(p, 0.875, true)).is_equal_approx(Vector3(0, 0, 5), Vector3(0.001, 0.001, 0.001))
	assert_vector(TrafficPaths.sample(p, -0.875, true)).is_equal_approx(Vector3(5, 0, 0), Vector3(0.001, 0.001, 0.001))


func test_open_sample_clamps() -> void:
	var p := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, 20)])
	assert_vector(TrafficPaths.sample(p, -1.0, false)).is_equal(Vector3(0, 0, 0))
	assert_vector(TrafficPaths.sample(p, 2.0, false)).is_equal(Vector3(0, 0, 20))
	assert_vector(TrafficPaths.sample(p, 0.75, false)).is_equal_approx(Vector3(0, 0, 15), Vector3(0.001, 0.001, 0.001))


func test_length() -> void:
	assert_float(TrafficPaths.length(_square(), true)).is_equal_approx(40.0, 0.001)
	assert_float(TrafficPaths.length(_square(), false)).is_equal_approx(30.0, 0.001)


func test_resample_is_even() -> void:
	var src := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(100, 0, 0)])
	var r := TrafficPaths.resample(src, false)
	assert_int(r.size()).is_equal(TrafficPaths.SAMPLES)
	assert_vector(r[0]).is_equal(Vector3(0, 0, 0))
	assert_vector(r[-1]).is_equal_approx(Vector3(100, 0, 0), Vector3(0.01, 0.01, 0.01))
	var spacing := 100.0 / (TrafficPaths.SAMPLES - 1)
	for i in r.size() - 1:
		assert_float(r[i].distance_to(r[i + 1])).is_equal_approx(spacing, 0.01)


func test_fallback_traffic_is_clear_of_play_and_varied() -> void:
	var routes := TrafficPaths.fallback_traffic(7)
	assert_int(routes.size()).is_equal(7)
	var heights := {}
	for r in routes:
		assert_int(r.size()).is_equal(TrafficPaths.SAMPLES)
		assert_bool(TrafficPaths.never_over_play(r)).is_true()
		heights[snappedf(r[0].y, 5.0)] = true
	assert_int(heights.size()).is_greater(3)


func test_fallback_drones_never_over_lanes() -> void:
	for r in TrafficPaths.fallback_drones(6):
		assert_bool(TrafficPaths.never_over_play(r)).is_true()


func test_fallback_train_and_birds_are_clear() -> void:
	assert_bool(TrafficPaths.never_over_play(TrafficPaths.fallback_train())).is_true()
	for r in TrafficPaths.fallback_birds():
		assert_bool(TrafficPaths.clear_of_play(r)).is_true()


func test_clear_of_play_detects_intrusion() -> void:
	assert_bool(TrafficPaths.clear_of_play(PackedVector3Array([Vector3(0, 5, -100)]))).is_false()
	assert_bool(TrafficPaths.clear_of_play(PackedVector3Array([Vector3(0, 80, -100)]))).is_true()
	assert_bool(TrafficPaths.never_over_play(PackedVector3Array([Vector3(0, 80, -100)]))).is_false()


func test_bake_matches_samples() -> void:
	var routes: Array[PackedVector3Array] = [TrafficPaths.oval(Vector3.ZERO, 200, 300, 50, 0, 0)]
	var img := TrafficPaths.bake(routes).get_image()
	assert_int(img.get_width()).is_equal(TrafficPaths.SAMPLES)
	var c := img.get_pixel(5, 0)
	assert_vector(Vector3(c.r, c.g, c.b)).is_equal_approx(routes[0][5], Vector3(0.01, 0.01, 0.01))


func test_train_schedule_gaps_and_determinism() -> void:
	for k in 50:
		var g := SkyTrainSchedule.gap(42, k)
		assert_float(g).is_between(SkyTrainSchedule.MIN_GAP_S, SkyTrainSchedule.MAX_GAP_S)
		assert_float(g).is_equal(SkyTrainSchedule.gap(42, k))
	var a := SkyTrainSchedule.new(42)
	var b := SkyTrainSchedule.new(42)
	assert_float(a.progress(0.0)).is_equal(-1.0)
	var passes := 0
	var was := false
	for i in 3600:
		var t := float(i)
		var pa := a.progress(t)
		assert_float(pa).is_equal(b.progress(t))
		if pa >= 0.0 and not was:
			passes += 1
		was = pa >= 0.0
	# One hour at 60..120 s gaps: 30..60 passes.
	assert_int(passes).is_between(29, 60)


func test_train_schedule_rewinds() -> void:
	var s := SkyTrainSchedule.new(7)
	var first := s.current_start()
	s.progress(1000.0)
	assert_float(s.current_start()).is_greater(first)
	s.progress(first + 1.0)
	assert_float(s.progress(first + 1.0)).is_equal_approx(1.0 / SkyTrainSchedule.PASS_S, 0.0001)
