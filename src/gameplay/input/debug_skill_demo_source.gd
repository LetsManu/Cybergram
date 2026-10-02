class_name DebugSkillDemoSource
extends DebugSquadDemoSource
## DEBUG ONLY (launch arg --debug-skill-demo; E10 evidence captures). Presses
## the hero's skills on a fixed schedule through the normal input path
## (InputCommand.BTN_SKILL*, server-validated):
## - Brannoc: stands facing down the lane; Fortify (C), Ram Charge (E), then
##   Aegis Wall (Q) ahead, so the bar shows cooldowns and an active wall.
## - Vesper (and others): backs down the lane facing her squad like
##   --debug-squad-demo, places Rally Beacon (E) on the squad, then Rewrite (G;
##   needs --grant-ult below level 6) to make the squad Elite.

const BRANNOC_PLAN := {20: InputCommand.BTN_SKILL3, 36: InputCommand.BTN_SKILL2, 80: InputCommand.BTN_SKILL1}
const VESPER_PLAN := {150: InputCommand.BTN_SKILL2, 175: InputCommand.BTN_SKILL4}
const WALL_PITCH: float = -0.16

var _brannoc: bool = false
var _face: float = INF


func sample(seq: int, out: InputCommand) -> void:
	_brannoc = client.hero_def != null and client.hero_def.id == &"hero_brannoc"
	if _brannoc:
		out.seq = seq
		out.buttons = 0
		out.squad_cmd = InputCommand.SQUAD_NONE
		out.move = Vector2.ZERO
		if _face == INF and client.body != null and client.map_def != null:
			var to := client.map_def.lanes[0].hardpoints[0].position - client.body.state.position
			_face = fposmod(atan2(-to.x, -to.z), TAU)
		out.yaw = _face if _face != INF else 0.0
		out.pitch = WALL_PITCH if seq >= 70 else 0.0
		out.buttons |= BRANNOC_PLAN.get(seq, 0)
		out.quantize()
		return
	super.sample(seq, out)
	out.buttons |= VESPER_PLAN.get(seq, 0)
	out.quantize()
