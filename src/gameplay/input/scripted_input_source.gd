class_name ScriptedInputSource
extends RefCounted
## Deterministic input from a ScriptedInputDef, for dummy entities and tests.
## Same contract as PlayerInputSource: sample(seq, out). Bots (ADR-0005) will
## emit InputCommands the same way from src/ai.

var def: ScriptedInputDef


func _init(d: ScriptedInputDef) -> void:
	def = d


## Fills `out` for tick `seq` (already quantized).
func sample(seq: int, out: InputCommand) -> void:
	var seg := (seq / def.ticks_per_segment) % maxi(def.segments.size(), 1)
	out.seq = seq
	out.move = def.segments[seg] if not def.segments.is_empty() else Vector2.ZERO
	out.yaw = deg_to_rad(def.start_yaw_deg + def.yaw_deg_per_tick * seq)
	out.pitch = 0.0
	out.buttons = 0
	if def.sprint:
		out.buttons |= InputCommand.BTN_SPRINT
	if def.jump_interval_ticks > 0 and seq % def.jump_interval_ticks == 0:
		out.buttons |= InputCommand.BTN_JUMP
	if seg in def.crouch_segments:
		out.buttons |= InputCommand.BTN_CROUCH
	out.quantize()
