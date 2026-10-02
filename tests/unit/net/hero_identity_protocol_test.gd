extends GdUnitTestSuite
## M1 protocol v8: hero identity per entity (ContentDB stable hero index) and
## the Wardling Surge tier round-trip through the snapshot codec; ContentDB
## indices are stable (sorted ids, 0 = none) and cover the slice heroes.


func test_hero_index_and_wardling_tier_round_trip() -> void:
	var s := SnapshotData.new()
	s.tick = 901
	for i in 3:
		var e := SnapshotData.EntityState.new()
		e.net_id = 10 + i
		e.kind = EntityRegistry.KIND_HERO
		e.team = i % 2
		e.status = 0x0F0F
		e.hero_index = [1, 2, 65535][i]
		s.entities.append(e)
	for t in [1, 2, 3]:
		var w := SnapshotData.WardlingState.new()
		w.net_id = 100 + t
		w.state = 0xFF
		w.owner_net_id = 0xBEEF
		w.tier = t
		s.wardlings.append(w)
	var d := SnapshotCodec.decode(SnapshotCodec.encode(s))
	assert_object(d).is_not_null()
	assert_int(d.entities.size()).is_equal(3)
	for i in 3:
		assert_int(d.entities[i].hero_index).is_equal(s.entities[i].hero_index)
		assert_int(d.entities[i].status).is_equal(0x0F0F)  # neighbouring field intact
		assert_int(d.entities[i].team).is_equal(i % 2)
	assert_int(d.wardlings.size()).is_equal(3)
	for i in 3:
		assert_int(d.wardlings[i].tier).is_equal(i + 1)
		assert_int(d.wardlings[i].state).is_equal(0xFF)
		assert_int(d.wardlings[i].owner_net_id).is_equal(0xBEEF)


func test_unknown_hero_index_defaults_to_zero_and_round_trips() -> void:
	var s := SnapshotData.new()
	s.entities.append(SnapshotData.EntityState.new())
	var d := SnapshotCodec.decode(SnapshotCodec.encode(s))
	assert_int(d.entities[0].hero_index).is_equal(ContentDB.NONE)
	assert_int(SnapshotData.WardlingState.new().tier).is_equal(1)


func test_truncated_packet_with_the_new_fields_is_rejected() -> void:
	var s := SnapshotData.new()
	var e := SnapshotData.EntityState.new()
	e.hero_index = 2
	s.entities.append(e)
	var w := SnapshotData.WardlingState.new()
	w.tier = 3
	s.wardlings.append(w)
	var b := SnapshotCodec.encode(s)
	assert_object(SnapshotCodec.decode(b)).is_not_null()
	assert_object(SnapshotCodec.decode(b.slice(0, b.size() - 1))).is_null()


func test_protocol_version_bumped_for_the_identity_fields() -> void:
	assert_int(MsgType.PROTOCOL_VERSION).is_greater_equal(8)


func test_content_db_indices_are_sorted_stable_and_one_based() -> void:
	var db := ContentDB.from_ids({ContentDB.HERO: [&"hero_vesper_loom", &"hero_brannoc", &"hero_brannoc"]})
	assert_int(db.count(ContentDB.HERO)).is_equal(2)
	assert_int(db.index_of(ContentDB.HERO, &"hero_brannoc")).is_equal(1)
	assert_int(db.index_of(ContentDB.HERO, &"hero_vesper_loom")).is_equal(2)
	assert_int(db.index_of(ContentDB.HERO, &"hero_nobody")).is_equal(ContentDB.NONE)
	assert_str(String(db.id_at(ContentDB.HERO, 2))).is_equal("hero_vesper_loom")
	assert_str(String(db.id_at(ContentDB.HERO, 0))).is_equal("")
	assert_str(String(db.id_at(ContentDB.HERO, 3))).is_equal("")
	# Insertion order does not change the table.
	var other := ContentDB.from_ids({ContentDB.HERO: [&"hero_brannoc", &"hero_vesper_loom"]})
	assert_int(other.index_of(ContentDB.HERO, &"hero_vesper_loom")).is_equal(2)


func test_shared_content_db_indexes_the_slice_heroes() -> void:
	var db := ContentDB.shared()
	for id in [&"hero_brannoc", &"hero_vesper_loom"]:
		var i := db.index_of(ContentDB.HERO, id)
		assert_int(i).is_greater(ContentDB.NONE)
		assert_str(String(db.id_at(ContentDB.HERO, i))).is_equal(String(id))
		var def := load("res://assets/data/heroes/%s.tres" % id) as HeroDef
		assert_str(String(def.id)).is_equal(String(id))  # ADR-0003 §1: stem = id
	assert_int(db.index_of(ContentDB.HERO, &"hero_brannoc")).is_not_equal(db.index_of(ContentDB.HERO, &"hero_vesper_loom"))
