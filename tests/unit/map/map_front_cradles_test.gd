extends GdUnitTestSuite
## E14 Cell Cradles on Shardline Front (match-flow-and-map.md §3.4 Plant 1): no two
## Cradles share a spot (a Mid between two Plant nodes hosts one of each team;
## found overlapping in the Phase 6b frames), and the layout stays mirror symmetric.

const MAP_PATH := "res://assets/data/match/map_front.tres"


func _cradles(def: MapDef) -> Array:
	var out: Array = []
	for lane: LaneDef in def.lanes:
		for h: HardpointDef in lane.hardpoints:
			for team in h.cell_cradles.size():
				out.append([String(h.id), team, h.cell_cradles[team]])
	return out


func test_no_two_cradles_share_a_spot() -> void:
	var all := _cradles(load(MAP_PATH) as MapDef)
	assert_int(all.size()).is_greater(0)
	for i in all.size():
		for j in range(i + 1, all.size()):
			var d := Vector2(all[i][2].x - all[j][2].x, all[i][2].z - all[j][2].z).length()
			assert_float(d).override_failure_message("%s/%d and %s/%d Cradles %.1f m apart" % [
				all[i][0], all[i][1], all[j][0], all[j][1], d]).is_greater(4.0)


func test_cradles_are_mirror_symmetric() -> void:
	var def := load(MAP_PATH) as MapDef
	# The map mirrors along L (world z) about the midpoint of the two Uplinks.
	var mid_z := (def.hq(MapDef.TEAM_CONCORD).uplink.z + def.hq(MapDef.TEAM_SYNDICATE).uplink.z) * 0.5
	var concord: Array = []
	var syndicate: Array = []
	for c in _cradles(def):
		(concord if c[1] == MapDef.TEAM_CONCORD else syndicate).append(c[2])
	assert_int(concord.size()).is_equal(syndicate.size())
	for p: Vector3 in concord:
		var mirrored := Vector3(p.x, p.y, 2.0 * mid_z - p.z)
		var found := false
		for q: Vector3 in syndicate:
			found = found or q.distance_to(mirrored) < 0.1
		assert_bool(found).override_failure_message("no mirror for Concord Cradle %s" % p).is_true()
