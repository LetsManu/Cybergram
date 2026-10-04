class_name StatBuffEffectDef
extends EffectDef
## W10-T1: timed hero-stat Modifier on the effect target (or the caster):
## Prism Ward Haste / Overcharge, Sable's Ambush, Slipstream. `stat` is a
## StatCatalog HERO_NAMES entry; the value and the duration come from skill
## params so the numbers live in the node modifiers. Op PCT = +fraction,
## MUL = multiplier (e.g. 1.15).

@export var stat: StringName = &"move_speed"
@export var op: Modifier.Op = Modifier.Op.PCT
@export var magnitude_param: StringName = &"extra"
@export var duration_param: StringName = &"secondary_duration"
@export var on_caster: bool = false


func apply(ctx: EffectContext) -> void:
	var t: Node3D = ctx.caster if on_caster else ctx.target
	var i := StatCatalog.hero_index(stat)
	if not (t is HeroBody) or i < 0:
		return
	var h := t as HeroBody
	if h.combat.dead or h.combat.team != ctx.team:
		return
	var src := Modifier.source(Modifier.SRC_PASSIVE, 0x900000 | (ctx.skill.slot << 8 if ctx.skill != null else 0) | (h.net_id & 0xFF))
	h.combat.stats.remove_by_source(src)
	h.combat.stats.add_modifier(Modifier.make(i, op, ctx.param(magnitude_param), src,
		ctx.tick + ctx.ticks(duration_param)))
