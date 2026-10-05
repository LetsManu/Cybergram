extends GdUnitTestSuite
## W19-HUD v0.12 HUD restyle (design/ux/hud-v0.12.md): the new settings (idle
## fade Off / 4 s / 8 s, text scale 90-130%), and the pure helpers behind the
## new look (cut-corner polygons, ownership, task shapes, lane columns, phase
## treatment, wave timer, key-chip pad text, skill line icons). In-memory only.


func test_idle_fade_default_is_4s_and_round_trips() -> void:
	var s := HudSettings.new()
	assert_float(s.idle_fade_seconds()).is_equal(4.0)
	s.idle_fade = 2
	s.set_text_scale(1.2)
	var cfg := ConfigFile.new()
	s.write_config(cfg)
	assert_str(str(cfg.get_value(HudSettings.SECTION, "idle_fade"))).is_equal("8")
	var b := HudSettings.new()
	b.read_config(cfg)
	assert_float(b.idle_fade_seconds()).is_equal(8.0)
	assert_float(b.text_scale).is_equal(1.2)


func test_idle_fade_off_never_fades_and_bad_id_falls_back() -> void:
	var s := HudSettings.new()
	s.apply_args(PackedStringArray(["--idle-fade", "off"]))
	assert_float(s.idle_fade_seconds()).is_equal(0.0)
	var cfg := ConfigFile.new()
	cfg.set_value(HudSettings.SECTION, "idle_fade", "banana")
	s.read_config(cfg)
	assert_float(s.idle_fade_seconds()).is_equal(4.0)


func test_text_scale_clamped_90_130() -> void:
	var s := HudSettings.new()
	s.set_text_scale(2.0)
	assert_float(s.text_scale).is_equal(HudSettings.TEXT_SCALE_MAX)
	s.apply_args(PackedStringArray(["--text-scale", "0.5"]))
	assert_float(s.text_scale).is_equal(HudSettings.TEXT_SCALE_MIN)


func test_cut_poly_chamfers_two_or_four_corners() -> void:
	var r := Rect2(0, 0, 87, 87)
	var two := HudWidget.cut_poly(r, 12.0)
	assert_int(two.size()).is_equal(6)
	assert_bool(two.has(Vector2(12, 0))).is_true()
	assert_bool(two.has(Vector2(87, 75))).is_true()
	assert_bool(two.has(Vector2(0, 0))).is_false()
	assert_int(HudWidget.cut_poly(r, 5.0, true).size()).is_equal(8)


func test_ownership_is_relative_to_own_team() -> void:
	assert_int(HudWidget.ownership(MapDef.TEAM_CONCORD, MapDef.TEAM_CONCORD)).is_equal(0)
	assert_int(HudWidget.ownership(MapDef.TEAM_SYNDICATE, MapDef.TEAM_CONCORD)).is_equal(1)
	assert_int(HudWidget.ownership(-1, MapDef.TEAM_SYNDICATE)).is_equal(2)


func test_task_shapes_differ_by_task() -> void:
	var c := Vector2.ZERO
	assert_int(HudWidget.task_shape(c, 12.0, HardpointDef.TaskKind.PLANT).size()).is_equal(4)
	assert_int(HudWidget.task_shape(c, 12.0, HardpointDef.TaskKind.BREACH).size()).is_equal(3)
	assert_int(HudWidget.task_shape(c, 12.0, HardpointDef.TaskKind.HOLD).size()).is_equal(16)


func test_lane_columns_put_own_hq_on_the_left() -> void:
	assert_int(FrontStrip.column_of(0, 5, MapDef.TEAM_CONCORD)).is_equal(0)
	assert_int(FrontStrip.column_of(0, 5, MapDef.TEAM_SYNDICATE)).is_equal(4)
	assert_int(FrontStrip.column_of(4, 5, MapDef.TEAM_SYNDICATE)).is_equal(0)


func test_phase_treatment() -> void:
	var m := SnapshotData.MatchState.new()
	m.phase = MatchRules.Phase.SKIRMISH
	assert_int(MatchHeader.phase_of(m)).is_equal(MatchHeader.Phase.NORMAL)
	m.phase = MatchRules.Phase.TIME_OUT
	assert_int(MatchHeader.phase_of(m)).is_equal(MatchHeader.Phase.OVERTIME)
	m.phase = MatchRules.Phase.SUDDEN_DEATH
	assert_int(MatchHeader.phase_of(m)).is_equal(MatchHeader.Phase.SUDDEN_DEATH)
	assert_int(MatchHeader.phase_of(null)).is_equal(MatchHeader.Phase.NORMAL)


func test_next_wave_timer_follows_the_cadence() -> void:
	var r := WardlingRulesDef.new()
	r.wave_first_s = 60.0
	r.wave_interval_s = 60.0
	assert_float(LaneMinimap.next_wave_in(0.0, r)).is_equal(60.0)
	assert_float(LaneMinimap.next_wave_in(102.0, r)).is_equal(18.0)
	assert_float(LaneMinimap.next_wave_in(120.0, r)).is_equal(60.0)


func test_pad_glyphs_are_short() -> void:
	assert_str(HudContext.short_pad("D-Pad Up")).is_equal("D↑")
	assert_str(HudContext.short_pad("RB")).is_equal("RB")


func test_every_skill_has_a_line_icon() -> void:
	var dir := "res://assets/data/skills/"
	var missing: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"):
			continue
		var d := load(dir + f) as SkillDef
		if d != null and d.short_label != "" and not SkillIcons.has(d.short_label):
			missing.append(d.short_label)
	assert_array(missing).is_empty()
	assert_bool(SkillIcons.has("MED")).is_true()


func test_icon_paths_parse_into_polylines() -> void:
	var lines := SkillIcons.parse("M5 25 L25 5|C15 15 2|A15 15 10 0 90")
	assert_int(lines.size()).is_equal(3)
	assert_int((lines[0] as PackedVector2Array).size()).is_equal(2)
	assert_vector((lines[0] as PackedVector2Array)[1]).is_equal(Vector2(25, 5))
	assert_bool((lines[1] as PackedVector2Array).size() > 8).is_true()


func test_critical_hp_band() -> void:
	assert_bool(VitalsPanel.is_critical(41, 279, 0.25)).is_true()
	assert_bool(VitalsPanel.is_critical(212, 279, 0.25)).is_false()
