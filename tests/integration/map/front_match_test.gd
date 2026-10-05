extends GdUnitTestSuite
## W14-M2 Shardline Front in a live ServerWorld:
##  * the baked navmesh reaches all 15 hardpoints, both HQs (Sanctum, Uplink,
##    Foundry, Armory, 3 lane gates) and every Undercroft junction from each Sanctum;
##  * Vanguard (C15): one wave of 4 per lane per team from that lane's gate, and
##    never more than 4 wave members per lane per team (max 1 live wave);
##  * a full 5v5 bots match on the map's own rules reaches End.

const DEF_PATH := "res://assets/data/match/map_front.tres"
const HZ: int = 30
const ROSTER := "res://assets/data/ai/bot_roster_slice.tres"


func _def() -> MapDef:
	return load(DEF_PATH) as MapDef


func _server(vanguard: bool) -> ServerWorld:
	var def := _def()
	var built := WardlingFixtures.slice_server(self, WardlingFixtures.rules(), vanguard, def.match_rules, def)
	auto_free(built[3])
	return built[0]


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func test_navmesh_reaches_every_hardpoint_hq_and_flank() -> void:
	var server := _server(false)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var nav := server.get_world_3d().navigation_map
	var targets: Array = []
	for lane in def.lanes:
		for h in lane.hardpoints:
			targets.append([String(h.id), h.position, h.zone_radius * 0.5])
		for f in lane.flank_loops:
			targets.append([String(f.id) + "_junction", f.waypoints[2], 2.0])
			targets.append([String(f.id) + "_door", f.mid_door, 2.5])
	for hq in def.hqs:
		var t := "hq%d_" % hq.team
		targets.append([t + "sanctum", hq.spawn_points[0], 1.5])
		targets.append([t + "uplink", hq.uplink + Vector3(0, 0, 6.0 if hq.team == 0 else -6.0), 2.0])
		targets.append([t + "foundry", hq.foundry, 2.0])
		targets.append([t + "armory", hq.armory, 2.0])
		for g in hq.lane_gates:
			targets.append([t + "gate", g, 1.5])
	var bad: Array = []
	for hq in def.hqs:
		var start := hq.spawn_points[2]
		for t in targets:
			var p := NavigationServer3D.map_get_path(nav, start, t[1], true)
			if p.size() < 2 or _flat(p[p.size() - 1], t[1]) > t[2] or absf(p[p.size() - 1].y - t[1].y) > 1.5:
				bad.append("%d->%s" % [hq.team, t[0]])
	assert_array(bad).is_empty()
	assert_int(targets.size()).is_equal(15 + 16 + 2 * 7)


func test_lanes_are_mirror_symmetric_and_short() -> void:
	var server := _server(false)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var nav := server.get_world_3d().navigation_map
	for li in 3:
		var hps := def.lanes[li].hardpoints
		var a := NavigationServer3D.map_get_path(nav, def.hq(0).spawn_points[2], hps[2].position, true)
		var b := NavigationServer3D.map_get_path(nav, def.hq(1).spawn_points[2], hps[2].position, true)
		var la := _len(a)
		var lb := _len(b)
		print("front lane %d: Sanctum -> Mid %.0f m / %.0f m" % [li, la, lb])
		assert_float(la).is_equal_approx(lb, 10.0)  # navmesh tessellation differs per half
		# GDD §3.2: Sanctum -> own C-Mid 210 m, N/S-Mid 255 m (first-person run 35-43 s).
		assert_float(la).is_between(195.0, 290.0)


static func _len(p: PackedVector3Array) -> float:
	var l := 0.0
	for i in p.size() - 1:
		l += p[i].distance_to(p[i + 1])
	return l


func test_a_vanguard_wave_per_lane_per_team() -> void:
	var server := _server(true)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var ww := server.wardlings
	ww.clock_scale = 60.0
	var spawned := []
	ww.vanguard_wave_spawned.connect(func(team: int, lane: int, n: int) -> void: spawned.append([team, lane, n]))
	while server.tick < 3 * HZ and spawned.size() < 6:
		server.step()
	assert_int(spawned.size()).is_equal(6)
	var seen := {}
	for s in spawned:
		seen["%d:%d" % [s[0], s[1]]] = s[2]
	for team in 2:
		for lane in 3:
			assert_int(seen.get("%d:%d" % [team, lane], 0)).is_equal(4)
	# Each wave starts at its own lane gate.
	for w in ww.waves:
		var gate := def.hq(w.team).gate_for_lane(w.lane)
		for m in w.members:
			assert_float(_flat(m.global_position, gate)).is_less(20.0)
	# Max 1 live wave: per lane per team never more than 4 members.
	for i in 20 * HZ:
		server.step()
		if i % 15 == 0:
			for team in 2:
				var per := [0, 0, 0]
				for w in ww.waves:
					if w.team == team:
						per[w.lane] += w.alive_count()
				for lane in 3:
					assert_int(per[lane]).is_less_equal(4)
	assert_int(ww.vanguard_count(0)).is_less_equal(12)


