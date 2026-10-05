extends GdUnitTestSuite
## W18-GEO: the shipped controller (HeroBody + HeroMotor, the same code the
## server and client prediction run) walks the living map's level changes by
## scripted input: the market's sunken street, a market shop and its back door
## into the jungle, the bridge guardhouse and the service walkway beneath the
## span, the dock warehouse and the raised quay, the plaza bridge and the
## jungle's rooftop route. Each route chains navmesh paths through waypoints
## (all nav layers, as bots use) and must be walked without falling or getting
## stuck. A replay of the same inputs on a second body ends in the same place
## (determinism: server and prediction stay in sync on stairs and slopes).

const DEF_PATH := "res://assets/data/match/map_front.tres"
const MOVEMENT_PATH := "res://assets/data/movement/movement_default.tres"
const TICK_HZ := 30
const LAYERS := 1 | MapDef.JUNGLE_NAV_LAYER

## [name, waypoints (x, L, y) in GDD lane coordinates, min y the route must dip
## to (NAN = no check), max y it must climb to (NAN = no check)].
const ROUTES := [
	["market_street", [Vector3(0, 90, 0), Vector3(0, 116, -3.5), Vector3(4, 150, 0)], -3.0, NAN],
	["market_shop_back_door", [Vector3(4, 92, 0), Vector3(11, 113, 2.5), Vector3(16.2, 115, 2.5), Vector3(20.7, 113, 2.5),
		Vector3(20, 123, 2.5), Vector3(32.5, 125, 0), Vector3(24, 135.5, 0)], NAN, 2.3],
	["guardhouse_walkway", [Vector3(-82, 136, 0), Vector3(-99, 137.5, 0), Vector3(-99, 146.5, 0), Vector3(-99, 156, 0),
		Vector3(-93, 178, -4.5), Vector3(-86.5, 176, -4.5), Vector3(-80, 205, 0)], -4.2, NAN],
	["warehouse_quay", [Vector3(80, 95, 0), Vector3(91, 109, 0), Vector3(97, 109, 0), Vector3(95, 119, 0),
		Vector3(99, 140, 2.5), Vector3(80, 156, 0)], NAN, 2.3],
	["plaza_bridge", [Vector3(-6, 203, 0), Vector3(-30.5, 210, 4.5), Vector3(-6, 217, 0)], NAN, 4.2],
	["jungle_rooftops", [Vector3(15, 76.5, 0), Vector3(24, 89, 4.5), Vector3(55, 89, 4.5), Vector3(54.5, 108, 1.5),
		Vector3(44.5, 114.5, 0), Vector3(60, 134, 4.5), Vector3(42, 123.5, 4.5)], NAN, 4.2],
]


static func _w(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


func test_hero_walks_every_level_change() -> void:
	var def := load(DEF_PATH) as MapDef
	var movement := load(MOVEMENT_PATH) as MovementDef
	var scene: Node3D = auto_free(def.scene.instantiate())
	add_child(scene)
	var nav_map := (scene.get_node("NavRegion") as NavigationRegion3D).get_navigation_map()
	for i in 180:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_path(nav_map, def.hq(0).sanctum, def.hq(1).sanctum, true).size() > 1:
			break
	var bad: Array = []
	for r in ROUTES:
		var res := await _walk(scene, nav_map, movement, r[1], [])
		var cmds: Array = res[3]
		print("walk %s: ok %s, %.1f s, y %.2f .. %.2f" % [r[0], res[0], cmds.size() / float(TICK_HZ), res[1], res[2]])
		if not res[0]:
			bad.append("%s: stuck/fell" % r[0])
		if not is_nan(r[2]) and res[1] > r[2]:
			bad.append("%s: never went down (%.2f)" % [r[0], res[1]])
		if not is_nan(r[3]) and res[2] < r[3]:
			bad.append("%s: never went up (%.2f)" % [r[0], res[2]])
		# Replay the recorded inputs on a fresh body: same end position.
		var rep := await _walk(scene, nav_map, movement, r[1], cmds)
		if (rep[4] as Vector3).distance_to(res[4]) > 0.01:
			bad.append("%s: replay diverged %.3f m" % [r[0], (rep[4] as Vector3).distance_to(res[4])])
	assert_array(bad).is_empty()


## Walks the waypoint chain (or replays `replay` commands). Returns
## [ok, min y, max y, commands, end position].
func _walk(scene: Node3D, nav_map: RID, movement: MovementDef, wps: Array, replay: Array) -> Array:
	var start := _w(wps[0])
	var hero := HeroBody.new()
	hero.setup(movement, start + Vector3(0, 0.05, 0), false)
	scene.add_child(hero)
	hero.place()
	await get_tree().physics_frame
	var dt := 1.0 / TICK_HZ
	var cmds: Array = []
	var min_y := INF
	var max_y := -INF
	var ok := true
	if not replay.is_empty():
		for c: InputCommand in replay:
			hero.step(c, dt)
	else:
		for k in range(1, wps.size()):
			var goal := _w(wps[k])
			var path := NavigationServer3D.map_get_path(nav_map, hero.global_position, goal, true, LAYERS)
			if path.size() < 2:
				ok = false
				break
			var wp := 1
			var ticks := 0
			var budget := int((_len(path) / 4.0 + 3.0) * TICK_HZ)
			while ticks < budget:
				var pos := hero.global_position
				if Vector2(pos.x - goal.x, pos.z - goal.z).length() < 0.9 and absf(pos.y - goal.y) < 1.2:
					break
				var to := path[wp] - pos
				to.y = 0.0
				while to.length() < 0.6 and wp < path.size() - 1:
					wp += 1
					to = path[wp] - pos
					to.y = 0.0
				var cmd := InputCommand.new()
				cmd.seq = cmds.size()
				cmd.move = Vector2(0.0, 1.0)
				cmd.yaw = atan2(-to.x, -to.z)
				cmd.quantize()
				hero.step(cmd, dt)
				cmds.append(cmd)
				min_y = minf(min_y, hero.global_position.y)
				max_y = maxf(max_y, hero.global_position.y)
				ticks += 1
			if ticks >= budget or hero.global_position.y < -8.0:
				print("  stuck before waypoint %d %s at %s (lane coords x %.1f L %.1f y %.2f)" % [k, wps[k], hero.global_position,
					hero.global_position.x, -hero.global_position.z, hero.global_position.y])
				ok = false
				break
	var end := hero.global_position
	scene.remove_child(hero)
	hero.free()
	return [ok, min_y, max_y, cmds, end]


static func _len(p: PackedVector3Array) -> float:
	var l := 0.0
	for i in p.size() - 1:
		l += p[i].distance_to(p[i + 1])
	return l
