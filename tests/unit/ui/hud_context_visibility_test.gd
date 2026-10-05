extends GdUnitTestSuite
## Polish sprint 2026-10-05: hud.md §12 / §14. Before, Sudden Death kept the
## squad strip and objective card on screen, and the whole combat HUD stayed
## visible behind the match-end banner.


func test_normal_play_shows_the_combat_hud() -> void:
	var v := HudRoot.context_visibility(false, false, false, false, false)
	for k in ["front", "minimap", "kill_feed", "tracker", "center", "squad", "vitals", "skills", "weapon"]:
		assert_bool(v[k]).override_failure_message(k).is_true()


func test_sudden_death_hides_tracker_and_squad_but_keeps_the_alive_pips_strip() -> void:
	var v := HudRoot.context_visibility(false, false, false, false, true)
	assert_bool(v.tracker).is_false()
	assert_bool(v.squad).is_false()
	assert_bool(v.front).is_true()
	assert_bool(v.vitals).is_true()


func test_match_end_leaves_only_header_and_toasts() -> void:
	var v := HudRoot.context_visibility(false, false, false, true, false)
	assert_bool(v.header).is_true()
	assert_bool(v.toasts).is_true()
	for k in ["front", "minimap", "kill_feed", "tracker", "center", "squad", "vitals", "skills", "weapon"]:
		assert_bool(v[k]).override_failure_message(k).is_false()
