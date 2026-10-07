extends GdUnitTestSuite
## Armory v2 visuals (items-and-armory.md §3.3, §3.8; weapons-and-mods.md
## §3.6.2-§3.6.3): build planning, body anchors on all 7 rigs, gear nodes,
## overflow badge, spares, gun parts per tier and the ammo tells.

const HEROES: Array[StringName] = [&"vesper", &"sable", &"juniper", &"ryker", &"brannoc", &"liora", &"hex"]
const ANCHOR_SUBS := {&"body_belt": 6, &"body_chest": 2, &"body_shoulders": 2, &"body_back": 2,
	&"body_head": 1, &"body_legs": 2, &"body_forearm": 2}

var _cat: ArmoryCatalogDef


func before() -> void:
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef


func _i(id: StringName) -> int:
	return _cat.index_of(id)


## Gun places + open slots by id (&"" = empty).
func _build(gun: Array, open: Array) -> PackedInt32Array:
	var b := PackedInt32Array()
	for id in gun + open:
		b.append(_i(id) if id != &"" else -1)
	while b.size() < SnapshotData.EntityState.BUILD_SIZE:
		b.append(-1)
	return b


func test_visual_tier_follows_recipe_tier() -> void:
	assert_int(BuildVisuals.visual_tier(_cat.find(&"ember_part"))).is_equal(1)
	assert_int(BuildVisuals.visual_tier(_cat.find(&"ember_facet"))).is_equal(2)
	assert_int(BuildVisuals.visual_tier(_cat.find(&"ember_heart"))).is_equal(3)


func test_plan_places_components_on_belt_and_gear_on_their_anchor() -> void:
	var b := _build([&"", &"", &"", &"", &""], [&"ember_part", &"tempo_part", &"vital_cell", &"plate_scale", &"cadence_bead", &"stride_clip"])
	var plan := BuildVisuals.plan_body(b, _cat)
	assert_int(plan.size()).is_equal(6)
	var anchors := plan.map(func(p: BuildVisuals.Placement) -> StringName: return p.anchor)
	assert_array(anchors).is_equal([&"body_belt", &"body_belt", &"body_chest", &"body_shoulders", &"body_head", &"body_legs"])
	assert_int(plan[1].index).is_equal(1)


func test_spare_is_flagged_unlit() -> void:
	var b := _build([&"", &"", &"", &"", &""], [&"vital_cell", &"vital_cell"])
	var plan := BuildVisuals.plan_body(b, _cat)
	assert_bool(plan[0].spare).is_false()
	assert_bool(plan[1].spare).is_true()


func test_full_anchor_overflows_then_badges_never_invisible() -> void:
	# body_head has 1 sub + 1 overflow: the third head item becomes a badge.
	var b := _build([&"", &"", &"", &"", &""], [&"cadence_bead", &"cadence_circlet", &"cadence_crown"])
	var plan := BuildVisuals.plan_body(b, _cat)
	assert_int(plan.size()).is_equal(3)
	assert_int(plan[0].place).is_equal(BuildVisuals.PLACE_SUB)
	assert_int(plan[1].place).is_equal(BuildVisuals.PLACE_OVERFLOW)
	assert_int(plan[2].place).is_equal(BuildVisuals.PLACE_BADGE)


func test_first_person_shows_only_belt_and_forearm() -> void:
	var b := _build([&"", &"", &"", &"", &""], [&"ember_part", &"vital_cell", &"breaker_sigil"])
	var plan := BuildVisuals.plan_body(b, _cat, BuildVisuals.SUB_COUNTS, {}, true)
	var anchors := plan.map(func(p: BuildVisuals.Placement) -> StringName: return p.anchor)
	assert_array(anchors).is_equal([&"body_belt", &"body_forearm"])


func test_every_hero_rig_gets_every_anchor() -> void:
	for k in HEROES:
		var m := HeroModelLoader.build(k, ModelPalette.TEAM_CONCORD)
		add_child(auto_free(m))
		m.set_build(_build([&"", &"", &"", &"", &""], []))
		for a in ANCHOR_SUBS:
			assert_int(m.gear.anchor_markers(a).size()).override_failure_message("%s %s" % [k, a]).is_equal(ANCHOR_SUBS[a])
			for mk in m.gear.anchor_markers(a):
				assert_bool(mk is Marker3D).is_true()
		assert_object(m.gear.badge_root()).is_not_null()


func test_set_build_puts_gear_and_gun_parts_on_a_hero() -> void:
	var m := HeroModelLoader.build(&"ryker", ModelPalette.TEAM_CONCORD)
	add_child(auto_free(m))
	var b := _build([&"ember_heart", &"longsight_ring", &"", &"ammo_incendiary", &"mod_saturated"],
		[&"tempo_part", &"tempo_part", &"vital_cell", &"bastion_plate"])
	assert_int(m.set_build(b)).is_equal(4)
	# unchanged build: no rebuild
	assert_int(m.set_build(b)).is_equal(4)


func test_mount_signature_has_idle_motion_and_component_size_grows() -> void:
	for id in [&"ember_heart", &"longsight_lens", &"flux_coil"]:
		var n := MountVisuals.build(_cat.find(id), 1, true)
		assert_bool((n.get_meta(&"spinners", []) as Array).is_empty()).override_failure_message(String(id)).is_false()
		n.free()
	var a := MountVisuals.build(_cat.find(&"longsight_ring"), 1, false)
	assert_bool((a.get_meta(&"spinners", []) as Array).is_empty()).is_true()
	a.free()
	assert_float(ArmoryVisualsData.tier_size(3)).is_greater(ArmoryVisualsData.tier_size(2))
	assert_float(ArmoryVisualsData.tier_size(2)).is_greater(ArmoryVisualsData.tier_size(1))


func test_weapon_model_set_build_mounts_sockets_and_tints_chamber() -> void:
	var w := WeaponModelBuilder.build(&"breakline", false, ModelPalette.TEAM_CONCORD)
	add_child(auto_free(w))
	var b := _build([&"ember_facet", &"bore_ring", &"wellframe", &"ammo_cryo", &""], [])
	assert_int(w.set_build(b)).is_equal(4)


func test_every_ammo_type_has_a_distinct_tell() -> void:
	var seen := {}
	for t in [1, 2, 3, 4, 5, 6]:
		var d := ArmoryVisualsData.ammo_tell(t)
		assert_str(String(d.get("color", ""))).is_not_empty()
		seen["%s|%s|%s" % [d.get("color"), d.get("shape"), d.get("impact")]] = true
	assert_int(seen.size()).is_equal(6)
	assert_str(String(ArmoryVisualsData.ammo_tell(0).get("name"))).is_equal("standard")


func test_first_person_rig_builds_only_belt_and_forearm_anchors() -> void:
	var m := HeroModelLoader.build(&"ryker", ModelPalette.TEAM_CONCORD)
	add_child(auto_free(m))
	var rig := BodyGearRig.new()
	rig.first_person = true
	rig.setup(m, &"ryker", m.get("skeleton") as Skeleton3D)
	assert_int(rig.anchor_markers(&"body_belt").size()).is_equal(6)
	assert_int(rig.anchor_markers(&"body_forearm").size()).is_equal(2)
	assert_int(rig.anchor_markers(&"body_chest").size()).is_equal(0)
	assert_object(rig.badge_root()).is_null()
	var b := _build([&"", &"", &"", &"", &""], [&"ember_part", &"vital_cell", &"breaker_sigil"])
	assert_int(rig.set_build(b)).is_equal(2)
