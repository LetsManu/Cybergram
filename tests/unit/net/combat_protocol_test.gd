extends GdUnitTestSuite
## Combat fields in snapshots and the Event codec (architecture.md §8.2).


func test_snapshot_round_trip_carries_own_combat_and_entity_health() -> void:
	var s := SnapshotData.new()
	s.tick = 900
	s.own_net_id = 2
	s.own_state = MotorState.new()
	var c := SnapshotData.OwnCombat.new()
	c.hp = 187
	c.max_hp = 250
	c.dead = true
	c.respawn_tick = 1081
	c.feed_kind = WeaponDef.FeedKind.MANA
	c.ammo = 41.5
	c.ammo_capacity = 100
	c.reserve = 0
	c.ammo_flags = AmmoFeed.FLAG_BURNOUT
	s.own_combat = c
	var e := SnapshotData.EntityState.new()
	e.net_id = 5
	e.kind = EntityRegistry.KIND_HERO
	e.dead = true
	e.team = 1
	e.hp = 0
	e.max_hp = 550
	e.grounded = true
	s.entities.append(e)
	var d := SnapshotCodec.decode(SnapshotCodec.encode(s))
	assert_object(d).is_not_null()
	assert_int(d.own_combat.hp).is_equal(187)
	assert_int(d.own_combat.max_hp).is_equal(250)
	assert_bool(d.own_combat.dead).is_true()
	assert_int(d.own_combat.respawn_tick).is_equal(1081)
	assert_float(d.own_combat.ammo).is_equal(41.5)
	assert_int(d.own_combat.ammo_capacity).is_equal(100)
	assert_int(d.own_combat.ammo_flags).is_equal(AmmoFeed.FLAG_BURNOUT)
	var de := d.entities[0]
	assert_bool(de.dead).is_true()
	assert_bool(de.grounded).is_true()
	assert_int(de.team).is_equal(1)
	assert_int(de.max_hp).is_equal(550)


func test_event_round_trip() -> void:
	var events: Array[GameEvent] = [
		GameEvent.hit_confirm(4, 2, 50.75, GameEvent.FLAG_HEADSHOT, Vector3(1, 2, 3)),
		GameEvent.kill(4, 2, Vector3(-1, 0, 5)),
	]
	var out: Array[GameEvent] = []
	assert_int(EventCodec.decode(EventCodec.encode(77, events), out)).is_equal(77)
	assert_int(out.size()).is_equal(2)
	assert_int(out[0].kind).is_equal(GameEvent.HIT_CONFIRM)
	assert_int(out[0].target_net_id).is_equal(4)
	assert_int(out[0].source_net_id).is_equal(2)
	assert_float(out[0].amount).is_equal(50.75)
	assert_int(out[0].flags).is_equal(GameEvent.FLAG_HEADSHOT)
	assert_vector(out[0].position).is_equal(Vector3(1, 2, 3))
	assert_int(out[1].kind).is_equal(GameEvent.KILL)


func test_malformed_event_is_rejected() -> void:
	var events: Array[GameEvent] = [GameEvent.kill(4, 2, Vector3.ZERO)]
	var b := EventCodec.encode(1, events)
	b.resize(b.size() - 1)
	var out: Array[GameEvent] = []
	assert_int(EventCodec.decode(b, out)).is_equal(-1)
