class_name Armory
extends RefCounted
## Armory rules (weapons-and-mods.md §3.6.4, §4.7; wardlings-and-economy.md §7,
## §19): buy / upgrade in place / swap (auto-sell) / sell / undo, HQ zone only,
## while alive. Mount and squad effects are SRC_MOD Modifiers on the hero
## StatBlock (one source per catalog item), so removing a mount removes exactly
## its numbers. Mounts live on HeroProgress and persist through death.
##
## Example:
##   Armory.buy(progress, combat, catalog, catalog.index_of(&"ember_heart"), 1, rules)


static func source_for(index: int) -> int:
	return Modifier.source(Modifier.SRC_MOD, index)


## Buys item `index` of `cat` (`tier` 1..3; 0 = the next tier of a held line).
static func buy(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, index: int, tier: int,
		r: EconomyRulesDef) -> int:
	if c.dead:
		return HeroProgress.Result.DEAD
	if not p.at_armory:
		return HeroProgress.Result.NOT_AT_ARMORY
	var item := cat.at(index)
	if item == null:
		return HeroProgress.Result.UNKNOWN_ITEM
	if item.disabled:
		return HeroProgress.Result.DISABLED
	match item.kind:
		ArmoryItemDef.Kind.CONSUMABLE:
			if p.medpacks >= item.carry_limit:
				return HeroProgress.Result.LIMIT
			if p.lumen < item.price(1):
				return HeroProgress.Result.NO_FUNDS
			p.lumen -= item.price(1)
			p.medpacks += 1
			return HeroProgress.Result.OK
		ArmoryItemDef.Kind.SQUAD:
			if p.owned.has(item.id):
				return HeroProgress.Result.LIMIT
			if item.requires != &"" and not p.owned.has(item.requires):
				return HeroProgress.Result.REQUIRES
			if p.lumen < item.price(1):
				return HeroProgress.Result.NO_FUNDS
			p.lumen -= item.price(1)
			p.owned[item.id] = true
			for m in item.modifiers(1, source_for(index)):
				c.stats.add_modifier(m)
			return HeroProgress.Result.OK
	if item.kind == ArmoryItemDef.Kind.MOUNT and not item.fits(c.weapon.def if c.weapon != null else null):
		return HeroProgress.Result.WRONG_FAMILY
	var held := p.mount(item.socket)
	var same := held != null and held.item == item
	if tier <= 0:
		tier = held.tier + 1 if same else 1
	if tier > item.tiers():
		return HeroProgress.Result.MAXED
	var cost := item.price(tier)
	var credit := 0
	if same:
		if tier <= held.tier:
			return HeroProgress.Result.LIMIT
		cost = EconomyMath.upgrade_cost(item, tier, held.tier)
	elif held != null:
		credit = EconomyMath.sell_value(r, held.paid, held.paid_visit)  # swap auto-sells
	if p.lumen + credit < cost:
		return HeroProgress.Result.NO_FUNDS
	if held != null and not same:
		_remove(p, c, item.socket)
		p.lumen += credit
		held = null
	if held == null:
		held = HeroProgress.Mount.new()
		held.item = item
		held.index = index
		p.mounts[item.socket] = held
	p.lumen -= cost
	held.tier = tier
	held.paid += cost
	held.paid_visit += cost
	_apply(c, held)
	return HeroProgress.Result.OK


## Sells the mount in `socket` (ArmoryItemDef.Socket). Refund per §3.6.4 rule 4.
static func sell(p: HeroProgress, c: HeroCombat, socket: int, r: EconomyRulesDef) -> int:
	if c.dead:
		return HeroProgress.Result.DEAD
	if not p.at_armory:
		return HeroProgress.Result.NOT_AT_ARMORY
	var held := p.mount(socket)
	if held == null:
		return HeroProgress.Result.NOT_OWNED
	p.lumen += EconomyMath.sell_value(r, held.paid, held.paid_visit)
	_remove(p, c, socket)
	return HeroProgress.Result.OK


static func _apply(c: HeroCombat, m: HeroProgress.Mount) -> void:
	var src := source_for(m.index)
	c.stats.remove_by_source(src)
	for mod in m.item.modifiers(m.tier, src):
		c.stats.add_modifier(mod)
	if m.item.kind == ArmoryItemDef.Kind.AMMO:
		c.ammo_type = m.item.ammo_type


static func _remove(p: HeroProgress, c: HeroCombat, socket: int) -> void:
	var m := p.mount(socket)
	if m == null:
		return
	c.stats.remove_by_source(source_for(m.index))
	if m.item.kind == ArmoryItemDef.Kind.AMMO:
		c.ammo_type = DamageMath.AMMO_STANDARD
	p.mounts.erase(socket)
