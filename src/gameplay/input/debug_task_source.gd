class_name DebugTaskSource
extends RefCounted
## DEBUG ONLY (launch arg --debug-task breach): the local hero stands still, aims
## at a fixed world point (the Ward Generator core) and pulls the trigger every
## other tick. E14 evidence captures only; never wired for normal play (Pillar 2:
## no aim assistance).

var client: ClientWorld
var target: Vector3 = Vector3.ZERO
## Hold Interact instead of firing (plant evidence).
var interact: bool = false


func _init(c: ClientWorld, point: Vector3) -> void:
	client = c
	target = point


func sample(seq: int, out: InputCommand) -> void:
	out.seq = seq
	out.move = Vector2.ZERO
	out.buttons = 0
	out.squad_cmd = InputCommand.SQUAD_NONE
	var body := client.body
	if body != null:
		var eye := body.state.position + Vector3(0.0, body.eye_height(), 0.0)
		var to := target - eye
		out.yaw = fposmod(atan2(-to.x, -to.z), TAU)
		out.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		if interact:
			out.buttons |= InputCommand.BTN_INTERACT
		elif seq > 30 and seq % 2 == 0:
			out.buttons |= InputCommand.BTN_FIRE
	out.quantize()