func test_full_five_v_five_bots_match_reaches_end() -> void:
	var def := _def()
	var server := _server(true)
	server.setup_match(def, 120.0)  # 60:00 in 30 s of sim time
	server.wardlings.clock_scale = 120.0
	server.enable_progression(load("res://assets/data/economy/economy_rules_slice.tres") as EconomyRulesDef,
		load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef, def)
	var roster := load(ROSTER) as BotRosterDef
	var director := BotDirector.new()
	director.setup(server, roster, roster.profile("normal"), 7)
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	assert_int(director.fill(false)).is_equal(10)
	var lanes_seen := {}
	var peak_ai := 0
	while server.tick < 45 * HZ and not server.match_flow.is_over():
		server.step()
		if server.tick % HZ == 0:
			for b in director.brains:
				lanes_seen[b.lane] = true
			peak_ai = maxi(peak_ai, server.wardlings.wardlings.size())
	print("front 5v5: end %s winner %d at %s, lanes used %s, peak AI %d" % [MatchRules.EndReason.keys()[server.match_flow.end_reason],
		server.match_flow.winner, MatchRules.format_clock(server.match_flow.time_s), lanes_seen.keys(), peak_ai])
	assert_bool(server.match_flow.is_over()).is_true()
	assert_int(lanes_seen.size()).is_equal(3)
	assert_int(peak_ai).is_less_equal(110)


# ---------------------------------------------------------------- W18-GEO living map

const RUN_SPEED := 6.0
const ALL_LAYERS := 1 | MapDef.JUNGLE_NAV_LAYER


func _map_node(server: ServerWorld) -> Node3D:
	return server.find_child("ShardlineFront", false, false) as Node3D


func _ray_down(server: ServerWorld, x: float, z: float, top := 40.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -40.0, z), HeroBody.LAYER_WORLD)
	return server.get_world_3d().direct_space_state.intersect_ray(q)


static func _plen(p: PackedVector3Array) -> float:
	return _len(p)


func _reach(nav: RID, from: Vector3, to: Vector3, layers: int, tol: float) -> PackedVector3Array:
	var p := NavigationServer3D.map_get_path(nav, from, to, true, layers)
	if p.size() < 2 or _flat(p[p.size() - 1], to) > tol or absf(p[p.size() - 1].y - to.y) > 1.5:
		return PackedVector3Array()
	return p


## Every enterable building (owner: 1-2 rooms, a window, a back door, doorways
## >= 2 m) and its interior is on the lane navmesh.
func test_buildings_enterable_with_wide_doors() -> void:
	var server := _server(false)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var nav := server.get_world_3d().navigation_map
	var b_root := _map_node(server).get_node("Buildings")
	assert_int(b_root.get_child_count()).is_equal(8)  # per half: guardhouse, warehouse, 2 market shops
	var bad: Array = []
	var space := server.get_world_3d().direct_space_state
	for b in b_root.get_children():
		var doors := 0
		var windows := 0
		for m: Node3D in b.get_children():
			var n := String(m.name)
			if n.begins_with("Interior"):
				if _reach(nav, def.hq(0).spawn_points[2], m.global_position, ALL_LAYERS, 1.2).is_empty():
					bad.append("%s/%s unreachable" % [b.name, n])
			elif n.begins_with("Door") or n == "InnerDoor":
				if n.begins_with("Door"):
					doors += 1
				var w: float = m.get_meta("width")
				if w < 2.0:
					bad.append("%s/%s width %.2f" % [b.name, n, w])
				# A 2.0 m x 2.4 m probe fits through the opening (nothing solid in it).
				var box := BoxShape3D.new()
				var along_x: bool = m.get_meta("axis") == "x"
				box.size = Vector3(1.9, 2.3, 0.1) if along_x else Vector3(0.1, 2.3, 1.9)
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = box
				q.collision_mask = HeroBody.LAYER_WORLD
				q.transform = Transform3D(Basis(), m.global_position + Vector3(0, 1.3, 0))
				if not space.intersect_shape(q, 4).is_empty():
					bad.append("%s/%s blocked" % [b.name, n])
				var h: float = m.get_meta("height")
				if h < 2.6:
					bad.append("%s/%s low" % [b.name, n])
			elif n.begins_with("Window"):
				windows += 1
		if doors < 2 or windows < 1:
			bad.append("%s doors %d windows %d" % [b.name, doors, windows])
		if float(b.get_meta("ceiling_y")) - float(b.get_meta("floor_y")) < 4.0:
			bad.append("%s ceiling" % b.name)
	assert_array(bad).is_empty()


