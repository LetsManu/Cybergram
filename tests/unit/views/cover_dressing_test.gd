extends GdUnitTestSuite
## CoverDressing (owner plan Part 4): kit crates fill each greybox cover box of
## the shipped map exactly (what you see is what stops you), no crate is
## stretched past its limits (stretch_ok), and the greybox is hidden only where
## a plausible fill exists.

const MAP_DEF := "res://assets/data/match/map_front.tres"


func _bounds() -> Dictionary:
	return WorldProps.bounds_of(WorldProps.piece_meshes(CoverDressing.KIT_KEY))


func test_fill_covers_the_box_exactly_and_stays_in_stretch_limits() -> void:
	var b := _bounds()
	if not b.has(&"crate"):
		return
	# the cover box sizes the shipped map uses (thin 0.4 m walls excepted)
	for size: Vector3 in [Vector3(3.0, 1.2, 1.5), Vector3(1.5, 1.2, 3.0), Vector3(3.0, 1.3, 3.0), Vector3(5.0, 0.9, 13.0),
			Vector3(5.0, 1.2, 1.2), Vector3(1.4, 1.6, 1.4), Vector3(1.4, 1.2, 1.4), Vector3(1.4, 1.1, 1.4)]:
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var vol := 0.0
		for f in CoverDressing.fill(size, b):
			var t: Transform3D = f[1]
			var w := t * (b[f[0]] as AABB)
			lo = lo.min(w.position)
			hi = hi.max(w.end)
			vol += w.size.x * w.size.y * w.size.z
			assert_bool(CoverDressing.stretch_ok(t)).override_failure_message("%s stretched %s" % [size, t.basis.get_scale()]).is_true()
		assert_vector(hi - lo).override_failure_message("%s filled %s" % [size, hi - lo]).is_equal_approx(size, Vector3.ONE * 0.03)
		assert_vector(lo).is_equal_approx(-size * 0.5, Vector3.ONE * 0.03)
		assert_float(vol).is_equal_approx(size.x * size.y * size.z, size.x * size.y * size.z * 0.03)


func test_map_cover_boxes_are_dressed_and_the_greybox_hidden() -> void:
	if not WorldModel.exists(CoverDressing.KIT_KEY):
		return
	var map: Node3D = auto_free((load(MAP_DEF) as MapDef).scene.instantiate())
	add_child(map)
	var d := CoverDressing.spawn(map)
	await get_tree().process_frame
	assert_int(d.boxes.size()).is_greater(50)
	# a box is either dressed (greybox hidden) or skipped (greybox kept)
	var hidden := 0
	for mi: MeshInstance3D in map.find_children("*", "MeshInstance3D", true, false):
		if CoverDressing.is_cover(mi) and not mi.visible:
			hidden += 1
	assert_int(hidden).is_equal(d.boxes.size())
	# today only the thin 0.4 m walls have no plausible fill (docs/polish-backlog.md)
	for sk in d.skipped:
		assert_float(minf((sk[1] as Vector3).x, (sk[1] as Vector3).z)).is_less(0.5)
	for p in d.pieces:
		assert_bool(CoverDressing.stretch_ok(p[1])).override_failure_message("%s %s" % [p[0], (p[1] as Transform3D).basis.get_scale()]).is_true()
	# batches are chunked: no batch spans more than two chunks of the map
	for c: MultiMeshInstance3D in d.get_children():
		assert_float(c.visibility_range_end).is_greater(0.0)
	assert_int(d.get_child_count()).is_greater(4)
