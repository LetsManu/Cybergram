class_name ItemShop
extends RefCounted
## Armory v2 purchase rules on the server (items-and-armory.md §3.6, §4.1,
## §4.2, §4.4). Recipe items, the Chamber, squad upgrades and Med-Packs. Every
## request is checked first and applied all at once: a refused request changes
## nothing (§3.6 rule 10). Each change is logged per visit so it can be
## undone for 100% while the hero stays on the pad (rule 8).
##
## Stats: every active item adds its modifiers under one source per catalog
## index (Armory.source_for); the one-copy rule (§3.2) means an index is
## active at most once, so sources never collide.

## Buys catalog item `index`.
static func buy(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, index: int, r: EconomyRulesDef) -> int:
	var gate := _gate(p, c)
	if gate != HeroProgress.Result.OK:
		return gate
	var it := cat.at(index)
	if it == null:
		return HeroProgress.Result.UNKNOWN_ITEM
	if it.disabled:
		return HeroProgress.Result.DISABLED
	match it.kind:
		ArmoryItemDef.Kind.CONSUMABLE, ArmoryItemDef.Kind.SQUAD:
			return _buy_row(p, c, cat, index)
		ArmoryItemDef.Kind.AMMO:
			return _buy_chamber(p, c, cat, index, ItemInventory.LOC_AMMO, r)
		ArmoryItemDef.Kind.AMMO_MOD:
			return _buy_chamber(p, c, cat, index, ItemInventory.LOC_MOD, r)
	if it.tier == ArmoryItemDef.Tier.NONE:
		return HeroProgress.Result.INVALID  # a v1 tiered line: not sold by the v2 shop
	return _buy_recipe(p, c, cat, index, r)


## Lumen a buy of `index` would cost now (0 = refused or free); for bots, the
## sim and tests. The shop UI computes the same with RecipeMath on the client.
static func price_of(p: HeroProgress, cat: ArmoryCatalogDef, index: int) -> int:
	var it := cat.at(index)
	if it == null:
		return 0
	if it.tier == ArmoryItemDef.Tier.NONE:
		return it.price(1)
	return int(RecipeMath.resolve(cat, p.inv.pool(), index)["cost"])


## Sells the item at `loc` (ItemInventory.LOC_*) for SellValue (§4.4).
## Selling the Ammo Type also sells the Ammo Mod (weapons-and-mods.md §3.6.4 rule 7).
static func sell(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, loc: int, r: EconomyRulesDef) -> int:
	var gate := _gate(p, c)
	if gate != HeroProgress.Result.OK:
		return gate
	var inv := p.inv
	var e := inv.at(loc) if loc != ItemInventory.LOC_ROW else null
	if e == null:
		return HeroProgress.Result.NOT_OWNED
	var sold: Array = []
	var value := 0
	if loc == ItemInventory.LOC_AMMO and inv.at(ItemInventory.LOC_MOD) != null:
		var m := inv.at(ItemInventory.LOC_MOD)
		value += RecipeMath.sell_value(cat, m.index, r)
		sold.append([inv.remove(m), m])
	value += RecipeMath.sell_value(cat, e.index, r)
	sold.append([inv.remove(e), e])
	p.lumen += value
	p.spent_lumen -= value
	inv.txns.append({"op": &"sell", "index": e.index, "lumen": -value, "placed": null, "at": -1,
		"taken": [], "sold": sold})
	apply_stats(p, c, cat)
	return HeroProgress.Result.OK


## Undoes the purchase that placed the item now at `loc` (§3.6 rule 8): full
## refund, used-up and swapped-out parts come back. Refused with UNDO_BLOCKED
## while a later purchase depends on it.
static func undo_at(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, loc: int, r: EconomyRulesDef) -> int:
	var gate := _gate(p, c)
	if gate != HeroProgress.Result.OK:
		return gate
	var k := p.inv.txn_for(loc)
	if k < 0:
		return HeroProgress.Result.NOT_OWNED
	if p.inv.is_blocked(k):
		return HeroProgress.Result.UNDO_BLOCKED
	return _revert(p, c, cat, k, r)


## Undoes the last squad upgrade or Med-Pack of catalog item `index` bought this visit.
static func undo_row(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, index: int, r: EconomyRulesDef) -> int:
	var gate := _gate(p, c)
	if gate != HeroProgress.Result.OK:
		return gate
	for k in range(p.inv.txns.size() - 1, -1, -1):
		var t: Dictionary = p.inv.txns[k]
		if t["op"] == &"row" and int(t["index"]) == index:
			return _revert(p, c, cat, k, r)
	return HeroProgress.Result.NOT_OWNED


