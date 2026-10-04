extends GdUnitTestSuite
## W10-W3: heal beam target choice, Sabotage remote detonation, Tripwire site
## choice, Relay Hop escape / reposition, and the seeded roster rotation.

const B := BotSkillBehaviours
const ROSTER := "res://assets/data/ai/bot_roster_slice.tres"


func _t() -> BotSkillTuning:
	return BotSkillTuning.new()


func test_beam_picks_most_injured_in_range_with_los() -> void:
	var allies: Array = [B.AllyView.new(1, 0.6, 8.0), B.AllyView.new(2, 0.3, 10.0),
		B.AllyView.new(3, 0.1, 9.0, false), B.AllyView.new(4, 0.05, 30.0)]
	assert_int(B.pick_beam_target(allies, 18.0, 0, _t())).is_equal(2)


func test_beam_ignores_healthy_allies() -> void:
	var allies: Array = [B.AllyView.new(1, 0.9, 5.0)]
	assert_int(B.pick_beam_target(allies, 18.0, 0, _t())).is_equal(0)


func test_beam_keeps_lock_until_release_threshold() -> void:
	var allies: Array = [B.AllyView.new(1, 0.9, 8.0), B.AllyView.new(2, 0.4, 8.0)]
	assert_int(B.pick_beam_target(allies, 18.0, 1, _t())).is_equal(1)
	allies = [B.AllyView.new(1, 0.99, 8.0), B.AllyView.new(2, 0.4, 8.0)]
	assert_int(B.pick_beam_target(allies, 18.0, 1, _t())).is_equal(2)


func test_beam_blocked_under_heavy_fire_only() -> void:
	var t := _t()
	assert_bool(B.beam_blocked(0.3, 0.5, t)).is_true()
	assert_bool(B.beam_blocked(0.9, 0.5, t)).is_false()
	assert_bool(B.beam_blocked(0.3, 10.0, t)).is_false()


func test_beam_mana_hysteresis() -> void:
	var t := _t()
	assert_bool(B.beam_mana_ok(0.1, false, t)).is_false()
	assert_bool(B.beam_mana_ok(0.1, true, t)).is_true()
	assert_bool(B.beam_mana_ok(0.02, true, t)).is_false()
	assert_bool(B.beam_mana_ok(0.5, false, t)).is_true()


func test_detonation_on_enemy_hero_in_radius() -> void:
	var charges := PackedVector3Array([Vector3(10, 0, 10)])
	var none := PackedVector3Array()
	assert_bool(B.detonation_wanted(charges, PackedVector3Array([Vector3(12, 0, 10)]), none, PackedFloat32Array(), 4.0, _t())).is_true()
	assert_bool(B.detonation_wanted(charges, PackedVector3Array([Vector3(16, 0, 10)]), none, PackedFloat32Array(), 4.0, _t())).is_false()


func test_detonation_near_enemy_generator() -> void:
	var charges := PackedVector3Array([Vector3(0, 0, 0)])
	var gp := PackedVector3Array([Vector3(5, 0, 0)])
	var gr := PackedFloat32Array([1.2])
	assert_bool(B.detonation_wanted(charges, PackedVector3Array(), gp, gr, 4.0, _t())).is_true()
	assert_bool(B.detonation_wanted(PackedVector3Array(), PackedVector3Array(), gp, gr, 4.0, _t())).is_false()
	assert_bool(B.detonation_wanted(charges, PackedVector3Array(), PackedVector3Array([Vector3(20, 0, 0)]), gr, 4.0, _t())).is_false()


## Straight path along -z toward a zone at the origin; a wall corridor probe.
func _path() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, -60), Vector3(0, 0, 0)])


func test_tripwire_prefers_narrowest_site() -> void:
	# Free width per site (by distance from the zone, z = -offset): the 12 m site is a choke.
	var probe := func(p: Vector3, _dir: Vector3) -> float:
		return 1.5 if is_equal_approx(p.z, -12.0) else 8.0
	var wire := B.pick_wire(_path(), 10.0, probe, _t())
	assert_int(wire.size()).is_equal(2)
	assert_float(wire[0].z).is_equal_approx(-12.0, 0.01)
	assert_float(wire[0].distance_to(wire[1])).is_equal_approx(3.0, 0.01)


func test_tripwire_caps_at_wire_length_and_rejects_narrow() -> void:
	var open := func(_p: Vector3, _d: Vector3) -> float: return 20.0
	var wire := B.pick_wire(_path(), 10.0, open, _t())
	assert_float(wire[0].distance_to(wire[1])).is_equal_approx(10.0, 0.01)
	var shut := func(_p: Vector3, _d: Vector3) -> float: return 0.5
	assert_int(B.pick_wire(_path(), 10.0, shut, _t()).size()).is_equal(0)
	assert_int(B.pick_wire(PackedVector3Array(), 10.0, open, _t()).size()).is_equal(0)


func test_tripwire_reach() -> void:
	var t := _t()
	assert_bool(B.wire_in_reach(Vector3.ZERO, Vector3(10, 0, 0), Vector3(0, 0, 10), 20.0, t)).is_true()
	assert_bool(B.wire_in_reach(Vector3.ZERO, Vector3(10, 0, 0), Vector3(0, 0, 25), 20.0, t)).is_false()


func test_hop_mode() -> void:
	var t := _t()
	assert_int(B.hop_mode(0.2, true, 10.0, t)).is_equal(B.HopMode.ESCAPE)
	assert_int(B.hop_mode(0.9, false, 40.0, t)).is_equal(B.HopMode.REPOSITION)
	assert_int(B.hop_mode(0.9, false, 10.0, t)).is_equal(B.HopMode.NONE)
	assert_int(B.hop_mode(0.9, true, 40.0, t)).is_equal(B.HopMode.NONE)
	assert_int(B.hop_mode(0.2, false, INF, t)).is_equal(B.HopMode.NONE)


func test_hop_escape_picks_gadget_nearest_home() -> void:
	var me := Vector3(0, 0, -100)
	var home := Vector3(0, 0, 0)
	var gadgets := PackedVector3Array([Vector3(0, 0, -95), Vector3(5, 0, -80), Vector3(0, 0, -75), Vector3(0, 0, -130)])
	# index 2 is the biggest gain in range (25 m < 28); index 1 is 20 m away, gain 20; index 3 moves away.
	assert_int(B.pick_hop_gadget(me, home, gadgets, 30.0, _t())).is_equal(2)
	assert_int(B.pick_hop_gadget(me, home, PackedVector3Array([Vector3(0, 0, -95)]), 30.0, _t())).is_equal(-1)
	assert_int(B.pick_hop_gadget(me, home, PackedVector3Array([Vector3(0, 0, -60)]), 30.0, _t())).is_equal(-1)  # out of range


func test_roster_rotation_covers_every_hero_deterministically() -> void:
	var roster := load(ROSTER) as BotRosterDef
	var seen := {}
	for seed_ in 7:
		var ids := []
		for team in 2:
			for slot in 3:
				ids.append(roster.hero_for_seeded(team, slot, 3, seed_).id)
		var again := []
		for team in 2:
			for slot in 3:
				again.append(roster.hero_for_seeded(team, slot, 3, seed_).id)
		assert_array(ids).is_equal(again)
		for id in ids:
			seen[id] = true
	assert_int(seen.size()).is_equal(roster.heroes.size())
	assert_object(roster.hero_for_seeded(0, 0, 3, -3)).is_not_null()
