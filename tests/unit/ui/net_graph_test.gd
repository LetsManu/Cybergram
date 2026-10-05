extends GdUnitTestSuite
## W16-NET net graph panel: builds in the UI kit style and shows the
## session's link figures (amber when poor).


func _graph() -> NetGraph:
	var g := NetGraph.new()
	add_child(g)
	return auto_free(g)


func test_shows_link_figures() -> void:
	var g := _graph()
	g.apply_stats({"ping_ms": 42, "loss_pct": 0.5, "jitter_ms": 3.0, "jitter_p95_ms": 12.0,
		"interp_ticks": 2.0, "interp_ms": 66.7, "kbps_in": 11.0, "kbps_snap": 10.2, "kbps_out": 2.4,
		"snap_avg": 341.0, "snap_max": 512, "sizes": PackedInt32Array([300, 512]), "budget": 1100, "mode": "UDP DTLS"})
	assert_str(g.value_text("ping")).is_equal("42 ms")
	assert_str(g.value_text("loss")).is_equal("0.5 %")
	assert_str(g.value_text("jitter")).is_equal("3 ms  p95 12")
	assert_str(g.value_text("interp")).is_equal("67 ms  (2.0 t)")
	assert_str(g.value_text("kbps_in")).is_equal("10.2 kB/s  all 11.0")
	assert_str(g.value_text("snap")).is_equal("341 B  max 512")
	assert_str(g.value_text("mode")).is_equal("UDP DTLS")


func test_missing_figures_show_a_dash() -> void:
	var g := _graph()
	g.apply_stats({})
	assert_str(g.value_text("ping")).is_equal("-")
	assert_str(g.value_text("snap")).is_equal("-")
