class_name BuildState
extends RefCounted
## What BuildAdvisor needs to know about one hero (docs/armory.md): holdings,
## Lumen, gun family, match time / mode / team size, server advice signals and
## the threat tags of the enemy team / roles of the own team. Built from the
## replicated ProgressState on the client or from HeroProgress on the server,
## so humans and bots get the same recommendations.

var catalog: ArmoryCatalogDef
var weapon: WeaponDef
var lumen: int = 0
## Catalog index -> held tier (mount / ammo line), 1 (owned squad upgrade) or
## carried count (consumable).
var holdings: Dictionary = {}
## Socket -> Lumen a swap would credit (auto-sell of the held line).
var credits: Dictionary = {}
var time_s: float = 0.0
## &"5v5", &"3v3", &"custom", &"bots" (RecommendedBuildDef.modes).
var mode: StringName = &""
var team_size: int = 5
## SnapshotData.ProgressState.SIG_* bits.
var signals: int = 0
## Threat tag -> number of enemy heroes carrying it (HeroDef.tags).
var enemy_tags: Dictionary = {}
## Role -> number of allied heroes (HeroDef.roles), including this hero.
var ally_roles: Dictionary = {}
## Armory v2 (items-and-armory.md §3.10): the recipe catalog is in use; the
## owned instances as a RecipeMath pool, open slots used, and the limits.
var v2: bool = false
var pool: Array = []
var slots_used: int = 0
var open_slots: int = 6
var signature_limit: int = 2


func held(index: int) -> int:
	return int(holdings.get(index, 0))


func swap_credit(index: int) -> int:
	var it := catalog.at(index) if catalog != null else null
	if it == null or it.socket == ArmoryItemDef.Socket.NONE:
		return 0
	return int(credits.get(int(it.socket), 0))


## Family rule (mount lines only).
func fits(it: ArmoryItemDef) -> bool:
	return it.kind != ArmoryItemDef.Kind.MOUNT or it.fits(weapon)


## Adds `def`'s tags (enemy) or roles (ally) to the team pictures.
func add_enemy(def: HeroDef) -> void:
	if def == null:
		return
	for t in def.tags:
		enemy_tags[t] = int(enemy_tags.get(t, 0)) + 1


func add_ally(def: HeroDef) -> void:
	if def == null:
		return
	for r in def.roles:
		ally_roles[r] = int(ally_roles.get(r, 0)) + 1


## From the replicated progress block (client side).
static func from_progress(p: SnapshotData.ProgressState, cat: ArmoryCatalogDef, weapon_: WeaponDef,
		econ: EconomyRulesDef) -> BuildState:
	var st := BuildState.new()
	st.catalog = cat
	st.weapon = weapon_
	if p == null or cat == null:
		return st
	st.lumen = p.lumen
	st.signals = p.signals
	if econ != null:
		st.open_slots = econ.open_slots
		st.signature_limit = econ.signature_limit
	if cat.is_recipe_catalog():
		st.v2 = true
		for k in SnapshotData.ProgressState.INV_LOCS.size():
			var idx := p.inv_items[k]
			if idx >= 0:
				var loc: int = SnapshotData.ProgressState.INV_LOCS[k]
				st.pool.append({"index": idx, "loc": loc, "key": k})
				st.holdings[idx] = int(st.holdings.get(idx, 0)) + 1
				if loc >= ItemInventory.LOC_SLOT:
					st.slots_used += 1
	for i in cat.items.size():
		var it := cat.items[i]
		if it == null:
			continue
		match it.kind:
			ArmoryItemDef.Kind.SQUAD:
				if i < 32 and (p.owned_bits & (1 << i)) != 0:
					st.holdings[i] = 1
			ArmoryItemDef.Kind.CONSUMABLE:
				if p.medpacks > 0:
					st.holdings[i] = p.medpacks
	for k in SnapshotData.ProgressState.MOUNT_SOCKETS.size():
		var idx := p.mount_item[k]
		if idx >= 0:
			st.holdings[idx] = p.mount_tier[k]
			if econ != null:
				st.credits[SnapshotData.ProgressState.MOUNT_SOCKETS[k]] = EconomyMath.sell_value(econ,
					p.mount_paid[k], p.mount_paid_visit[k])
	return st


## From the server-side wallet (bots, server tests).
static func from_hero(hp: HeroProgress, cat: ArmoryCatalogDef, weapon_: WeaponDef, econ: EconomyRulesDef) -> BuildState:
	var st := BuildState.new()
	st.catalog = cat
	st.weapon = weapon_
	if hp == null or cat == null:
		return st
	st.lumen = hp.lumen
	st.signals = hp.signals
	if econ != null:
		st.open_slots = econ.open_slots
		st.signature_limit = econ.signature_limit
	if cat.is_recipe_catalog():
		st.v2 = true
		st.pool = hp.inv.pool()
		st.slots_used = hp.inv.slots.size()
		for e in st.pool:
			st.holdings[int(e["index"])] = int(st.holdings.get(int(e["index"]), 0)) + 1
	for id in hp.owned:
		var i := cat.index_of(id)
		if i >= 0:
			st.holdings[i] = 1
	if hp.medpacks > 0:
		for i in cat.items.size():
			if cat.items[i] != null and cat.items[i].kind == ArmoryItemDef.Kind.CONSUMABLE:
				st.holdings[i] = hp.medpacks
	for s in hp.mounts:
		var m: HeroProgress.Mount = hp.mounts[s]
		st.holdings[m.index] = m.tier
		if econ != null:
			st.credits[int(s)] = EconomyMath.sell_value(econ, m.paid, m.paid_visit)
	return st


## v2: Signatures held.
func signature_count() -> int:
	var n := 0
	for e in pool:
		var it := catalog.at(int(e["index"]))
		if it != null and it.tier == ArmoryItemDef.Tier.SIGNATURE:
			n += 1
	return n


## v2: catalog index in the Chamber at `loc` (ItemInventory.LOC_AMMO / LOC_MOD), -1 if empty.
func chamber(loc: int) -> int:
	for e in pool:
		if int(e["loc"]) == loc:
			return int(e["index"])
	return -1


## v2: true when catalog item `index` is a part (at any depth) of an owned item.
func built_into(index: int) -> bool:
	var id := catalog.at(index).id if catalog != null and catalog.at(index) != null else &""
	if id == &"":
		return false
	for e in pool:
		if _contains_part(catalog.at(int(e["index"])), id):
			return true
	return false


func _contains_part(it: ArmoryItemDef, id: StringName) -> bool:
	if it == null:
		return false
	for part in it.recipe:
		if StringName(part) == id or _contains_part(catalog.find(StringName(part)), id):
			return true
	return false
