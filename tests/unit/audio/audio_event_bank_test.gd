extends GdUnitTestSuite
## W21-A1: AudioEventBank resolution order (explicit -> files -> convention ->
## synth fallback), deterministic variant picks, and catalog integrity.

const BUSES := [&"Master", &"Music", &"Effects", &"Weapons", &"Abilities", &"Footsteps", &"World",
	&"UI", &"Voice", &"Ambient"]


func _event(id: StringName, stem: String, recipe: StringName = &"") -> AudioEventDef:
	var e := AudioEventDef.new()
	e.id = id
	e.folder = "weapons"
	e.file_stem = stem
	e.synth_recipe = recipe
	return e


func _bank(events: Array[AudioEventDef]) -> AudioEventBank:
	var d := AudioEventBankDef.new()
	d.events = events
	return AudioEventBank.new(d)


func test_missing_file_falls_back_to_the_synth_recipe() -> void:
	var b := _bank([_event(&"shot", "weapons_rifle_shot", &"gun_rifle")])
	b.exists_fn = func(_p: String) -> bool: return false
	var s := b.streams_for(&"shot")
	assert_int(s.size()).is_equal(1)
	assert_object(s[0]).is_same(SfxBank.shared().stream(&"gun_rifle"))
	assert_str(String(b.source[&"shot"])).is_equal("synth")


func test_convention_files_are_preferred_and_counted() -> void:
	var b := _bank([_event(&"shot", "weapons_rifle_shot", &"gun_rifle")])
	var s := b.streams_for(&"shot")
	assert_int(s.size()).is_equal(5)  # weapons_rifle_shot_01..05.ogg
	assert_bool(s[0] is AudioStreamOggVorbis).is_true()
	assert_str(String(b.source[&"shot"])).is_equal("file")


func test_partial_variants_stop_at_the_first_gap() -> void:
	var b := _bank([_event(&"shot", "weapons_rifle_shot")])
	b.exists_fn = func(p: String) -> bool: return not p.ends_with("_03.ogg") and ResourceLoader.exists(p)
	assert_int(b.streams_for(&"shot").size()).is_equal(2)


func test_no_file_and_no_recipe_is_silent() -> void:
	var b := _bank([_event(&"vo", "voice_announcer_first_blood")])
	assert_bool(b.streams_for(&"vo").is_empty()).is_true()
	assert_bool(b.streams_for(&"unknown").is_empty()).is_true()


func test_explicit_streams_win() -> void:
	var e := _event(&"x", "weapons_rifle_shot", &"gun_rifle")
	var w := AudioStreamWAV.new()
	e.streams = [w]
	var b := _bank([e])
	assert_object(b.streams_for(&"x")[0]).is_same(w)


func test_pick_is_deterministic_and_never_repeats() -> void:
	var b := _bank([_event(&"shot", "weapons_rifle_shot")])
	var r1 := RandomNumberGenerator.new()
	r1.seed = 42
	var r2 := RandomNumberGenerator.new()
	r2.seed = 42
	var last := -1
	for i in 50:
		var a := b.pick(&"shot", r1, last)
		assert_int(a).is_equal(b.pick(&"shot", r2, last))
		assert_int(a).is_not_equal(last)
		last = a


func test_every_catalog_event_resolves_and_uses_a_known_bus() -> void:
	var b := AudioEventBank.shared()
	assert_int(b.ids().size()).is_greater(200)
	for id in b.ids():
		var e := b.get_def(id)
		assert_bool(BUSES.has(e.bus)).override_failure_message("bus %s of %s" % [e.bus, id]).is_true()
		if String(id).begins_with("voice_"):
			continue  # recorded announcer lines: silent until the files land
		assert_bool(b.streams_for(id).is_empty()).override_failure_message("no stream for %s" % id).is_false()


func test_every_weapon_voice_and_skill_has_events() -> void:
	var b := AudioEventBank.shared()
	for f in DirAccess.get_files_at("res://assets/data/heroes"):
		if not f.ends_with(".tres"):
			continue
		var h := load("res://assets/data/heroes/" + f) as HeroDef
		for rel in ["own", "enemy", "ally"]:
			assert_bool(b.has(StringName("weapon_%s_shot_%s" % [h.weapon.sfx_voice, rel]))).is_true()
		for s in h.skills:
			for rel in ["own", "enemy", "ally"]:
				assert_bool(b.has(StringName("%s_cast_%s" % [s.id, rel]))).override_failure_message(String(s.id)).is_true()
			assert_bool(b.has(StringName("%s_impact" % s.id))).is_true()
