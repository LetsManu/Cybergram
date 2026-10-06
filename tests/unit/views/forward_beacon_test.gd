extends GdUnitTestSuite
## Forward Beacon (owner plan Part 6, docs/assets/forward_beacon.md): stages from
## the replicated Mid state, the lit lenses and hard-light per stage, the sounds
## per state change, the wire bits, the spots and the real asset in the view
## (fails without the asset).

const S := ForwardBeaconView.Stage
const C := MapDef.TEAM_CONCORD
const SY := MapDef.TEAM_SYNDICATE


func test_stage_follows_owner_and_beacon_state() -> void:
	var B := ProgressionSystem.Beacon
	assert_int(ForwardBeaconView.stage_of(MapDef.TEAM_NEUTRAL, C, B.NONE)).is_equal(S.DORMANT)
	assert_int(ForwardBeaconView.stage_of(C, C, B.ATTUNING)).is_equal(S.ATTUNING)
	assert_int(ForwardBeaconView.stage_of(C, C, B.READY)).is_equal(S.READY)
	assert_int(ForwardBeaconView.stage_of(C, C, B.UNDER_ATTACK)).is_equal(S.UNDER_ATTACK)
	# the other side's pad stays dark whatever the owner's Beacon does
	assert_int(ForwardBeaconView.stage_of(C, SY, B.READY)).is_equal(S.DORMANT)


func test_lenses_light_one_by_one_while_attuning() -> void:
	assert_int(ForwardBeaconView.lamps_lit(S.DORMANT, 1.0)).is_equal(0)
	assert_int(ForwardBeaconView.lamps_lit(S.ATTUNING, 0.0)).is_equal(0)
	assert_int(ForwardBeaconView.lamps_lit(S.ATTUNING, 0.5)).is_equal(3)
	assert_int(ForwardBeaconView.lamps_lit(S.ATTUNING, 1.0)).is_equal(6)
	assert_int(ForwardBeaconView.lamps_lit(S.READY, 0.0)).is_equal(6)
	assert_int(ForwardBeaconView.lamps_lit(S.UNDER_ATTACK, 0.0)).is_equal(6)


func test_sounds_on_state_changes() -> void:
	var B := ProgressionSystem.Beacon
	assert_str(String(ClientSfx.beacon_event(-1, B.READY))).is_empty()
	assert_str(String(ClientSfx.beacon_event(B.NONE, B.ATTUNING))).is_equal("beacon_attune")
	assert_str(String(ClientSfx.beacon_event(B.ATTUNING, B.READY))).is_equal("beacon_ready")
	assert_str(String(ClientSfx.beacon_event(B.READY, B.UNDER_ATTACK))).is_equal("beacon_threat")
	assert_str(String(ClientSfx.beacon_event(B.UNDER_ATTACK, B.READY))).is_equal("beacon_ready")
	assert_str(String(ClientSfx.beacon_event(B.READY, B.NONE))).is_empty()
	for ev in [&"beacon_attune", &"beacon_ready", &"beacon_threat"]:
		assert_bool(ResourceLoader.exists("res://assets/data/audio/events/world/%s.tres" % ev)).is_true()


func test_beacon_bits_round_trip_without_touching_breach() -> void:
	var h := SnapshotData.HardpointState.new()
	h.shielded = true
	h.breach_phase2 = true
	h.beacon = ProgressionSystem.Beacon.UNDER_ATTACK
	h.beacon_attune = 0.6
	var d := SnapshotCodec.hardpoint_from(SnapshotCodec.hardpoint_record(h))
	assert_int(d.beacon).is_equal(ProgressionSystem.Beacon.UNDER_ATTACK)
	assert_float(d.beacon_attune).is_equal_approx(0.6, 1.0 / 15.0)
	assert_bool(d.shielded and d.breach_phase2).is_true()


func test_spots_lie_half_way_to_the_zone_edge_toward_each_sanctum() -> void:
	var md := load("res://assets/data/match/map_front.tres") as MapDef
	var n := 0
	for lane: LaneDef in md.lanes:
		for d: HardpointDef in lane.hardpoints:
			var sp := ForwardBeaconView.spots(md, d)
			if d.tier != HardpointDef.Tier.MID:
				assert_int(sp.size()).is_equal(0)
				continue
			assert_int(sp.size()).is_equal(2)
			for s: Array in sp:
				var at: Vector3 = s[1]
				assert_float(Vector2(at.x - d.position.x, at.z - d.position.z).length()).is_equal_approx(d.zone_radius * 0.5, 0.01)
				var to_sanctum := md.hq(s[0]).sanctum - d.position
				assert_float((at - d.position).dot(to_sanctum)).is_greater(0.0)
				n += 1
	assert_int(n).is_equal(6)


func test_view_shows_the_asset_through_every_stage() -> void:
	assert_bool(ForwardBeaconView.available()).override_failure_message("forward_beacon glb not built").is_true()
	var B := ProgressionSystem.Beacon
	var v: ForwardBeaconView = auto_free(ForwardBeaconView.new())
	v.setup(C)
	add_child(v)
	for p in ["main", "core", "lamp_1", "lamp_6"]:
		assert_object(v.piece(StringName(p))).override_failure_message("piece %s" % p).is_not_null()
	assert_int(v.stage).is_equal(S.DORMANT)
	assert_bool(v.piece(&"core").visible).is_false()
	assert_float(v.strength_target()).is_equal(0.0)
	assert_bool(v.apply_state(C, B.ATTUNING, 0.5)).is_true()
	assert_bool(v.piece(&"lamp_3").visible and not v.piece(&"lamp_4").visible).is_true()
	assert_bool(v.piece(&"core").visible).is_true()
	assert_float(v.strength_target()).is_equal(v.def.attuning_strength)
	v.apply_state(C, B.READY, 1.0)
	assert_int(v.stage).is_equal(S.READY)
	assert_bool(v.piece(&"lamp_6").visible).is_true()
	assert_float(v.strength_target()).is_equal(v.def.ready_strength)
	v.apply_state(C, B.UNDER_ATTACK, 1.0)
	assert_int(v.stage).is_equal(S.UNDER_ATTACK)
	assert_float(v.strength_target()).is_less(v.def.ready_strength)
	# the enemy takes the Mid: this pad goes dark
	v.apply_state(SY, B.ATTUNING, 0.1)
	assert_int(v.stage).is_equal(S.DORMANT)
	assert_bool(v.piece(&"lamp_1").visible or v.piece(&"core").visible).is_false()


func test_strobe_stays_under_three_flashes_a_second() -> void:
	assert_float(ForwardBeaconDef.shared().strobe_hz).is_less_equal(3.0)
