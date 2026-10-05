extends GdUnitTestSuite
## W10-W5: synthesized sound bank: every weapon / skill maps to a voice, streams
## are non-empty and normalized, the cache is deterministic, pools are bounded.

const HEROES := "res://assets/data/heroes"


func _heroes() -> Array[HeroDef]:
	var out: Array[HeroDef] = []
	for f in DirAccess.get_files_at(HEROES):
		if f.ends_with(".tres"):
			out.append(load("%s/%s" % [HEROES, f]) as HeroDef)
	return out


func _peak(w: AudioStreamWAV) -> float:
	var p := 0.0
	for i in range(0, w.data.size(), 2):
		p = maxf(p, absf(w.data.decode_s16(i)) / 32767.0)
	return p


func test_every_weapon_has_a_voice() -> void:
	var bank := SfxBank.shared()
	var n := 0
	for h in _heroes():
		var v := bank.weapon_voice(h.weapon.sfx_voice)
		assert_bool(v.is_empty()).is_false()
		assert_int((v["stream"] as AudioStreamWAV).data.size()).is_greater(0)
		n += 1
	assert_int(n).is_greater_equal(7)


func test_weapons_are_distinct_voices() -> void:
	var seen := {}
	for h in _heroes():
		seen[h.weapon.sfx_voice] = true
	assert_int(seen.size()).is_equal(7)


func test_every_skill_maps_to_a_cast_archetype() -> void:
	var bank := SfxBank.shared()
	var n := 0
	for h in _heroes():
		for s in h.skills:
			var c := bank.skill_cast(s.id)
			assert_bool(c.is_empty()).is_false()
			assert_int((c["stream"] as AudioStreamWAV).data.size()).is_greater(0)
			n += 1
	assert_int(n).is_equal(28)


func test_all_streams_non_empty_and_normalized() -> void:
	var bank := SfxBank.shared()
	assert_int(bank.streams.size()).is_equal(SfxSynth.ARCHETYPES.size())
	for k in bank.streams:
		var w := bank.streams[k] as AudioStreamWAV
		assert_int(w.data.size()).is_greater(0)
		assert_float(_peak(w)).is_less_equal(1.0)
		assert_float(_peak(w)).is_greater(0.5)


func test_synthesis_is_deterministic() -> void:
	for k in [&"gun_rifle", &"hack_glitch", &"explosion", &"beam_loop"]:
		assert_bool(SfxSynth.make(k).data == SfxSynth.make(k).data).is_true()


func test_bank_maps_resolve_to_known_archetypes() -> void:
	var d := SfxBank.shared().def
	for v in d.weapon_voices.values():
		assert_bool(SfxSynth.ARCHETYPES.has(v["archetype"])).is_true()
	for v in d.skills.values():
		assert_bool(SfxSynth.ARCHETYPES.has(v["cast"])).is_true()
	for v in d.fx_impacts.values():
		assert_bool(SfxSynth.ARCHETYPES.has(v)).is_true()
	for v in d.ui.values():
		assert_bool(SfxSynth.ARCHETYPES.has(v)).is_true()


func test_startup_synth_under_budget() -> void:
	var b := SfxBank.new()
	b.synthesize_all()
	assert_float(b.synth_ms).is_less(300.0)


func test_voice_pools_are_bounded() -> void:
	var d := SfxBank.shared().def
	var sfx := ClientSfx.new()
	add_child(auto_free(sfx))
	assert_int(sfx.get_child_count()).is_less_equal(d.pool_2d + d.pool_3d + d.pool_ui + d.pool_loops + d.pool_feet)
	for i in 100:
		sfx.play_2d(sfx.gunshot, 0.0, 1.0)
		sfx.play_3d(sfx.gunshot, Vector3.ZERO, 0.0, 1.0)
	assert_int(sfx.get_child_count()).is_less_equal(d.pool_2d + d.pool_3d + d.pool_ui + d.pool_loops + d.pool_feet)
