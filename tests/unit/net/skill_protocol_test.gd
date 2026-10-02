extends GdUnitTestSuite
## E10 snapshot fields round-trip (protocol v5): own motion-effect state
## (speed scale, dash), the skill bar block, hero status bits, Wardling
## Elite/Turned bits and the skill FX block.


func test_skill_fields_round_trip() -> void:
	var s := SnapshotData.new()
	s.tick = 77
	s.own_net_id = 3
	var m := MotorState.new()
	m.position = Vector3(1, 2, 3)
	m.speed_scale = 0.75
	m.dash_ticks = 7
	m.dash_velocity = Vector3(15.0, 4.5, -2.0)
	m.dash_launch = true
	s.own_state = m
	var c := SnapshotData.OwnCombat.new()
	c.hp = 400
	c.max_hp = 550
	c.skill_cd_left = PackedInt32Array([0, 300, 12, 3600])
	c.skill_cd_total = PackedInt32Array([0, 420, 600, 3600])
	c.skill_flags = PackedInt32Array([AbilityRunner.FLAG_ACTIVE, 0, AbilityRunner.FLAG_CASTING, AbilityRunner.FLAG_LOCKED])
	c.shield = 150
	c.level = 6
	c.status = StatusComponent.BIT_DR | StatusComponent.BIT_CC_IMMUNE
	s.own_combat = c
	var e := SnapshotData.EntityState.new()
	e.net_id = 5
	e.status = StatusComponent.BIT_STUN | StatusComponent.BIT_SLOW | StatusComponent.BIT_KNOCKBACK
	s.entities.append(e)
	var w := SnapshotData.WardlingState.new()
	w.net_id = 9
	w.state = 1 | (1 << 6) | (1 << 7)
	s.wardlings.append(w)
	var f := SnapshotData.FxState.new()
	f.id = 4242
	f.kind = AbilityWorld.FX_WALL
	f.team = 1
	f.position = Vector3(10.0, 0.0, -40.0)
	f.position2 = Vector3(6.0, 3.0, 0.4)
	f.yaw = 1.0
	f.param = 0.5
	f.ticks_left = 299
	s.fx.append(f)
	var d := SnapshotCodec.decode(SnapshotCodec.encode(s))
	assert_object(d).is_not_null()
	assert_float(d.own_state.speed_scale).is_equal(0.75)
	assert_int(d.own_state.dash_ticks).is_equal(7)
	assert_vector(d.own_state.dash_velocity).is_equal(Vector3(15.0, 4.5, -2.0))
	assert_bool(d.own_state.dash_launch).is_true()
	assert_array(Array(d.own_combat.skill_cd_left)).is_equal(Array(c.skill_cd_left))
	assert_array(Array(d.own_combat.skill_cd_total)).is_equal(Array(c.skill_cd_total))
	assert_array(Array(d.own_combat.skill_flags)).is_equal(Array(c.skill_flags))
	assert_int(d.own_combat.shield).is_equal(150)
	assert_int(d.own_combat.level).is_equal(6)
	assert_int(d.own_combat.status).is_equal(c.status)
	assert_int(d.entities[0].status).is_equal(e.status)
	assert_int(d.wardlings[0].state).is_equal(w.state)
	assert_int(d.fx.size()).is_equal(1)
	var g := d.fx[0]
	assert_int(g.id).is_equal(4242)
	assert_int(g.kind).is_equal(AbilityWorld.FX_WALL)
	assert_int(g.team).is_equal(1)
	assert_vector(g.position).is_equal_approx(f.position, Vector3.ONE * 0.05)
	assert_vector(g.position2).is_equal_approx(f.position2, Vector3.ONE * 0.05)
	assert_float(g.yaw).is_equal_approx(1.0, 0.03)
	assert_float(g.param).is_equal_approx(0.5, 0.01)
	assert_int(g.ticks_left).is_equal(299)
	assert_int(MsgType.PROTOCOL_VERSION).is_greater_equal(5)
