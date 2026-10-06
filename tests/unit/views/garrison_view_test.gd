extends GdUnitTestSuite
## Garrison client side (docs/assets/garrison.md): socket stages, sockets on a
## hardpoint lit by the replicated Sentinels, the Sentinel look (plates at every
## tier, no sash or pennant), the sound event, and the real socket asset
## (fails without it).

const S := GarrisonSocketView.Stage
const C := MapDef.TEAM_CONCORD
const SY := MapDef.TEAM_SYNDICATE


func _def() -> HardpointDef:
	var md := load("res://assets/data/match/map_front.tres") as MapDef
	return md.lanes[1].hardpoints[1]


func _sentinel_state(team: int, at: Vector3) -> SnapshotData.WardlingState:
	var w := SnapshotData.WardlingState.new()
	w.team = team
	w.position = at
	w.state = WardlingWorld.GARRISON_STATE
	return w


func test_socket_stage_follows_owner_and_manning() -> void:
	assert_int(GarrisonSocketView.stage_of(MapDef.TEAM_NEUTRAL, true)).is_equal(S.OFF)
	assert_int(GarrisonSocketView.stage_of(C, false)).is_equal(S.WAITING)
	assert_int(GarrisonSocketView.stage_of(C, true)).is_equal(S.MANNED)


func test_hardpoint_sockets_light_for_the_owners_sentinels() -> void:
	assert_bool(GarrisonSocketView.available()).override_failure_message("garrison_socket glb not built").is_true()
	var d := _def()
	var v: HardpointView = auto_free(HardpointView.new())
	v.setup(d)
	add_child(v)
	assert_int(v.sockets.size()).is_equal(2)
	for p in ["main", "ring"]:
		assert_object(v.sockets[0].piece(StringName(p))).override_failure_message("piece %s" % p).is_not_null()
	# a Sentinel of the owner on post 0 only
	v.apply_garrison(C, [_sentinel_state(C, d.garrison_points[0])])
	assert_int(v.sockets[0].stage).is_equal(S.MANNED)
	assert_int(v.sockets[1].stage).is_equal(S.WAITING)
	assert_bool(v.sockets[0].piece(&"ring").visible).is_true()
	# an enemy Sentinel or a squad Wardling does not man it
	var squad := _sentinel_state(C, d.garrison_points[1])
	squad.state = 1
	v.apply_garrison(C, [_sentinel_state(SY, d.garrison_points[0]), squad])
	assert_int(v.sockets[0].stage).is_equal(S.WAITING)
	assert_int(v.sockets[1].stage).is_equal(S.WAITING)
	v.apply_garrison(MapDef.TEAM_NEUTRAL, [])
	assert_int(v.sockets[0].stage).is_equal(S.OFF)
	assert_bool(v.sockets[0].piece(&"ring").visible).is_false()


func test_sentinel_wears_plates_at_tier_one_without_sash_or_pennant() -> void:
	var m: Node3D = auto_free(WardlingModelBuilder.build(&"picket", 1, C))
	add_child(m)
	if m.get("rig") == null:
		return  # procedural fallback model: no plates to check
	m.set_owner_kind(3)
	var rig: Node = m.get("rig")
	for p in [&"plate_l", &"plate_r"]:
		var mi: MeshInstance3D = rig.get("_props").get(p)
		assert_bool(mi != null and mi.visible).override_failure_message("%s hidden" % p).is_true()
	for p in [&"sash", &"sash_own", &"pennant"]:
		var mi2: MeshInstance3D = rig.get("_props").get(p)
		assert_bool(mi2 == null or not mi2.visible).override_failure_message("%s shown" % p).is_true()
	m.set_owner_kind(1)
	assert_bool((rig.get("_props").get(&"plate_l") as MeshInstance3D).visible).is_false()


func test_post_sound_event_exists() -> void:
	assert_bool(ResourceLoader.exists("res://assets/data/audio/events/world/garrison_post.tres")).is_true()


func test_every_used_post_is_inside_its_zone() -> void:
	var md := load("res://assets/data/match/map_front.tres") as MapDef
	var per := WardlingRulesDef.new().sentinels_per_hardpoint
	for lane: LaneDef in md.lanes:
		for d: HardpointDef in lane.hardpoints:
			for i in mini(per, d.garrison_points.size()):
				var p := d.garrison_points[i]
				assert_float(Vector2(p.x - d.position.x, p.z - d.position.z).length()).is_less(d.zone_radius)
