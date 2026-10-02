extends GdUnitTestSuite
## InterpolationBuffer: interpolation between ticks and capped extrapolation.


func _buf() -> InterpolationBuffer:
	var b := InterpolationBuffer.new(1)
	b.push(10, Vector3(0, 0, 0), 0.0, false)
	b.push(11, Vector3(1, 0, 0), 0.0, false)
	b.push(12, Vector3(2, 0, 0), 0.0, true)
	return b


func test_sample_between_ticks_interpolates_linearly() -> void:
	var b := _buf()
	assert_bool(b.sample(10.5)).is_true()
	assert_vector(b.position).is_equal_approx(Vector3(0.5, 0, 0), Vector3.ONE * 1e-5)


func test_sample_past_newest_extrapolates_at_most_cap() -> void:
	var b := _buf()
	b.sample(15.0)
	assert_vector(b.position).is_equal_approx(Vector3(3, 0, 0), Vector3.ONE * 1e-5)


func test_sample_before_oldest_clamps_to_oldest() -> void:
	var b := _buf()
	b.sample(2.0)
	assert_vector(b.position).is_equal(Vector3.ZERO)


func test_out_of_order_push_is_ignored() -> void:
	var b := _buf()
	b.push(11, Vector3(100, 0, 0), 0.0, false)
	b.sample(11.0)
	assert_vector(b.position).is_equal(Vector3(1, 0, 0))


func test_empty_buffer_reports_no_sample() -> void:
	assert_bool(InterpolationBuffer.new(1).sample(1.0)).is_false()
