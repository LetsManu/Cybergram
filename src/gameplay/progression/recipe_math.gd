class_name RecipeMath
extends RefCounted
## Armory v2 recipe prices (items-and-armory.md §4.1). Shared by the server
## (ItemShop), the shop UI and BuildAdvisor, so all three agree on what a buy
## costs and which owned parts it uses.
##
## An owned pool is an Array of Dictionaries {index: int, loc: int, key}:
## `loc` is ItemInventory.LOC_* (a socket, the Chamber or an open slot) and
## `key` is unique per owned instance (server: serial; client: slot position).

## Total(X) = combine(X) + Σ Total(part); a component's Total is its price.
## A recipe deeper than this is a data cycle (ArmoryValidator reports it);
## the recursion stops instead of overflowing the stack.
const MAX_DEPTH := 8


static func total(cat: ArmoryCatalogDef, index: int, depth: int = 0) -> int:
	var it := cat.at(index)
	if it == null or depth > MAX_DEPTH:
		return 0
	if it.tier == ArmoryItemDef.Tier.NONE or it.tier == ArmoryItemDef.Tier.COMPONENT or it.recipe.is_empty():
		return it.price(1)
	var t := it.combine_cost
	for part in it.recipe:
		t += total(cat, cat.index_of(StringName(part)), depth + 1)
	return t


## RemainingCost(X) and the owned instances it uses: {cost: int, take: Array}
## (`take` holds pool entries). Matching (§4.1): a part is matched to an
## owned instance before its own parts are bought (deepest first); the target
## socket first, then open slots, later copies (spares) before the first
## (active) copy; each instance at most once. Buying a component never uses
## an owned copy (it adds one).
static func resolve(cat: ArmoryCatalogDef, pool: Array, index: int) -> Dictionary:
	var it := cat.at(index)
	if it == null:
		return {"cost": 0, "take": []}
	if it.tier == ArmoryItemDef.Tier.COMPONENT or it.recipe.is_empty():
		return {"cost": it.price(1), "take": []}
	var used := {}
	var take: Array = []
	var cost := _resolve(cat, pool, index, it.socket, used, take, 0)
	return {"cost": cost, "take": take}


static func _resolve(cat: ArmoryCatalogDef, pool: Array, index: int, socket: int, used: Dictionary, take: Array,
		depth: int) -> int:
	var it := cat.at(index)
	if depth > MAX_DEPTH:
		return 0
	var cost := it.combine_cost
	for part in it.recipe:
		var pi := cat.index_of(StringName(part))
		var e := _match(pool, pi, socket, used)
		if not e.is_empty():
			used[e["key"]] = true
			take.append(e)
			continue
		var pit := cat.at(pi)
		if pit == null:
			continue
		if pit.tier == ArmoryItemDef.Tier.COMPONENT or pit.recipe.is_empty():
			cost += pit.price(1)
		else:
			cost += _resolve(cat, pool, pi, socket, used, take, depth + 1)
	return cost


## Parts of `index` that are not owned (matched like resolve): every missing
## Assembly and every missing component under it, in recipe order. The
## advisor picks the next part to buy from this list (§3.10 rule 2).
static func missing(cat: ArmoryCatalogDef, pool: Array, index: int) -> Array[int]:
	var out: Array[int] = []
	var it := cat.at(index)
	if it == null or it.recipe.is_empty():
		return out
	_missing(cat, pool, index, it.socket, {}, out, 0)
	return out


static func _missing(cat: ArmoryCatalogDef, pool: Array, index: int, socket: int, used: Dictionary, out: Array[int],
		depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	for part in cat.at(index).recipe:
		var pi := cat.index_of(StringName(part))
		var e := _match(pool, pi, socket, used)
		if not e.is_empty():
			used[e["key"]] = true
			continue
		out.append(pi)
		var pit := cat.at(pi)
		if pit != null and not pit.recipe.is_empty():
			_missing(cat, pool, pi, socket, used, out, depth + 1)


## Best owned instance of catalog item `index` not used yet: the target's
## socket first, then the last matching open slot (a spare before the active copy).
static func _match(pool: Array, index: int, socket: int, used: Dictionary) -> Dictionary:
	if socket != ArmoryItemDef.Socket.NONE:
		for e in pool:
			if int(e["index"]) == index and int(e["loc"]) == socket and not used.has(e["key"]):
				return e
	for k in range(pool.size() - 1, -1, -1):
		var e: Dictionary = pool[k]
		if int(e["index"]) == index and int(e["loc"]) >= ItemInventory.LOC_SLOT and not used.has(e["key"]):
			return e
	return {}


## Sell value of an item sold later (§4.4): `sell_late_frac` (60%) of Total,
## down to a multiple of `sell_round`.
static func sell_value(cat: ArmoryCatalogDef, index: int, r: EconomyRulesDef) -> int:
	var step := maxi(1, r.sell_round)
	return floori(r.sell_late_frac * total(cat, index) / float(step)) * step
