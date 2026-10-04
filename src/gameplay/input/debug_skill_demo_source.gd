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
## W9-H2: scripted plans for the gadget heroes: tick -> buttons; AIM tick ranges
## -> [yaw offset (rad), pitch]. They stand facing the lane like Brannoc.
const JUNIPER_PLAN := {10: InputCommand.BTN_SKILL3, 25: InputCommand.BTN_SKILL1, 40: InputCommand.BTN_SKILL2,
	55: InputCommand.BTN_SKILL2, 80: InputCommand.BTN_SKILL4}
const HEX_PLAN := {20: InputCommand.BTN_SKILL1, 40: InputCommand.BTN_SKILL2, 70: InputCommand.BTN_SKILL4}

var _brannoc: bool = false
var _face: float = INF


func sample(seq: int, out: InputCommand) -> void:
	_brannoc = client.hero_def != null and client.hero_def.id == &"hero_brannoc"
	var gadget_hero := client.hero_def != null and client.hero_def.id in [&"hero_juniper_quill", &"hero_hex"]
	if _brannoc or gadget_hero:
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
		if gadget_hero:
			var juniper := client.hero_def.id == &"hero_juniper_quill"
			out.buttons = (JUNIPER_PLAN if juniper else HEX_PLAN).get(seq, 0)
			out.pitch = -0.2 if seq < 100 else -0.1
			if juniper:  # Tripwire anchors A (left) and B (right) a few metres apart
				out.yaw += 0.4 if seq >= 36 and seq < 50 else (-0.4 if seq >= 50 and seq < 70 else 0.0)
		out.quantize()
		return
	super.sample(seq, out)
	out.buttons |= VESPER_PLAN.get(seq, 0)
	out.quantize()
