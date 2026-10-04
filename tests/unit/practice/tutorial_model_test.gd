extends GdUnitTestSuite
## W10-W4: tutorial step progression (TutorialModel) and the shipped step data.

const PATH := "res://assets/data/match/tutorial_steps.tres"
const ORDER: Array[StringName] = [&"move", &"jump", &"sprint", &"shoot", &"reload", &"skill_1",
	&"level_up", &"fork", &"shop_open", &"buy"]


func _def() -> TutorialDef:
	return load(PATH) as TutorialDef


func test_data_lists_the_required_steps_in_order() -> void:
	var d := _def()
	assert_int(d.steps.size()).is_equal(ORDER.size())
	for i in ORDER.size():
		assert_str(String(d.steps[i].id)).is_equal(String(ORDER[i]))
		assert_str(d.steps[i].text_key).starts_with("HUD_TUT_")


func test_step_actions_are_real_rebindable_actions() -> void:
	var ids := InputBindings.action_ids()
	for s in _def().steps:
		for a in s.actions:
			assert_bool(ids.has(a)).is_true()


func test_only_the_current_step_completes() -> void:
	var m := TutorialModel.new(_def())
	assert_bool(m.update({"jump": true})).is_false()  # not the current step
	assert_int(m.index).is_equal(0)
	assert_bool(m.update({"move": true})).is_true()
	assert_int(m.index).is_equal(1)


func test_full_run_finishes_once() -> void:
	var m := TutorialModel.new(_def())
	var fin: Array = []
	m.finished.connect(func(s: bool) -> void: fin.append(s))
	for id in ORDER:
		assert_bool(m.done).is_false()
		assert_str(String(m.current().id)).is_equal(String(id))
		m.update({id: true})
	assert_bool(m.done).is_true()
	assert_array(fin).is_equal([false])
	assert_bool(m.update({"move": true})).is_false()


func test_skip_step_and_skip_all() -> void:
	var m := TutorialModel.new(_def())
	m.skip_step()
	assert_int(m.index).is_equal(1)
	var fin: Array = []
	m.finished.connect(func(s: bool) -> void: fin.append(s))
	m.skip_all()
	assert_bool(m.done).is_true()
	assert_bool(m.skipped).is_true()
	assert_array(fin).is_equal([true])


func test_skipping_every_step_finishes_and_restart_resets() -> void:
	var m := TutorialModel.new(_def())
	for i in ORDER.size():
		m.skip_step()
	assert_bool(m.done).is_true()
	m.restart()
	assert_bool(m.done).is_false()
	assert_int(m.index).is_equal(0)


func test_range_launch_args() -> void:
	var a := PracticeRange.begin("brannoc")
	assert_array(a).is_equal(PackedStringArray(["--map", "test_course", "--hero", "brannoc"]))
	assert_bool(PracticeRange.is_active(PackedStringArray())).is_true()
	PracticeRange.end()
	assert_bool(PracticeRange.is_active(PackedStringArray())).is_false()
	assert_bool(PracticeRange.is_active(PackedStringArray(["--practice"]))).is_true()
	assert_array(PracticeRange.boot_args(PackedStringArray(["x"]))).is_equal(PackedStringArray(["x"]))