## "Undo last": reverts the most recent transaction of this visit.
static func undo_last(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, r: EconomyRulesDef) -> int:
	var gate := _gate(p, c)
	if gate != HeroProgress.Result.OK:
		return gate
	if p.inv.txns.is_empty():
		return HeroProgress.Result.NOT_OWNED
	return _revert(p, c, cat, p.inv.txns.size() - 1, r)


## Re-applies every active item's modifiers, the Chamber and max HP.
static func apply_stats(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef) -> void:
	for idx in p.inv_applied:
		c.stats.remove_by_source(Armory.source_for(idx))
	p.inv_applied.clear()
	var mana := c.weapon == null or c.weapon.def.feed_kind == WeaponDef.FeedKind.MANA
	for idx in p.inv.active_indices():
		var it := cat.at(idx)
		if it == null or it.tier == ArmoryItemDef.Tier.NONE:
			continue
		for m in it.v2_modifiers(mana, Armory.source_for(idx)):
			c.stats.add_modifier(m)
		p.inv_applied.append(idx)
	var ammo := cat.at(p.inv.index_at(ItemInventory.LOC_AMMO))
	c.ammo_type = ammo.ammo_type if ammo != null else DamageMath.AMMO_STANDARD
	var mod := cat.at(p.inv.index_at(ItemInventory.LOC_MOD))
	c.ammo_mod = mod.ammo_mod if mod != null else 0
	c.sync_max_hp()


# --- internals ----------------------------------------------------------------

static func _gate(p: HeroProgress, c: HeroCombat) -> int:
	if c.dead:
		return HeroProgress.Result.DEAD
	if not p.at_armory:
		return HeroProgress.Result.NOT_AT_ARMORY
	return HeroProgress.Result.OK


static func _buy_recipe(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, index: int, r: EconomyRulesDef) -> int:
	var inv := p.inv
	var it := cat.at(index)
	if it.tier != ArmoryItemDef.Tier.COMPONENT and inv.owns(index):
		return HeroProgress.Result.ALREADY_OWNED
	if it.tier == ArmoryItemDef.Tier.SIGNATURE and inv.signature_count(cat) >= r.signature_limit:
		return HeroProgress.Result.SIGNATURE_LIMIT
	var res := RecipeMath.resolve(cat, inv.pool(), index)
	var cost: int = res["cost"]
	var take: Array = res["take"]
	var to_slot := it.uses_open_slot()
	var swap: ItemInventory.Entry = null
	var credit := 0
	if not to_slot:
		var held := inv.at(it.socket)
		if held != null and not take.any(func(t: Dictionary) -> bool: return t["entry"] == held):
			swap = held
			credit = RecipeMath.sell_value(cat, held.index, r)
	var consumed_open := 0
	for t in take:
		if int(t["loc"]) >= ItemInventory.LOC_SLOT:
			consumed_open += 1
	if inv.slots.size() - consumed_open + (1 if to_slot else 0) > r.open_slots:
		return HeroProgress.Result.INVENTORY_FULL
	if p.lumen + credit < cost:
		return HeroProgress.Result.NO_FUNDS
	var taken: Array = []
	for t in take:
		var e: ItemInventory.Entry = t["entry"]
		taken.append([inv.remove(e), e])
	var sold: Array = []
	if swap != null:
		sold.append([inv.remove(swap), swap])
	var placed := inv.new_entry(index)
	var dest := ItemInventory.LOC_SLOT + inv.slots.size() if to_slot else it.socket
	inv.place(placed, dest)
	p.lumen += credit - cost
	p.spent_lumen += cost - credit
	inv.txns.append({"op": &"buy", "index": index, "lumen": cost - credit, "placed": placed, "at": dest,
		"taken": taken, "sold": sold})
	apply_stats(p, c, cat)
	return HeroProgress.Result.OK


static func _buy_chamber(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, index: int, loc: int,
		r: EconomyRulesDef) -> int:
	var inv := p.inv
	var it := cat.at(index)
	var held := inv.at(loc)
	if held != null and held.index == index:
		return HeroProgress.Result.ALREADY_OWNED
	var new_type := it.ammo_type
	if loc == ItemInventory.LOC_MOD:
		var ammo := cat.at(inv.index_at(ItemInventory.LOC_AMMO))
		if ammo == null:
			return HeroProgress.Result.REQUIRES  # an Ammo Mod needs an Ammo Type
		if not _mod_fits(it, ammo.ammo_type):
			return HeroProgress.Result.INCOMPATIBLE
	var swaps: Array[ItemInventory.Entry] = []
	if held != null:
		swaps.append(held)
	if loc == ItemInventory.LOC_AMMO:
		var mod_e := inv.at(ItemInventory.LOC_MOD)
		if mod_e != null and not _mod_fits(cat.at(mod_e.index), new_type):
			swaps.append(mod_e)  # rule 7: an incompatible Mod is sold with the swap
	var credit := 0
	for e in swaps:
		credit += RecipeMath.sell_value(cat, e.index, r)
	var cost := it.price(1)
	if p.lumen + credit < cost:
		return HeroProgress.Result.NO_FUNDS
	var sold: Array = []
	for e in swaps:
		sold.append([inv.remove(e), e])
	var placed := inv.new_entry(index)
	inv.place(placed, loc)
	p.lumen += credit - cost
	p.spent_lumen += cost - credit
	inv.txns.append({"op": &"buy", "index": index, "lumen": cost - credit, "placed": placed, "at": loc,
		"taken": [], "sold": sold})
	apply_stats(p, c, cat)
	return HeroProgress.Result.OK


