extends GdUnitTestSuite
## C6 public build replication (items-and-armory.md §3.8 rule 7): every hero's
## sockets, Chamber and open slots ride in the HERO record's own delta group,
## so they cost bytes only when the build changes.

const BUILD_A: Array[int] = [19, 21, 23, 44, 49, 9, 9, 33, -1, 14, 18]
const BUILD_B: Array[int] = [29, 21, 23, 44, 49, -1, 9, 33, -1, 14, 18]


func _hero(net_id: int, build: Array[int]) -> SnapshotData.EntityState:
	var e := SnapshotData.EntityState.new()
	e.net_id = net_id
	e.kind = 1
	e.position = Vector3(1, 2, 3)
	e.hp = 100
	e.max_hp = 100
	e.hero_index = 2
	e.build = PackedInt32Array(build)
	return e


func _snap(tick: int, heroes: Array[SnapshotData.EntityState]) -> SnapshotData:
	var s := SnapshotData.new()
	s.tick = tick
	s.entities = heroes
	return s


func test_build_round_trips_in_the_hero_record() -> void:
	var e := _hero(7, BUILD_A)
	var d := SnapshotCodec.hero_from(7, SnapshotCodec.hero_record(e))
	assert_array(Array(d.build)).is_equal(Array(BUILD_A))
	assert_int(SnapshotCodec.hero_record(e).size()).is_equal(SnapshotCodec.RECORD_SIZE[SnapshotCodec.SEC_HERO])


func test_empty_build_round_trips_as_all_minus_one() -> void:
	var e := SnapshotData.EntityState.new()
	var d := SnapshotCodec.hero_from(1, SnapshotCodec.hero_record(e))
	for v in d.build:
		assert_int(v).is_equal(-1)


func test_full_snapshot_carries_every_heros_build() -> void:
	var heroes: Array[SnapshotData.EntityState] = [_hero(3, BUILD_A), _hero(4, BUILD_B)]
	var d := SnapshotCodec.decode(SnapshotCodec.encode(_snap(10, heroes)))
	assert_object(d).is_not_null()
	assert_int(d.entities.size()).is_equal(2)
	var by_id := {}
	for e in d.entities:
		by_id[e.net_id] = e
	assert_array(Array((by_id[3] as SnapshotData.EntityState).build)).is_equal(Array(BUILD_A))
	assert_array(Array((by_id[4] as SnapshotData.EntityState).build)).is_equal(Array(BUILD_B))


func test_unchanged_build_costs_no_bytes_in_a_delta() -> void:
	var base := SnapshotCodec.encode_delta(_snap(10, [_hero(3, BUILD_A)] as Array[SnapshotData.EntityState]), null, 0)
	var same := SnapshotCodec.encode_delta(_snap(11, [_hero(3, BUILD_A)] as Array[SnapshotData.EntityState]), base.view, 0)
	var changed := SnapshotCodec.encode_delta(_snap(11, [_hero(3, BUILD_B)] as Array[SnapshotData.EntityState]), base.view, 0)
	# A build change is one keyed update: u16 key + u8 mask + the 11-byte group.
	assert_int(changed.bytes.size() - same.bytes.size()).is_equal(2 + 1 + SnapshotData.EntityState.BUILD_SIZE)


func test_delta_applies_a_build_change() -> void:
	var enc := SnapshotEncoder.new(32, 0)
	var dec := SnapshotDecoder.new(64)
	assert_object(dec.decode(enc.encode(_snap(10, [_hero(3, BUILD_A)] as Array[SnapshotData.EntityState]), 0))).is_not_null()
	var d := dec.decode(enc.encode(_snap(11, [_hero(3, BUILD_B)] as Array[SnapshotData.EntityState]), 10))
	assert_object(d).is_not_null()
	assert_bool(d.is_delta).is_true()
	assert_array(Array(d.entities[0].build)).is_equal(Array(BUILD_B))


func test_spare_is_a_later_copy_in_the_open_slots() -> void:
	var e := _hero(3, BUILD_A)
	assert_bool(e.is_spare(0)).is_false()
	assert_bool(e.is_spare(1)).is_true()
	assert_bool(e.is_spare(2)).is_false()
	assert_bool(e.is_spare(3)).is_false()


## C2 prediction parity: the 4 weapon multipliers ride in OWN_COMBAT as hundredths.
func test_own_combat_weapon_multipliers_round_trip() -> void:
	var c := SnapshotData.OwnCombat.new()
	c.weapon_rate_mult = 1.15
	c.weapon_spread_mult = 0.62
	c.weapon_recoil_mult = 0.8
	c.weapon_kick_mult = 0.35
	var d := SnapshotCodec.own_combat_from(SnapshotCodec.own_combat_blob(c))
	assert_float(d.weapon_rate_mult).is_equal_approx(1.15, 0.005)
	assert_float(d.weapon_spread_mult).is_equal_approx(0.62, 0.005)
	assert_float(d.weapon_recoil_mult).is_equal_approx(0.8, 0.005)
	assert_float(d.weapon_kick_mult).is_equal_approx(0.35, 0.005)
	c.weapon_rate_mult = 9.0
	assert_float(SnapshotCodec.own_combat_from(SnapshotCodec.own_combat_blob(c)).weapon_rate_mult).is_equal(2.55)


## C3: the Lattice overshield rides in OWN_COMBAT as a u16.
func test_own_combat_overshield_round_trip() -> void:
	var c := SnapshotData.OwnCombat.new()
	c.overshield = 80
	assert_int(SnapshotCodec.own_combat_from(SnapshotCodec.own_combat_blob(c)).overshield).is_equal(80)
	c.overshield = 0
	assert_int(SnapshotCodec.own_combat_from(SnapshotCodec.own_combat_blob(c)).overshield).is_equal(0)
