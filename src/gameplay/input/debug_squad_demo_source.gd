class_name DebugSquadDemoSource
extends RefCounted
## DEBUG ONLY (launch arg --debug-squad-demo): after a short wait for the squad
## to mint, the local hero backs down the lane along a navmesh path while
## facing back the way it came, so the Follow squad (which forms up behind the
## direction of travel) is in the first-person view. Evidence captures only.

const WAIT_TICKS: int = 60
const BACK_SPEED: float = 0.55
const PITCH: float = -0.12

var client: ClientWorld
var _path: PackedVector3Array = PackedVector3Array()
var _i: int = 1
var _yaw: float = PI


func _init(c: ClientWorld) -> void:
	client = c


func sample(seq: int, out: InputCommand) -> void:
	out.seq = seq
	out.buttons = 0
	out.squad_cmd = InputCommand.SQUAD_NONE
	out.move = Vector2.ZERO
	out.pitch = PITCH
	var body := client.body
	if body != null and seq >= WAIT_TICKS:
		var pos := body.state.position
		if _path.is_empty() and client.map_def != null:
			var goal := client.map_def.lanes[0].hardpoints[0].position
			_path = NavigationServer3D.map_get_path(client.get_world_3d().navigation_map, pos, goal, true)
		while _i < _path.size() - 1 and Vector2(_path[_i].x - pos.x, _path[_i].z - pos.z).length() < 1.0:
			_i += 1
		if _i < _path.size():
			var d := Vector3(_path[_i].x - pos.x, 0.0, _path[_i].z - pos.z)
			if d.length() > 0.5:
				d = d.normalized()
				_yaw = lerp_angle(_yaw, atan2(d.x, d.z), 0.1)  # face away from the travel direction
				var local := Basis(Vector3.UP, _yaw).inverse() * d
				out.move = Vector2(local.x, -local.z) * BACK_SPEED
	out.yaw = fposmod(_yaw, TAU)
	out.quantize()
