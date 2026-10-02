class_name DebugAutoAimSource
extends RefCounted
## DEBUG ONLY (launch arg --autofire): aims the local client at the chest of the
## nearest visible remote hero and pulls the trigger every other tick (so
## semi-auto weapons fire at their rate cap). Used for evidence captures; it is
## never wired for normal play (Pillar 2: no aim assistance).
## It leads moving targets by the interpolation delay: until lag compensation
## lands, the server judges shots against current poses, not what was on screen.

const CHEST_HEIGHT: float = 1.1

var client: ClientWorld
var _last_pos: Dictionary = {}  # net id -> position at the previous sample


func _init(c: ClientWorld) -> void:
	client = c


func sample(seq: int, out: InputCommand) -> void:
	out.seq = seq
	out.move = Vector2.ZERO
	out.buttons = 0
	out.squad_cmd = InputCommand.SQUAD_NONE
	var body := client.body
	if body != null:
		var eye := body.state.position + Vector3(0.0, body.eye_height(), 0.0)
		var best: HeroView = null
		var best_id := 0
		var best_d := INF
		var views := client.remote_views()
		for id in views:
			var v: HeroView = views[id]
			var d := v.position.distance_to(eye)
			if v.visible and d < best_d:
				best = v
				best_id = id
				best_d = d
		if best != null:
			var lead := Vector3.ZERO
			if _last_pos.has(best_id):
				var vel: Vector3 = best.position - _last_pos[best_id]
				lead = Vector3(vel.x, 0.0, vel.z) * (client.net.interp_delay_ticks + 1)
			var to := best.position + lead + Vector3(0.0, CHEST_HEIGHT, 0.0) - eye
			out.yaw = fposmod(atan2(-to.x, -to.z), TAU)
			out.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			if seq % 2 == 0:
				out.buttons |= InputCommand.BTN_FIRE
		for id in views:
			_last_pos[id] = views[id].position
	out.quantize()
