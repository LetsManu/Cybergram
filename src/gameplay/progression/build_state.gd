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