## Mirror symmetry across L = 210 of the collision world (top hit heights).
func test_geometry_is_mirror_symmetric() -> void:
	var server := _server(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bad: Array = []
	var n := 0
	var x := -134.0
	while x <= 134.0:
		var l := -4.0
		while l < 209.0:
			var a := _ray_down(server, x + 0.37, -(l + 0.29))
			var b := _ray_down(server, x + 0.37, -(LANE_LEN_M - l - 0.29))
			n += 1
			if a.is_empty() != b.is_empty():
				bad.append("%.1f,%.1f hit/miss" % [x, l])
			elif not a.is_empty() and absf((a.position as Vector3).y - (b.position as Vector3).y) > 0.2:
				bad.append("%.1f,%.1f dy %.2f" % [x, l, (a.position as Vector3).y - (b.position as Vector3).y])
			l += 2.0
		x += 2.0
	print("mirror samples %d, mismatches %d %s" % [n, bad.size(), bad.slice(0, 8)])
	assert_int(bad.size()).is_less_equal(n / 200)  # < 0.5 %: rail-piece tessellation only


const LANE_LEN_M := 420.0


## Walkable slopes. A 1 m ray grid over the whole map: no walkable surface
## (on the navmesh, normal within 50 degrees of up; steeper is a wall or prop face the motor cannot stand on at 46) is steeper than 32.5 degrees, so every stair
## wedge and ramp stays well under HeroMotor's 46 degree floor angle; and the
## rolling lane floors stay <= 20 degrees (owner: hills walkable up to ~20).
func test_slopes_stay_walkable() -> void:
	var server := _server(false)
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, _def())).is_true()
	var nav := server.get_world_3d().navigation_map
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var lane_worst := 0.0
	var x := -134.6
	while x <= 134.0:
		var l := -5.4
		while l < 425.0:
			var a := _ray_down(server, x, -l)
			if not a.is_empty():
				var ang := rad_to_deg(acos(clampf((a.normal as Vector3).y, -1.0, 1.0)))
				var on_nav := (NavigationServer3D.map_get_closest_point(nav, a.position) as Vector3).distance_to(a.position) < 0.6
				if on_nav and ang < 50.0 and ang > worst:
					worst = ang
					worst_at = a.position
				if String((a.collider as Node).name).begins_with("Rolling"):
					lane_worst = maxf(lane_worst, ang)
			l += 1.0
		x += 1.0
	print("steepest walkable surface %.1f deg at %s, rolling lanes %.1f deg" % [worst, worst_at, lane_worst])
	assert_float(worst).is_less_equal(32.5)
	assert_float(lane_worst).is_less_equal(20.0)


