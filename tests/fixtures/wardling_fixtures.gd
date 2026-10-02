class_name WardlingFixtures
extends RefCounted
## E8 test helpers: a slice-map ServerWorld with objectives, Wardlings and the
## Wardling AI attached, and scripted owners that walk a navmesh path or issue
## squad orders through InputCommand (the real server validation path).

const MAP_DEF := "res://assets/data/match/map_slice_lane.tres"
const RULES := "res://assets/data/wardlings/wardling_rules_slice.tres"
const PICKET := "res://assets/data/wardlings/wardling_picket.tres"


## Scripted hero that idles `wait_ticks`, then walks a navmesh path to `goal`
## (stopping within `stop_m`), optionally issuing one squad order at `order_tick`.
class Owner extends ScriptedInputSource:
	var server: ServerWorld
	var hero_id: int = 0
	var goal: Vector3 = Vector3.INF
	var stop_m: float = 6.0
	var wait_ticks: int = 0
	var order_tick: int = -1
	var order_cmd: int = 0
	var order_target: int = 0
	var order_point: Vector3 = Vector3.ZERO
	var arrived: bool = false
	var _path: PackedVector3Array = PackedVector3Array()
	var _i: int = 1

	func _init() -> void:
		super(CombatFixtures.idle_input())

	func sample(seq: int, out: InputCommand) -> void:
		super.sample(seq, out)
		var h := server.hero(hero_id)
		if h != null and goal != Vector3.INF and seq >= wait_ticks and not arrived:
			var pos := h.state.position
			if _path.is_empty():
				_path = NavigationServer3D.map_get_path(server.get_world_3d().navigation_map, pos, goal, true)
			if Vector2(goal.x - pos.x, goal.z - pos.z).length() <= stop_m:
				arrived = true
			else:
				while _i < _path.size() - 1 and Vector2(_path[_i].x - pos.x, _path[_i].z - pos.z).length() < 0.8:
					_i += 1
				if _i < _path.size():
					var to := _path[_i] - pos
					out.move = Vector2(0.0, 1.0)
					out.yaw = fposmod(atan2(-to.x, -to.z), TAU)
		if seq == order_tick:
			out.squad_cmd = order_cmd
			out.squad_target = order_target
			out.squad_point = order_point
		out.quantize()


static func map_def() -> MapDef:
	return load(MAP_DEF) as MapDef


static func rules() -> WardlingRulesDef:
	return (load(RULES) as WardlingRulesDef).duplicate() as WardlingRulesDef


## Builds the server under `parent` (own World3D) and returns [server, link, director].
static func slice_server(parent: Node, rules_: WardlingRulesDef, vanguard: bool) -> Array:
	var net := NetFixtures.net_config()
	var link := LoopbackLink.new(NetFixtures.profile(0, 0, 0.0))
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(vp)
	var server := ServerWorld.new()
	vp.add_child(server)
	var def := map_def()
	server.setup(net, load("res://assets/data/movement/movement_default.tres") as MovementDef, def.scene,
		link.create_endpoint(1), CombatFixtures.vesper(), load("res://assets/data/match/match_rules_slice.tres") as MatchRulesDef)
	server.setup_objectives(def)
	server.enable_wardlings(def, rules_, load(PICKET) as WardlingDef)
	server.wardlings.vanguard_enabled = vanguard
	var director := WardlingDirector.new()
	director.attach(server)
	return [server, link, director, vp]


## Waits until the server world's navmesh answers path queries.
static func await_nav(tree: SceneTree, server: ServerWorld) -> bool:
	var def := map_def()
	var a := def.hq(MapDef.TEAM_CONCORD).sanctum
	var b := def.hq(MapDef.TEAM_SYNDICATE).sanctum
	for i in 180:
		await tree.physics_frame
		if NavigationServer3D.map_get_path(server.get_world_3d().navigation_map, a, b, true).size() > 1:
			return true
	return false
