class_name ScriptedInputSource
extends RefCounted
## Deterministic input from a ScriptedInputDef, for dummy entities and tests.
## Same contract as PlayerInputSource: sample(seq, out). Bots (ADR-0005) will
## emit InputCommands the same way from src/ai.

var def: ScriptedInputDef
## Debug: ServerWorld respawns this source's hero at its own spawn point instead
## of its team's HQ (keeps test/evidence dummies near where they started).
var respawn_at_home: bool = false


func _init(d: ScriptedInputDef) -> void:
	def = d
	respawn_at_home = d.respawn_at_home


## Fills `out` for tick `seq` (already quantized).
func sample(seq: int, out: InputCommand) -> void:
	var seg := (seq / def.ticks_per_segment) % maxi(def.segments.size(), 1)
	out.seq = seq
	out.move = def.segments[seg] if not def.segments.is_empty() else Vector2.ZERO
	out.yaw = deg_to_rad(def.start_yaw_deg + def.yaw_deg_per_tick * seq)
	out.pitch = deg_to_rad(def.pitch_deg)
	out.buttons = 0
	if def.sprint:
		out.buttons |= InputCommand.BTN_SPRINT
	if def.jump_interval_ticks > 0 and seq % def.jump_interval_ticks == 0:
		out.buttons |= InputCommand.BTN_JUMP
	if seg in def.crouch_segments:
		out.buttons |= InputCommand.BTN_CROUCH
	if def.fire_period_ticks > 0 and seq % def.fire_period_ticks < def.fire_hold_ticks:
		out.buttons |= InputCommand.BTN_FIRE
	out.squad_cmd = InputCommand.SQUAD_NONE
	out.action = InputCommand.ACTION_NONE  # E13/E15 edge event
	out.action_arg = 0
	out.quantize()
