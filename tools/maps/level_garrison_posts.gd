extends SceneTree
## Moves each used Garrison post of Shardline Front (the first
## WardlingRulesDef.sentinels_per_hardpoint of HardpointDef.garrison_points)
## to the nearest spot where a Garrison socket lies level (PlacementKit
## support, same test as the CI placement gate), clear of the Forward Beacon
## pads and the Supply Cache, and writes the result into map_front.tres.
## Run after tools/maps/build_shardline_front.gd (whose formula puts some
## posts on pad kerbs):
##   godot --headless --path . -s res://tools/maps/level_garrison_posts.gd [-- --dry]

const MAP_DEF := "res://assets/data/match/map_front.tres"
const SOCKET_R := 0.62
const TOL := 0.06
const REACH := 2.5
const STEP := 0.25
## Keep this far (m, flat) from a beacon spot and from the cache centre.
const BEACON_CLEAR := 3.4
const CACHE_CLEAR := 1.8


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	var md := load(MAP_DEF) as MapDef
	var map := md.scene.instantiate() as Node3D
	root.add_child(map)
	await physics_frame
	await physics_frame
	var space := map.get_world_3d().direct_space_state
	var per := WardlingRulesDef.new().sentinels_per_hardpoint
	var moved := 0
	for lane: LaneDef in md.lanes:
		for d: HardpointDef in lane.hardpoints:
			var avoid: Array = []
			for sp: Array in ForwardBeaconView.spots(md, d):
				avoid.append([sp[1], BEACON_CLEAR])
			if d.supply_cache.is_finite():
				avoid.append([d.supply_cache, CACHE_CLEAR])
			var pts := d.garrison_points
			for i in mini(pts.size(), per):
				var p := _level(space, pts[i], d, avoid)
				if p.distance_to(pts[i]) > 0.01:
					print("%s post %d: %s -> %s" % [d.id, i, pts[i], p])
					pts[i] = p
					moved += 1
			d.garrison_points = pts
	print("moved %d posts" % moved)
	if not dry and moved > 0:
		var err := ResourceSaver.save(md, MAP_DEF)
		print("saved %s (%s)" % [MAP_DEF, error_string(err)])
	quit()


func _level(space: PhysicsDirectSpaceState3D, post: Vector3, d: HardpointDef, avoid: Array) -> Vector3:
	var inward := Vector3(d.position.x - post.x, 0.0, d.position.z - post.z)
	inward = inward.normalized() if inward.length_squared() > 1e-6 else Vector3.FORWARD
	var side := inward.cross(Vector3.UP)
	# mirror-stable order: rings outward; on each ring inward first, then both
	# sides by the same offset (the side sign follows the post's side of the zone)
	var sgn := 1.0 if side.dot(post - d.position) >= 0.0 else -1.0
	var r := 0.0
	while r <= REACH + 1e-3:
		var n := 1 if r == 0.0 else 16
		for k in n:
			var a := 0.0 if k == 0 else PI * ceilf(k / 2.0) / 8.0 * (1.0 if k % 2 == 1 else -1.0)
			var dir := inward * cos(a) + side * sgn * sin(a)
			var c := post + dir * r
			if _ok(space, c, d, avoid):
				var g := PlacementKit.ground(space, c + Vector3.UP, 0.5, 3.0)
				return Vector3(snappedf(c.x, 0.05), snappedf((g.pos as Vector3).y, 0.01), snappedf(c.z, 0.05))
		r += STEP
	push_warning("%s: no level spot near %s" % [d.id, post])
	return post


func _ok(space: PhysicsDirectSpaceState3D, c: Vector3, d: HardpointDef, avoid: Array) -> bool:
	if Vector2(c.x - d.position.x, c.z - d.position.z).length() > d.zone_radius - 1.0:
		return false
	for a: Array in avoid:
		if Vector2(c.x - (a[0] as Vector3).x, c.z - (a[0] as Vector3).z).length() < float(a[1]):
			return false
	var g := PlacementKit.ground(space, c + Vector3.UP, 0.5, 3.0)
	if g.is_empty():
		return false
	var xf := Transform3D(Basis(), g.pos)
	var pts := ForwardBeaconView.pad_foot(xf, SOCKET_R)
	pts.append_array(ForwardBeaconView.pad_foot(xf, SOCKET_R, PI * 0.25))
	pts.append(xf.origin)
	return PlacementKit.support_at(space, pts, TOL) >= 1.0
