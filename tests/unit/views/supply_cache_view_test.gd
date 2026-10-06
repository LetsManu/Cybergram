extends GdUnitTestSuite
## Supply Cache view (docs/assets/supply_cache.md): stages from the replicated
## owner and the switch delay, pieces lit per stage, motes while serving the own
## hero, the sounds, the solid collider, and the real asset (fails without it).

const S := SupplyCacheView.Stage
const C := MapDef.TEAM_CONCORD
const SY := MapDef.TEAM_SYNDICATE


func _def() -> HardpointDef:
	var md := load("res://assets/data/match/map_front.tres") as MapDef
	return md.lanes[1].hardpoints[1]


func test_stage_follows_owner_and_switch_delay() -> void:
	assert_int(SupplyCacheView.stage_of(MapDef.TEAM_NEUTRAL, 0.0, 50.0, 10.0)).is_equal(S.NEUTRAL)
	assert_int(SupplyCacheView.stage_of(C, 40.0, 45.0, 10.0)).is_equal(S.SWITCHING)
	assert_int(SupplyCacheView.stage_of(C, 40.0, 50.0, 10.0)).is_equal(S.SERVING)


func test_sounds_on_online_and_first_use() -> void:
	assert_str(String(ClientSfx.supply_event(-1, S.SERVING, false, false))).is_empty()
	assert_str(String(ClientSfx.supply_event(S.SWITCHING, S.SERVING, false, false))).is_equal("supply_online")
	assert_str(String(ClientSfx.supply_event(S.SERVING, S.SERVING, false, true))).is_equal("supply_use")
	assert_str(String(ClientSfx.supply_event(S.SERVING, S.SERVING, true, true))).is_empty()
	for ev in [&"supply_online", &"supply_use"]:
		assert_bool(ResourceLoader.exists("res://assets/data/audio/events/world/%s.tres" % ev)).is_true()


func test_view_shows_the_asset_through_every_stage() -> void:
	assert_bool(SupplyCacheView.available()).override_failure_message("supply_cache glb not built").is_true()
	var v: SupplyCacheView = auto_free(SupplyCacheView.new())
	v.setup(_def())
	add_child(v)
	for p in ["main", "lamps", "icon"]:
		assert_object(v.piece(StringName(p))).override_failure_message("piece %s" % p).is_not_null()
	# first sample: a held hardpoint counts as settled (joining mid-match)
	v.apply_owner(C, 100.0)
	assert_int(v.stage).is_equal(S.SERVING)
	assert_bool(v.piece(&"lamps").visible and v.piece(&"icon").visible).is_true()
	# the enemy takes it: switching for 10 s, then serving them
	v.apply_owner(SY, 200.0)
	assert_int(v.stage).is_equal(S.SWITCHING)
	v.apply_owner(SY, 210.5)
	assert_int(v.stage).is_equal(S.SERVING)
	assert_int(v.team).is_equal(SY)
	v.set_serving_me(true)
	assert_bool(v.serving_me()).is_true()
	v.apply_owner(MapDef.TEAM_NEUTRAL, 220.0)
	assert_int(v.stage).is_equal(S.NEUTRAL)
	assert_bool(v.piece(&"lamps").visible or v.piece(&"icon").visible).is_false()
	assert_bool(v.serving_me()).is_false()


func test_crates_are_solid_where_the_map_puts_them() -> void:
	var md := load("res://assets/data/match/map_front.tres") as MapDef
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var bodies := SupplyCacheSystem.add_bodies(root, md)
	assert_int(bodies.size()).is_equal(15)
	var d := _def()
	var b := bodies.filter(func(x: StaticBody3D) -> bool: return x.name == "SupplyCacheBody_%s" % d.id)
	assert_int(b.size()).is_equal(1)
	assert_vector((b[0] as StaticBody3D).position).is_equal(d.supply_cache)
	assert_int((b[0] as StaticBody3D).collision_layer).is_equal(HeroBody.LAYER_WORLD)
