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
## Wave 9: the new kits stand and face the lane; skill buttons on a schedule
## (tick -> button), chosen so the last frames show each effect.
const PLANS := {
	&"hero_ryker_vance": {10: InputCommand.BTN_SKILL1, 20: InputCommand.BTN_SKILL2, 32: InputCommand.BTN_SKILL4,
		44: InputCommand.BTN_SKILL3},
	&"hero_sable": {10: InputCommand.BTN_SKILL3, 40: InputCommand.BTN_SKILL2, 60: InputCommand.BTN_SKILL4,
		90: InputCommand.BTN_SKILL1},
	&"hero_liora_vale": {10: InputCommand.BTN_SKILL1, 20: InputCommand.BTN_SKILL2, 30: InputCommand.BTN_SKILL3,
		40: InputCommand.BTN_SKILL4},
}
const PLAN_PITCH: float = 0.12
const WALL_PITCH: float = -0.16

var _brannoc: bool = false
var _plan: Dictionary = {}
var _face: float = INF


func sample(seq: int, out: InputCommand) -> void:
	_brannoc = client.hero_def != null and client.hero_def.id == &"hero_brannoc"
	_plan = PLANS.get(client.hero_def.id, {}) if client.hero_def != null else {}
	if not _plan.is_empty():
		out.seq = seq
		out.buttons = 0
		out.squad_cmd = InputCommand.SQUAD_NONE
		out.move = Vector2.ZERO
		if _face == INF and client.body != null and client.map_def != null:
			var to2 := client.map_def.lanes[0].hardpoints[0].position - client.body.state.position
			_face = fposmod(atan2(-to2.x, -to2.z), TAU)
		out.yaw = _face if _face != INF else 0.0
		out.pitch = PLAN_PITCH
		out.buttons |= _plan.get(seq, 0)
		out.quantize()
		return
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
