extends GdUnitTestSuite
## Ward Generator (owner plan Part 6, docs/assets/ward_generator.md): stages from
## the replicated state, the pieces and shield per stage, the sounds per stage
## change, and the real asset in the Breach view (fails without the asset).

const S := WardGeneratorView.Stage
const C := MapDef.TEAM_CONCORD


func test_stage_follows_owner_shield_and_hp() -> void:
	assert_int(WardGeneratorView.stage_of(MapDef.TEAM_NEUTRAL, false, 1.0, false)).is_equal(S.NEUTRAL)
	assert_int(WardGeneratorView.stage_of(C, true, 1.0, false)).is_equal(S.SHIELDED)
	assert_int(WardGeneratorView.stage_of(C, false, 0.9, false)).is_equal(S.EXPOSED)
	assert_int(WardGeneratorView.stage_of(C, false, 0.74, false)).is_equal(S.CRACK_1)
	assert_int(WardGeneratorView.stage_of(C, false, 0.49, false)).is_equal(S.CRACK_2)
	assert_int(WardGeneratorView.stage_of(C, false, 0.2, false)).is_equal(S.CRACK_3)
	assert_int(WardGeneratorView.stage_of(C, false, 0.0, false)).is_equal(S.BREACHED)
	assert_int(WardGeneratorView.stage_of(C, true, 0.6, true)).is_equal(S.BREACHED)


func test_pieces_per_stage() -> void:
	assert_bool(WardGeneratorView.pieces_for(S.EXPOSED)[&"crack_1"]).is_false()
	assert_bool(WardGeneratorView.pieces_for(S.CRACK_2)[&"crack_2"]).is_true()
	assert_bool(WardGeneratorView.pieces_for(S.CRACK_2)[&"crack_3"]).is_false()
	var b := WardGeneratorView.pieces_for(S.BREACHED)
	assert_bool(b[&"wreck"] and b[&"crack_3"] and not b[&"core"]).is_true()


func test_sounds_on_stage_changes() -> void:
	assert_str(String(ClientSfx.generator_event(-1, S.SHIELDED))).is_empty()
	assert_str(String(ClientSfx.generator_event(S.SHIELDED, S.EXPOSED))).is_equal("generator_shield_down")
	assert_str(String(ClientSfx.generator_event(S.EXPOSED, S.CRACK_1))).is_equal("generator_crack")
	assert_str(String(ClientSfx.generator_event(S.CRACK_2, S.CRACK_1))).is_empty()  # healed: no crack sound
	assert_str(String(ClientSfx.generator_event(S.CRACK_3, S.BREACHED))).is_equal("generator_breach")
	for ev in [&"generator_shield_down", &"generator_crack", &"generator_breach"]:
		assert_bool(ResourceLoader.exists("res://assets/data/audio/events/world/%s.tres" % ev)).is_true()


func test_view_shows_the_asset_through_every_stage() -> void:
	assert_bool(WardGeneratorView.available()).override_failure_message("ward_generator glb not built").is_true()
	var v: WardGeneratorView = auto_free(WardGeneratorView.new())
	v.setup(C)
	add_child(v)
	v.apply_state(C, true, 1.0, false)
	v._process(1.0)
	assert_bool(v.shield_visible()).is_true()
	assert_bool(v.piece(&"crack_1").visible).is_false()
	v.apply_state(C, false, 0.45, false)
	v._process(1.0)
	assert_bool(v.shield_visible()).is_false()
	assert_bool(v.piece(&"crack_2").visible).is_true()
	assert_bool(v.piece(&"wreck").visible).is_false()
	assert_bool(v.smoking()).is_false()
	v.apply_state(C, false, 0.0, true)
	assert_bool(v.piece(&"wreck").visible).is_true()
	assert_bool(v.piece(&"core").visible).is_false()
	assert_bool(v.smoking()).is_true()
	# a breached generator is dead: no team glow
	assert_float(float((v.piece(&"main").material_override as ShaderMaterial).get_shader_parameter("map_emission"))).is_equal(0.0)