## Hardpoint zones sit on flat ground: >= 85 % of a 1 m grid inside each zone
## hits the floor within -0.3 .. +0.7 m of the hardpoint (dais / plinth / props).
func test_hardpoint_zones_are_flat() -> void:
	var server := _server(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bad: Array = []
	for lane in _def().lanes:
		for h in lane.hardpoints:
			var ok := 0
			var n := 0
			var r := h.zone_radius
			var dx := -r
			while dx <= r:
				var dz := -r
				while dz <= r:
					if dx * dx + dz * dz <= r * r:
						n += 1
						var hit := _ray_down(server, h.position.x + dx, h.position.z + dz, h.position.y + 2.0)
						var prop := not hit.is_empty() and String((hit.collider as Node).name).begins_with("Skiff")
						if prop:
							ok += 1  # the dock skiff is low cover standing in the zone, not terrain
						elif not hit.is_empty():
							var dy: float = (hit.position as Vector3).y - h.position.y
							if dy >= -0.3 and dy <= 0.7:
								ok += 1
					dz += 1.0
				dx += 1.0
			if float(ok) / n < 0.85:
				bad.append("%s %.2f" % [h.id, float(ok) / n])
	assert_array(bad).is_empty()


## Capture zones are never fully covered from one camping spot: from every
## raised spot (navmesh vertex >= 2 m up) and every building window within the
## 70 m sightline cap, at least one of the zone's 13 sample points is hidden.
func test_no_single_spot_covers_a_whole_zone() -> void:
	var server := _server(false)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var spots := PackedVector3Array()
	var mp := _map_node(server)
	for r in [mp.get_node("NavRegion"), mp.get_node("NavRegionJungle")]:
		for v in ((r as NavigationRegion3D).navigation_mesh as NavigationMesh).get_vertices():
			if v.y >= 2.0 and not _reach(server.get_world_3d().navigation_map, def.hq(0).spawn_points[2], v, ALL_LAYERS, 0.6).is_empty():
				spots.append(v + Vector3(0, 1.5, 0))
	for b in mp.get_node("Buildings").get_children():
		for m: Node3D in b.get_children():
			if String(m.name).begins_with("Window"):
				spots.append(m.global_position + Vector3(0, 0.6, 0))
	var space := server.get_world_3d().direct_space_state
	var bad: Array = []
	for lane in def.lanes:
		for h in lane.hardpoints:
			var pts := PackedVector3Array([h.position + Vector3(0, 1.0, 0)])
			for k in 12:
				var a := TAU * k / 12.0
				var rr := h.zone_radius * (0.85 if k % 2 == 0 else 0.5)
				pts.append(h.position + Vector3(cos(a) * rr, 1.0, sin(a) * rr))
			for sp in spots:
				if _flat(sp, h.position) > 70.0:
					continue
				var seen := 0
				for p in pts:
					var q := PhysicsRayQueryParameters3D.create(sp, p, HeroBody.LAYER_WORLD)
					if space.intersect_ray(q).is_empty():
						seen += 1
				if seen == pts.size():
					bad.append("%s from %s" % [h.id, sp.snapped(Vector3.ONE)])
					break
	print("zones fully covered from one spot: %s" % [bad])
	assert_array(bad).is_empty()


## The jungle: every pocket and route point is on the jungle navmesh (heroes /
## bots, all layers); Wardlings (layer 1 only) can never path into it; lane to
## lane through it takes 8-15 s at run speed; the lane stays the fastest way
## forward.
func test_jungle_network_reach_times_and_wardling_exclusion() -> void:
	var server := _server(false)
	var def := _def()
	assert_bool(await WardlingFixtures.await_nav(get_tree(), server, def)).is_true()
	var nav := server.get_world_3d().navigation_map
	var start := def.hq(0).spawn_points[2]
	var bad: Array = []
	assert_int(def.jungle_pockets.size()).is_equal(8)
	assert_int(def.jungle_paths.size()).is_equal(24)
	for p in def.jungle_pockets:
		if _reach(nav, start, p.center, ALL_LAYERS, 1.5).is_empty():
			bad.append("pocket " + String(p.id))
		# Wardlings: a layer-1 path toward a pocket stops short of it.
		var w := NavigationServer3D.map_get_path(nav, start, p.center, true, 1)
		if w.size() > 1 and _flat(w[w.size() - 1], p.center) < 3.0:
			bad.append("wardling reaches " + String(p.id))
	for path in def.jungle_paths:
		for pt in path:
			if _reach(nav, start, pt, ALL_LAYERS, 1.5).is_empty():
				bad.append("route point %s" % pt.snapped(Vector3.ONE * 0.1))
	assert_array(bad).is_empty()
	# Lane-to-lane rotation times (entrance to entrance), both halves, both gaps.
	var times: Array = []
	for half in 2:
		for s in [-1.0, 1.0]:
			var lo := func(l: float) -> float: return -(l if half == 0 else LANE_LEN_M - l)
			for pair in [[Vector3(0.0, 0.0, lo.call(76.0)), Vector3(s * 80.0, 0.0, lo.call(76.0))],
					[Vector3(0.0, 0.0, lo.call(136.0)), Vector3(s * 80.0, lane_y(s, 114.5), lo.call(114.5))]]:
				var p := _reach(nav, pair[0], pair[1], ALL_LAYERS, 1.5)
				var t := _plen(p) / RUN_SPEED
				times.append(snappedf(t, 0.1))
				if p.is_empty() or t < 8.0 or t > 15.0:
					bad.append("rotation %s -> %s %.1f s" % [pair[0], pair[1], t])
	print("jungle lane-to-lane times (s): %s" % [times])
	# The lane is the fastest way forward: Inner -> Outer pad paths match with
	# and without the jungle.
	for lane in def.lanes:
		var a := NavigationServer3D.map_get_path(nav, lane.hardpoints[0].position, lane.hardpoints[1].position, true, 1)
		var b := NavigationServer3D.map_get_path(nav, lane.hardpoints[0].position, lane.hardpoints[1].position, true, ALL_LAYERS)
		if _plen(b) < _plen(a) - 1.0:
			bad.append("%s: jungle shortcut %.0f < %.0f" % [lane.id, _plen(b), _plen(a)])
	assert_array(bad).is_empty()


static func lane_y(s: float, l: float) -> float:
	# North rolls down 2 m between pads at L 100..130 (ROLL in the builder).
	if s < 0.0 and l > 100.0 and l < 130.0:
		return -2.0 * 0.5 * (1.0 - cos(TAU * (l - 100.0) / 30.0))
	return 0.0
