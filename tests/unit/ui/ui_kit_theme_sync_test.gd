extends GdUnitTestSuite
## P4: assets/ui/ui_kit_theme.tres (the editor copy of the UI kit theme) is in
## sync with UiKit.build_theme(): same types, colours, constants and font
## sizes. Fails after a token / UiKit change until tools/ui/export_theme.gd
## is re-run.


func test_exported_theme_matches_the_code() -> void:
	var saved := load("res://assets/ui/ui_kit_theme.tres") as Theme
	assert_object(saved).is_not_null()
	var built := UiKit.build_theme()
	assert_int(saved.default_font_size).is_equal(built.default_font_size)
	var types := built.get_type_list()
	types.sort()
	var saved_types := saved.get_type_list()
	saved_types.sort()
	assert_array(Array(saved_types)).is_equal(Array(types))
	for ty in types:
		for n in built.get_color_list(ty):
			assert_that(saved.get_color(n, ty)).override_failure_message("color %s/%s" % [ty, n]).is_equal(built.get_color(n, ty))
		for n in built.get_constant_list(ty):
			assert_int(saved.get_constant(n, ty)).override_failure_message("constant %s/%s" % [ty, n]).is_equal(built.get_constant(n, ty))
		for n in built.get_font_size_list(ty):
			assert_int(saved.get_font_size(n, ty)).override_failure_message("font size %s/%s" % [ty, n]).is_equal(built.get_font_size(n, ty))
