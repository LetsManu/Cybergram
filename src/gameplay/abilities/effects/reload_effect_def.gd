class_name ReloadEffectDef
extends EffectDef
## W10-T1: instantly refills the caster's magazine from reserve (Stim's
## Overdrive Fork, heroes.md §4.4: instant full reload on cast).


func apply(ctx: EffectContext) -> void:
	var w := ctx.caster.combat.weapon if ctx.caster != null else null
	if w == null or not (w.feed is MagazineFeed):
		return
	var f := w.feed as MagazineFeed
	var add := mini(f.reserve, f.def.magazine - f.rounds)
	if add > 0:
		f.rounds += add
		f.reserve -= add
	f.reload_end_tick = -1