static func _mod_fits(mod: ArmoryItemDef, ammo_type: int) -> bool:
	return mod == null or mod.fits_ammo.is_empty() or mod.fits_ammo.has(ammo_type)


## Squad upgrades and Med-Packs (v1 rules, own row, logged for undo).
static func _buy_row(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, index: int) -> int:
	var it := cat.at(index)
	var price := it.price(1)
	if it.kind == ArmoryItemDef.Kind.CONSUMABLE:
		if p.medpacks >= it.carry_limit:
			return HeroProgress.Result.LIMIT
		if p.lumen < price:
			return HeroProgress.Result.NO_FUNDS
		p.medpacks += 1
	else:
		if p.owned.has(it.id):
			return HeroProgress.Result.LIMIT
		if it.requires != &"" and not p.owned.has(it.requires):
			return HeroProgress.Result.REQUIRES
		if p.lumen < price:
			return HeroProgress.Result.NO_FUNDS
		p.owned[it.id] = true
		for m in it.modifiers(1, Armory.source_for(index)):
			c.stats.add_modifier(m)
	p.lumen -= price
	p.spent_lumen += price
	p._visit_add(it.id, 1)
	p.inv.txns.append({"op": &"row", "index": index, "lumen": price, "placed": null, "at": ItemInventory.LOC_ROW,
		"taken": [], "sold": []})
	return HeroProgress.Result.OK


## Reverts transaction `k` of the visit log (checked by the callers).
static func _revert(p: HeroProgress, c: HeroCombat, cat: ArmoryCatalogDef, k: int, r: EconomyRulesDef) -> int:
	var inv := p.inv
	var t: Dictionary = inv.txns[k]
	var refund: int = t["lumen"]
	if refund < 0 and p.lumen < -refund:
		return HeroProgress.Result.NO_FUNDS  # undoing a sale gives the Lumen back
	if t["op"] == &"row":
		var it := cat.at(int(t["index"]))
		if it.kind == ArmoryItemDef.Kind.CONSUMABLE:
			if p.medpacks <= 0:
				return HeroProgress.Result.NOT_OWNED  # already used
			p.medpacks -= 1
		else:
			for other in cat.items:
				if other != null and other.requires == it.id and p.owned.has(other.id):
					return HeroProgress.Result.REQUIRES  # undo the upgrade built on it first
			p.owned.erase(it.id)
			c.stats.remove_by_source(Armory.source_for(int(t["index"])))
		p._visit_add(it.id, -1)
	else:
		var restore: Array = []
		restore.append_array(t["taken"])
		restore.append_array(t["sold"])
		# Restored parts go back where they were: refuse if a socket is taken or
		# the open slots would overflow.
		var placed: ItemInventory.Entry = t["placed"]
		var slots_after := inv.slots.size() - (1 if placed != null and inv.loc_of(placed) >= ItemInventory.LOC_SLOT else 0)
		for pair in restore:
			var loc: int = pair[0]
			if loc >= ItemInventory.LOC_SLOT:
				slots_after += 1
			elif inv.at(loc) != null and (placed == null or inv.at(loc) != placed):
				return HeroProgress.Result.UNDO_BLOCKED
		if slots_after > r.open_slots:
			return HeroProgress.Result.UNDO_BLOCKED
		if placed != null:
			inv.remove(placed)
		# Undo removals in reverse order so slot positions come back exactly.
		for i in range(t["sold"].size() - 1, -1, -1):
			var pair: Array = t["sold"][i]
			inv.place(pair[1], pair[0])
		for i in range(t["taken"].size() - 1, -1, -1):
			var pair: Array = t["taken"][i]
			inv.place(pair[1], pair[0])
	p.lumen += refund
	p.spent_lumen -= refund
	inv.txns.remove_at(k)
	apply_stats(p, c, cat)
	return HeroProgress.Result.OK
