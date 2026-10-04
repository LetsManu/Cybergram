class_name ForkGateEffectDef
extends EffectDef
## W10-T1 (heroes.md §2 / §3.5): runs `effects` only when the casting skill has
## learned the matching tree node, otherwise `else_effects`. Lets a Fork or
## Mastery change *how* an existing skill plays at any hook of its effect
## chain (on_hit, on_detonate, on_land...) without adding a button or a code
## path: the skill's .tres authors the gate, the numbers stay in node modifiers.

enum Fork { ANY, A, B }

## Which Fork must be learned (ANY = the gate does not look at the Fork).
@export var fork: Fork = Fork.ANY
## Also requires the Mastery node.
@export var needs_mastery: bool = false
@export var effects: Array[Resource] = []
@export var else_effects: Array[Resource] = []


## True when the skill in `ctx` satisfies the gate.
func is_open(ctx: EffectContext) -> bool:
	var s := ctx.skill
	if s == null:
		return false
	if fork != Fork.ANY and s.fork() != int(fork):
		return false
	if needs_mastery and not s.has_mastery():
		return false
	return fork != Fork.ANY or needs_mastery or s.fork() != 0


func apply(ctx: EffectContext) -> void:
	ctx.run(effects if is_open(ctx) else else_effects)
