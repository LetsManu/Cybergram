class_name DebugUplinkSiegeSource
extends RefCounted
## DEBUG ONLY (launch arg --debug-uplink): the local hero stands still, aims at
## the enemy Uplink core and pulls the trigger every other tick. Evidence
## captures for E9 only; never wired for normal play (Pillar 2: no aim assistance).

## Aim height above the Uplink floor (the slice map's core).
const AIM_Y: float = 7.0

var client: ClientWorld


func _init(c: ClientWorld) -> void:
	client = c


func sample(seq: int, out: InputCommand) -> void:
	out.seq = seq
	out.move = Vector2.ZERO
	out.buttons = 0
	out.squad_cmd = InputCommand.SQUAD_NONE
	var body := client.body
	if body != null and client.map_def != null:
		var hq := client.map_def.hq(1 - client.own_team())
		if hq != null:
			var eye := body.state.position + Vector3(0.0, body.eye_height(), 0.0)
			var to := hq.uplink + Vector3(0.0, AIM_Y, 0.0) - eye
			out.yaw = fposmod(atan2(-to.x, -to.z), TAU)
			out.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			if seq > 30 and seq % 2 == 0:
				out.buttons |= InputCommand.BTN_FIRE
	out.quantize()
