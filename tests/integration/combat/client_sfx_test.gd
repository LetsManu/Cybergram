extends GdUnitTestSuite
## Placeholder combat sounds: the synthesized streams are valid, and an own
## shot on the client plays the 2D gunshot (pellets of one shot play once).
## W21-A1: the shot is now the weapon's AudioEventDef played by ClientSfx.events.


func test_synth_streams_have_the_expected_length() -> void:
	var g := ClientSfx.synth_gunshot()
	assert_int(g.data.size()).is_equal(int(ClientSfx.RATE * 0.22) * 2)
	assert_int(ClientSfx.synth_tone(1700.0, 0.05).data.size()).is_equal(int(ClientSfx.RATE * 0.05) * 2)
	assert_int(ClientSfx.synth_chime().data.size()).is_greater(0)


func test_own_shot_plays_the_gunshot_once_per_shot() -> void:
	var client := ClientWorld.new()
	add_child(auto_free(client))
	var net := NetFixtures.net_config()
	var link := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	client.setup(net, MovementDef.new(), LookSettings.new(), CombatFixtures.range_scene(false),
		link.create_endpoint(2), ScriptedInputSource.new(CombatFixtures.idle_input()), CombatFixtures.vesper())
	client.session.own_net_id = 5
	var plays := [0]
	# W21-A1: the own weapon's shot event (rendered variants, else the synth fallback).
	var shots := client.sfx.events.bank.streams_for(StringName("weapon_%s_shot_own" % client.hero_def.weapon.sfx_voice))
	assert_bool(shots.is_empty()).is_false()
	# Three pellets of one shotgun shot arrive in the same tick.
	for i in 3:
		client.shot_received.emit(GameEvent.shot(5, Vector3(0, 1, -10)))
	for p in client.sfx.events.get_children():
		if p is AudioStreamPlayer and shots.has((p as AudioStreamPlayer).stream):
			plays[0] += 1
	assert_int(plays[0]).is_equal(1)


## Owner 2026-10-07: Lumen income plays no sound (it played on every gain).
func test_lumen_income_plays_no_sound() -> void:
	var client := ClientWorld.new()
	add_child(auto_free(client))
	var net := NetFixtures.net_config()
	var link := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	client.setup(net, MovementDef.new(), LookSettings.new(), CombatFixtures.range_scene(false),
		link.create_endpoint(2), ScriptedInputSource.new(CombatFixtures.idle_input()), CombatFixtures.vesper())
	var lumen := client.sfx.events.bank.streams_for(&"ui_lumen")
	for gain in [100, 140, 400]:
		var s := SnapshotData.new()
		s.progress = SnapshotData.ProgressState.new()
		s.progress.lumen = gain
		client.sfx._on_snapshot(s)
	var plays := 0
	for p in client.sfx.events.get_children():
		if p is AudioStreamPlayer and (p as AudioStreamPlayer).playing and lumen.has((p as AudioStreamPlayer).stream):
			plays += 1
	assert_int(plays).is_equal(0)
