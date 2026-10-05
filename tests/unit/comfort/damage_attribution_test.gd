extends GdUnitTestSuite
## W16-COMFORT: DamageAttribution per source type, AoE centre, environment fallback.

const OWN := Vector3(10.0, 1.0, 10.0)
const TEAM := 0
var rules := ComfortRulesDef.new()


func _r(obs: Dictionary) -> Dictionary:
	return DamageAttribution.resolve(OWN, TEAM, obs, rules)


func test_environment_damage_has_no_source() -> void:
	assert_int(_r({}).kind).is_equal(DamageAttribution.Kind.NONE)
	# far-away stuff does not count
	var far := {"wardlings": [{"pos": OWN + Vector3(30, 0, 0), "team": 1, "combat": true}],
		"bolts": [{"from": Vector3.ZERO, "to": OWN + Vector3(20, 0, 0)}]}
	assert_int(_r(far).kind).is_equal(DamageAttribution.Kind.NONE)


func test_hero_shot_uses_shooter_position() -> void:
	var shooter := OWN + Vector3(0, 0, -20)
	var r := _r({"shots": [{"pos": shooter, "impact": OWN + Vector3(0, 0, -0.5)}]})
	assert_int(r.kind).is_equal(DamageAttribution.Kind.HERO_SHOT)
	assert_vector(r.pos).is_equal(shooter)
	# a shot that stopped elsewhere is not ours
	assert_int(_r({"shots": [{"pos": shooter, "impact": OWN + Vector3(9, 0, 0)}]}).kind).is_equal(DamageAttribution.Kind.NONE)


func test_ranged_wardling_bolt() -> void:
	var from := OWN + Vector3(-12, 0, 0)
	var r := _r({"bolts": [{"from": from, "to": OWN + Vector3(0, 0.3, 0)}]})
	assert_int(r.kind).is_equal(DamageAttribution.Kind.BOLT)
	assert_vector(r.pos).is_equal(from)


func test_melee_wardling_enemy_in_combat_only() -> void:
	var w := OWN + Vector3(2.0, 0, 0)
	var r := _r({"wardlings": [{"pos": w, "team": 1, "combat": true}]})
	assert_int(r.kind).is_equal(DamageAttribution.Kind.MELEE)
	assert_vector(r.pos).is_equal(w)
	assert_int(_r({"wardlings": [{"pos": w, "team": 0, "combat": true}]}).kind).is_equal(DamageAttribution.Kind.NONE)  # ally
	assert_int(_r({"wardlings": [{"pos": w, "team": 1, "combat": false}]}).kind).is_equal(DamageAttribution.Kind.NONE)  # idle
	var near := OWN + Vector3(1.0, 0, 0)
	var two := _r({"wardlings": [{"pos": w, "team": 1, "combat": true}, {"pos": near, "team": 1, "combat": true}]})
	assert_vector(two.pos).is_equal(near)  # nearest


func test_aoe_direction_is_the_centre() -> void:
	var centre := OWN + Vector3(0, 0, 3)
	var fx := {"kind": AbilityWorld.FX_CIRCLE, "team": 1, "pos": centre, "pos2": Vector3(5, 0, 0)}
	var r := _r({"fx": [fx]})
	assert_int(r.kind).is_equal(DamageAttribution.Kind.AOE)
	assert_vector(r.pos).is_equal(centre)
	fx.pos2 = Vector3(1, 0, 0)  # too small to reach us (3 m away, margin 1)
	assert_int(_r({"fx": [fx]}).kind).is_equal(DamageAttribution.Kind.NONE)
	fx.pos2 = Vector3(5, 0, 0)
	fx.team = 0  # own team's area never counts
	assert_int(_r({"fx": [fx]}).kind).is_equal(DamageAttribution.Kind.NONE)


func test_line_and_projectile_and_burst() -> void:
	var line := {"kind": AbilityWorld.FX_TRAIL, "team": 1, "pos": OWN + Vector3(-5, 0, 1), "pos2": OWN + Vector3(5, 0, 1)}
	var r := _r({"fx": [line]})
	assert_int(r.kind).is_equal(DamageAttribution.Kind.LINE)
	assert_float(r.pos.z).is_equal_approx(OWN.z + 1.0, 0.01)
	var thread := {"kind": AbilityWorld.FX_THREAD, "team": 1, "pos": OWN + Vector3(0, 0, -2), "pos2": Vector3.ZERO}
	assert_int(_r({"fx": [thread]}).kind).is_equal(DamageAttribution.Kind.PROJECTILE)
	var burst := {"kind": AbilityWorld.FX_BURST, "team": 1, "pos": OWN, "pos2": Vector3(4, 0, 0)}
	assert_int(_r({"fx": [burst]}).kind).is_equal(DamageAttribution.Kind.AOE)


func test_instant_cast_fallback_and_priority() -> void:
	var caster := OWN + Vector3(0, 0, 15)
	assert_int(_r({"casts": [{"pos": caster}]}).kind).is_equal(DamageAttribution.Kind.CAST)
	# a concrete hit beats the cast guess
	var w := OWN + Vector3(2, 0, 0)
	var r := _r({"casts": [{"pos": caster}], "wardlings": [{"pos": w, "team": 1, "combat": true}]})
	assert_int(r.kind).is_equal(DamageAttribution.Kind.MELEE)
	assert_int(_r({"casts": [{"pos": OWN + Vector3(0, 0, 90)}]}).kind).is_equal(DamageAttribution.Kind.NONE)  # out of range


func test_attribution_direction_feeds_indicator() -> void:
	# AoE centre behind (yaw 0 faces -Z): the indicator points to the rear.
	var fx := {"kind": AbilityWorld.FX_CIRCLE, "team": 1, "pos": OWN + Vector3(0, 0, 3), "pos2": Vector3(5, 0, 0)}
	var r := _r({"fx": [fx]})
	assert_float(absf(DamageFeedbackModel.relative_angle(OWN, 0.0, r.pos))).is_equal_approx(PI, 0.01)
