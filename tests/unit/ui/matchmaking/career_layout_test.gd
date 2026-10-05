extends GdUnitTestSuite
## W21-U2: the CAREER page never lets PROFILE and RANKS overlap: side by side
## when the page is wide enough, stacked (with a scrollbar) when it is narrow.


func _page(width: float, height: float) -> Array:
	var host := Control.new()
	host.size = Vector2(width, height)
	add_child(host)
	var page := CareerLayout.new()
	host.add_child(page)
	var a := Control.new()
	a.custom_minimum_size = Vector2(660, 500)
	var b := Control.new()
	b.custom_minimum_size = Vector2(420, 400)
	page.add_panel(a)
	page.add_panel(b)
	return [host, page, a, b]


func test_wide_page_puts_the_panels_side_by_side_without_overlap() -> void:
	var n := _page(1300.0, 700.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var a: Control = n[2]
	var b: Control = n[3]
	assert_bool((n[1] as CareerLayout).is_stacked()).is_false()
	assert_bool(a.get_global_rect().intersects(b.get_global_rect())).is_false()
	(n[0] as Control).queue_free()


func test_narrow_page_stacks_the_panels_without_overlap() -> void:
	var n := _page(1000.0, 700.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var a: Control = n[2]
	var b: Control = n[3]
	assert_bool((n[1] as CareerLayout).is_stacked()).is_true()
	assert_bool(a.get_global_rect().intersects(b.get_global_rect())).is_false()
	assert_bool(b.get_global_rect().end.x <= (n[0] as Control).get_global_rect().end.x).is_true()
	(n[0] as Control).queue_free()
