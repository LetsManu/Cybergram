extends GdUnitTestSuite
## W14-P2: hit reaction mapping, tier toggles, spring setup without bones, foot IK plan.


func test_hit_from_front_pushes_body_back() -> void:
	var m := HitReaction.map_hit(Vector3(0, 0, -1), 0.5)  # attacker in front (-Z)
	# Push is +Z, axis = up x push = (push.z, 0, -push.x) = (1,0,0).
	assert_vector(m.axis).is_equal_approx(Vector3(1, 0, 0), Vector3(0.001, 0.001, 0.001))
	assert_bool(m.stagger).is_false()


func test_hit_from_right_leans_left_and_sides_mirror() -> void:
	var r := HitReaction.map_hit(Vector3(1, 0, 0), 0.5)
	var l := HitReaction.map_hit(Vector3(-1, 0, 0), 0.5)
	assert_vector(r.axis).is_equal_approx(-l.axis, Vector3(0.001, 0.001, 0.001))


func test_unknown_direction_is_frontal_and_height_is_ignored() -> void:
	var a := HitReaction.map_hit(Vector3.ZERO, 0.5)
	var b := HitReaction.map_hit(Vector3(0, 5, -1), 0.5)
	assert_vector(a.axis).is_equal_approx(b.axis, Vector3(0.001, 0.001, 0.001))


func test_big_hit_staggers_with_larger_angle_and_longer_time() -> void:
	var small := HitReaction.map_hit(Vector3(0, 0, -1), 0.5)
	var big := HitReaction.map_hit(Vector3(0, 0, -1), 1.0)
	assert_bool(big.stagger).is_true()
	assert_float(big.angle).is_greater(small.angle * 2.0)
	assert_float(big.duration).is_greater(small.duration)


func test_envelope_is_zero_outside_and_peaks_at_start() -> void:
	assert_float(HitReaction.envelope(1.0, 0.35)).is_equal(0.0)
	assert_float(HitReaction.envelope(0.0, 0.35)).is_equal(1.0)


func test_tier_toggles() -> void:
	assert_bool(SecondaryMotion.enabled_for(GfxQuality.LOW)).is_false()
	assert_bool(SecondaryMotion.enabled_for(GfxQuality.MEDIUM)).is_true()
	assert_bool(FootIK.enabled_for(GfxQuality.MEDIUM)).is_false()
	assert_bool(FootIK.enabled_for(GfxQuality.HIGH)).is_true()


func test_find_chains_groups_and_orders() -> void:
	var c := SecondaryMotion.find_chains(PackedStringArray(
		["Hips", "Sec_coat_L_2", "Sec_coat_L_1", "Sec_halo_1", "Sec_bad", "Sec_x_y"]))
	assert_array(c["Sec_coat_L"]).is_equal(["Sec_coat_L_1", "Sec_coat_L_2"])
	assert_bool(c.has("Sec_halo")).is_true()
	assert_int(c.size()).is_equal(2)
	assert_str(SecondaryMotion.part_of("Sec_coat_L")).is_equal("coat")


func test_spring_attach_without_bones_adds_nothing() -> void:
	var sk: Skeleton3D = auto_free(Skeleton3D.new())
	sk.add_bone("Hips")
	assert_object(SecondaryMotion.attach(sk, GfxQuality.ULTRA)).is_null()
	assert_int(sk.get_child_count()).is_equal(0)


func test_spring_attach_with_bones_builds_one_simulator() -> void:
	var sk: Skeleton3D = auto_free(Skeleton3D.new())
	sk.add_bone("Hips")
	sk.add_bone("Sec_coat_L_1")
	sk.add_bone("Sec_coat_L_2")
	sk.set_bone_parent(1, 0)
	sk.set_bone_parent(2, 1)
	assert_object(SecondaryMotion.attach(sk, GfxQuality.LOW)).is_null()
	var sim := SecondaryMotion.attach(sk, GfxQuality.HIGH)
	assert_object(sim).is_not_null()
	assert_int(sim.setting_count).is_equal(1)
	assert_str(sim.get_end_bone_name(0)).is_equal("Sec_coat_L_2")


func test_foot_ik_plan_lowers_pelvis_to_lowest_planted_foot() -> void:
	var p := FootIK.plan(-0.2, 0.0, 0.0, 0.0)
	assert_float(p.pelvis).is_equal_approx(-0.2, 0.001)
	assert_float(p.lift[0]).is_equal_approx(-0.2, 0.001)
	var up := FootIK.plan(0.2, 0.1, 0.0, 0.0)
	assert_float(up.pelvis).is_equal(0.0)
	assert_float(up.lift[0]).is_equal_approx(0.2, 0.001)


func test_foot_ik_ignores_swinging_foot_and_clamps_step() -> void:
	var p := FootIK.plan(-0.3, 0.0, 0.5, 0.0)  # left foot well off the ground in the clip
	assert_float(p.lift[0]).is_equal(0.0)
	assert_float(FootIK.plan(-2.0, 0.0, 0.0, 0.0).pelvis).is_equal_approx(-FootIK.MAX_STEP_M, 0.001)
