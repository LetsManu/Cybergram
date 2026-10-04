extends GdUnitTestSuite
## Placeholder combat sounds: the synthesized streams are valid, and an own
## shot on the client plays the 2D gunshot (pellets of one shot play once).


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
	# W10-W5: the own weapon's bank voice (generic gunshot if it has none).
	var voice := client.sfx.bank.weapon_voice(client.hero_def.weapon.sfx_voice)
	var expected: AudioStream = voice.get("stream", client.sfx.gunshot)
	# Three pellets of one shotgun shot arrive in the same tick.
	for i in 3:
		client.shot_received.emit(GameEvent.shot(5, Vector3(0, 1, -10)))
	for p in client.sfx.get_children():
		if p is AudioStreamPlayer and (p as AudioStreamPlayer).stream == expected:
			plays[0] += 1
	assert_int(plays[0]).is_equal(1)
