class_name ItemShopModel
extends RefCounted
## Pure logic of the Armory v2 shop (design/gdd/items-and-armory.md §3.9):
## the three tabs (Recommended / All Items / Item Sets), stat filters, shelves
## (Components / Assemblies / Signatures, then Ammo, Squad, Consumables),
## prices with owned parts (RecipeMath, §4.1), greyed reasons that match the
## server (ItemShop: Inventory full, Signature limit, Already owned, needs an
## Ammo Type, incompatible mod), the recipe tree, "Builds into", stats with
## "(capped)" (§3.7), sell values (§4.4) and undo availability (§3.6 rule 8).
## Reads the replicated SnapshotData.ProgressState only and never mutates
## anything; ItemShopPanel turns its answers into ACTION_BUY / ACTION_SELL
## requests (the server stays authoritative).
##
## Inventory places: index k into ProgressState.inv_items / INV_LOCS
## (P_CORE..P_MOD sockets and Chamber, then P_SLOT + 0..5 open slots).
##
## Example:
##   var m := ItemShopModel.new(catalog, rules, guides, &"hero_vesper_loom", weapon)
##   m.update(client.progress)
##   var st := m.state(catalog.index_of(&"ember_facet"))

enum Tab { RECOMMENDED, ALL, SETS }
## Why an item cannot be bought now (AVAILABLE = it can).
enum State { AVAILABLE, CANT_AFFORD, OWNED, ALREADY_OWNED, INVENTORY_FULL, SIGNATURE_LIMIT, NEEDS_AMMO,
	INCOMPATIBLE, CARRY_FULL, LOCKED, DISABLED }
## All Items grid rows (§3.9).
enum Shelf { COMPONENT, ASSEMBLY, SIGNATURE, AMMO, SQUAD, CONSUMABLE }

const TAB_KEYS: Array[String] = ["HUD_SHOP_TAB_REC", "HUD_SHOP2_TAB_ALL", "HUD_SHOP2_TAB_SETS"]
const SHELF_KEYS: Array[String] = ["HUD_SHOP2_SHELF_COMPONENTS", "HUD_SHOP2_SHELF_ASSEMBLIES",
	"HUD_SHOP2_SHELF_SIGNATURES", "HUD_SHOP2_SHELF_AMMO", "HUD_ARMORY_SQUAD", "HUD_SHOP2_SHELF_CONSUMABLES"]
## Stat filters, top to bottom (§3.9 All Items). A filter matches by stat id or item kind.
const FILTERS: Array[StringName] = [&"damage", &"fire_rate", &"range", &"handling", &"feed", &"health", &"armor",
	&"resist", &"cooldown", &"speed", &"siege", &"ammo", &"squad", &"consumable"]
const FILTER_STATS := {
	&"damage": ["mod_damage", "armor_pen_bonus", "headshot_bonus"],
	&"fire_rate": ["fire_rate_bonus"],
	&"range": ["falloff_range"],
	&"handling": ["spread_mult", "recoil_mult"],
	&"feed": ["mana_regen", "reload_time", "capacity_mult", "regen_delay"],
	&"health": ["item_max_hp"],
	&"armor": ["gear_armor"],
	&"resist": ["gear_resist"],
	&"cooldown": ["cooldown_reduction"],
	&"speed": ["item_move_speed", "ooc_move_speed"],
	&"siege": ["cell_carry_speed"],
}
## §3.7 caps per item stat (display only: the server applies them). Negative
## caps are reductions (spread / recoil / reload).
const CAPS := {
	"mod_damage": 0.25, "fire_rate_bonus": 0.15, "armor_pen_bonus": 0.60, "headshot_bonus": 0.30,
	"gear_armor": 0.20, "gear_resist": 0.20, "item_max_hp": 200.0, "cooldown_reduction": 0.25,
	"item_move_speed": 0.12, "falloff_range": 0.40, "spread_mult": -0.50, "recoil_mult": -0.50,
	"capacity_mult": 0.60, "mana_regen": 0.45, "reload_time": -0.35,
}
## Stat display names (HUD_ rows).
const STAT_KEYS := {
	"mod_damage": "HUD_STAT_DAMAGE", "mana_regen": "HUD_STAT_REGEN", "regen_delay": "HUD_STAT_REGEN_DELAY",
	"reload_time": "HUD_STAT_RELOAD", "falloff_range": "HUD_STAT_FALLOFF", "armor_pen_bonus": "HUD_STAT_ARMOR_PEN",
	"fire_rate_bonus": "HUD_STAT2_FIRE_RATE", "spread_mult": "HUD_STAT2_SPREAD", "recoil_mult": "HUD_STAT2_RECOIL",
	"headshot_bonus": "HUD_STAT2_HEADSHOT", "capacity_mult": "HUD_STAT2_CAPACITY", "gear_armor": "HUD_STAT2_ARMOR",
	"gear_resist": "HUD_STAT2_RESIST", "item_max_hp": "HUD_STAT2_MAX_HP", "item_move_speed": "HUD_STAT2_MOVE",
	"ooc_move_speed": "HUD_STAT2_MOVE_OOC", "cell_carry_speed": "HUD_STAT2_CARRY", "cooldown_reduction": "HUD_STAT2_CDR",
}
## Stats shown as flat numbers (the rest are fractions shown as %).
const FLAT_STATS := ["item_max_hp"]

const P_CORE: int = 0
const P_BARREL: int = 1
const P_FRAME: int = 2
const P_AMMO: int = 3
const P_MOD: int = 4
const P_SLOT: int = 5
const PLACES: int = 11

var catalog: ArmoryCatalogDef
var rules: EconomyRulesDef
var builds: RecommendedBuildsDef
## The selected Item Set as a guide (null = the hero's default guide).
var custom_guide: RecommendedBuildDef
var hero_id: StringName = &""
var weapon: WeaponDef
var progress: SnapshotData.ProgressState
var advice_rules: AdviceRulesDef
var time_s: float = 0.0
var mode: StringName = &""
var team_size: int = 5
var enemy_defs: Array = []
var ally_defs: Array = []
## Active stat filters (FILTERS ids); an item must match all of them.
var filters: Dictionary = {}
var _st: BuildState
var _advice: BuildAdvisor.Result


func _init(cat: ArmoryCatalogDef = null, rules_: EconomyRulesDef = null, builds_: RecommendedBuildsDef = null,
		hero: StringName = &"", weapon_: WeaponDef = null) -> void:
	catalog = cat
	rules = rules_ if rules_ != null else EconomyRulesDef.new()
	builds = builds_
	hero_id = hero
	weapon = weapon_


## Sets the latest replicated progress (call every frame).
func update(p: SnapshotData.ProgressState) -> void:
	progress = p
	_st = null
	_advice = null


## Recommendation context (clock, mode, team size, both teams' HeroDefs).
func set_context(time_s_: float, mode_: StringName, team_size_: int, enemies: Array, allies: Array) -> void:
	time_s = time_s_
	mode = mode_
	team_size = team_size_
	enemy_defs = enemies
	ally_defs = allies
	_st = null
	_advice = null


func set_custom_guide(g: RecommendedBuildDef) -> void:
	if g != custom_guide:
		custom_guide = g
		_advice = null


## True on a Mana gun (Crystal names; Chip names on Mechanical guns, §3.3).
func mana_gun() -> bool:
	return weapon == null or weapon.feed_kind == WeaponDef.FeedKind.MANA


## Player-facing name of catalog item `index` for this hero's gun (label_for).
func name_of(index: int) -> String:
	var it := catalog.at(index) if catalog != null else null
	return it.label_for(mana_gun()) if it != null else ""


## What BuildAdvisor and the prices see (cached until update / set_context).
func build_state() -> BuildState:
	if _st == null:
		_st = BuildState.from_progress(progress, catalog, weapon, rules)
		_st.time_s = time_s
		_st.mode = mode
		_st.team_size = team_size
		for d in enemy_defs:
			_st.add_enemy(d)
		for d in ally_defs:
			_st.add_ally(d)
	return _st


# --- Inventory -----------------------------------------------------------------------

## Catalog index at place `k` (-1 = empty).
func item_at(k: int) -> int:
	if progress == null or k < 0 or k >= progress.inv_items.size():
		return -1
	return progress.inv_items[k]


## True when the open-slot item at `k` is a spare: an earlier open slot holds
## the same id, so it gives no stats (§3.4 rule 3).
func is_spare(k: int) -> bool:
	var idx := item_at(k)
	if k < P_SLOT or idx < 0:
		return false
	for j in range(P_SLOT, k):
		if item_at(j) == idx:
			return true
	return false


## Places holding catalog item `index`, in INV_LOCS order.
func places_of(index: int) -> Array[int]:
	var out: Array[int] = []
	if index < 0:
		return out
	for k in PLACES:
		if item_at(k) == index:
			out.append(k)
	return out


func slots_used() -> int:
	var n := 0
	for k in range(P_SLOT, PLACES):
		if item_at(k) >= 0:
			n += 1
	return n


func open_slots() -> int:
	return rules.open_slots if rules != null else 6


## Signatures held / limit ("Signatures n/2", §3.6 rule 5).
func signatures() -> Vector2i:
	return Vector2i(build_state().signature_count(), rules.signature_limit if rules != null else 2)


## Lumen selling the item at place `k` gives (§4.4: 60% of Total, to 5).
func sell_value(k: int) -> int:
	var idx := item_at(k)
	return RecipeMath.sell_value(catalog, idx, rules) if idx >= 0 else 0


## ACTION_SELL argument selling place `k` (-1 when empty).
func sell_arg(k: int) -> int:
	return SnapshotData.ProgressState.INV_LOCS[k] if item_at(k) >= 0 else -1


## True when the purchase that put the item at `k` can be undone on its own (§3.6 rule 8).
func can_undo(k: int) -> bool:
	return progress != null and item_at(k) >= 0 and (progress.inv_undo_bits & (1 << k)) != 0


## ACTION_SELL argument undoing the purchase at place `k`, or -1.
func undo_arg(k: int) -> int:
	return InputCommand.UNDO_ITEM_FLAG | SnapshotData.ProgressState.INV_LOCS[k] if can_undo(k) else -1


## ACTION_SELL argument undoing a squad upgrade / Med-Pack bought this visit, or -1.
func row_undo_arg(index: int) -> int:
	var it := catalog.at(index) if catalog != null else null
	if it == null or progress == null:
		return -1
	var ok := false
	match it.kind:
		ArmoryItemDef.Kind.SQUAD:
			ok = index < 32 and (progress.visit_owned_bits & (1 << index)) != 0
		ArmoryItemDef.Kind.CONSUMABLE:
			ok = progress.visit_medpacks > 0 and progress.medpacks > 0
	return InputCommand.UNDO_ITEM_FLAG | InputCommand.UNDO_ROW_FLAG | index if ok else -1


## "Undo last" is available (any purchase / sale this visit).
func undo_last_available() -> bool:
	return progress != null and progress.inv_txns > 0


## Squad upgrades owned (catalog indices) for the squad / Med-Pack row.
func squad_owned() -> Array[int]:
	var out: Array[int] = []
	if catalog == null or progress == null:
		return out
	for i in mini(catalog.items.size(), 32):
		var it := catalog.items[i]
		if it != null and it.kind == ArmoryItemDef.Kind.SQUAD and (progress.owned_bits & (1 << i)) != 0:
			out.append(i)
	return out


# --- Prices and states ------------------------------------------------------------------

## Total(X) (§4.1): the full recipe price.
func total(index: int) -> int:
	return RecipeMath.total(catalog, index) if catalog != null else 0


## Lumen buying `index` costs now: RemainingCost with owned parts used up
## (§3.6 rule 2), the list price for rows and the Chamber.
func cost(index: int) -> int:
	var it := catalog.at(index) if catalog != null else null
	if it == null:
		return 0
	if it.is_recipe_item():
		return int(RecipeMath.resolve(catalog, build_state().pool, index)["cost"])
	return it.price(1)


## Lumen credited by the sale a buy of `index` triggers: a socket part it
## does not build from (§3.6 rule 4), the loaded ammo / mod, and a mod the
## new Ammo Type does not fit (weapons-and-mods.md §3.6.4 rule 7).
func swap_credit(index: int) -> int:
	var it := catalog.at(index) if catalog != null else null
	if it == null or progress == null:
		return 0
	if it.is_recipe_item() and not it.uses_open_slot():
		var k := SnapshotData.ProgressState.INV_LOCS.find(int(it.socket))
		var held := item_at(k)
		if held < 0:
			return 0
		for t in RecipeMath.resolve(catalog, build_state().pool, index)["take"]:
			if int(t["key"]) == k:
				return 0
		return RecipeMath.sell_value(catalog, held, rules)
	if it.kind == ArmoryItemDef.Kind.AMMO:
		var c := 0
		if item_at(P_AMMO) >= 0:
			c += RecipeMath.sell_value(catalog, item_at(P_AMMO), rules)
		var m := catalog.at(item_at(P_MOD))
		if m != null and not mod_fits(m, it.ammo_type):
			c += RecipeMath.sell_value(catalog, item_at(P_MOD), rules)
		return c
	if it.kind == ArmoryItemDef.Kind.AMMO_MOD and item_at(P_MOD) >= 0:
		return RecipeMath.sell_value(catalog, item_at(P_MOD), rules)
	return 0


static func mod_fits(mod: ArmoryItemDef, ammo_type: int) -> bool:
	return mod.fits_ammo.is_empty() or mod.fits_ammo.has(ammo_type)


## Open slots used after buying `index` (its used-up parts freed).
func slots_after(index: int) -> int:
	var it := catalog.at(index)
	var used := slots_used()
	if it.is_recipe_item() and not it.recipe.is_empty():
		for t in RecipeMath.resolve(catalog, build_state().pool, index)["take"]:
			if int(t["loc"]) >= ItemInventory.LOC_SLOT:
				used -= 1
	return used + (1 if it.uses_open_slot() else 0)


## What stops a buy of `index`, in the server's order (ItemShop), or AVAILABLE.
func state(index: int) -> int:
	var it := catalog.at(index) if catalog != null else null
	if it == null or progress == null:
		return State.LOCKED
	if it.disabled:
		return State.DISABLED
	match it.kind:
		ArmoryItemDef.Kind.SQUAD:
			if index < 32 and (progress.owned_bits & (1 << index)) != 0:
				return State.OWNED
			var req := catalog.index_of(it.requires) if it.requires != &"" else -1
			if req >= 0 and req < 32 and (progress.owned_bits & (1 << req)) == 0:
				return State.LOCKED
		ArmoryItemDef.Kind.CONSUMABLE:
			if progress.medpacks >= it.carry_limit:
				return State.CARRY_FULL
		ArmoryItemDef.Kind.AMMO:
			if item_at(P_AMMO) == index:
				return State.ALREADY_OWNED
		ArmoryItemDef.Kind.AMMO_MOD:
			if item_at(P_MOD) == index:
				return State.ALREADY_OWNED
			var ammo := catalog.at(item_at(P_AMMO))
			if ammo == null:
				return State.NEEDS_AMMO
			if not mod_fits(it, ammo.ammo_type):
				return State.INCOMPATIBLE
		_:
			if it.is_recipe_item():
				if it.tier != ArmoryItemDef.Tier.COMPONENT and not places_of(index).is_empty():
					return State.ALREADY_OWNED
				if it.tier == ArmoryItemDef.Tier.SIGNATURE and signatures().x >= signatures().y:
					return State.SIGNATURE_LIMIT
				if slots_after(index) > open_slots():
					return State.INVENTORY_FULL
	return State.AVAILABLE if progress.lumen + swap_credit(index) >= cost(index) else State.CANT_AFFORD


## Lumen still missing for `index` (0 when affordable).
func shortfall(index: int) -> int:
	return maxi(0, cost(index) - swap_credit(index) - (progress.lumen if progress != null else 0))


## Localization key of a greyed reason (State), "" for AVAILABLE.
static func state_key(st: int) -> String:
	match st:
		State.CANT_AFFORD:
			return "HUD_SHOP_NEED_LUMEN"
		State.OWNED, State.ALREADY_OWNED:
			return "HUD_SHOP2_ALREADY_OWNED"
		State.INVENTORY_FULL:
			return "HUD_SHOP2_INVENTORY_FULL"
		State.SIGNATURE_LIMIT:
			return "HUD_SHOP2_SIGNATURE_LIMIT"
		State.NEEDS_AMMO:
			return "HUD_SHOP2_NEEDS_AMMO"
		State.INCOMPATIBLE:
			return "HUD_SHOP2_INCOMPATIBLE"
		State.CARRY_FULL:
			return "HUD_SHOP_CARRY_FULL"
		State.LOCKED:
			return "HUD_SHOP2_LOCKED"
		State.DISABLED:
			return "HUD_SHOP_DISABLED"
	return ""


## Localization key of a server Result (exact toast, §3.9).
static func result_key(r: int) -> String:
	match r:
		HeroProgress.Result.INVENTORY_FULL:
			return "HUD_SHOP2_INVENTORY_FULL"
		HeroProgress.Result.SIGNATURE_LIMIT:
			return "HUD_SHOP2_SIGNATURE_LIMIT"
		HeroProgress.Result.ALREADY_OWNED:
			return "HUD_SHOP2_ALREADY_OWNED"
		HeroProgress.Result.UNDO_BLOCKED:
			return "HUD_SHOP2_R_UNDO_BLOCKED"
		HeroProgress.Result.INCOMPATIBLE:
			return "HUD_SHOP2_INCOMPATIBLE"
		HeroProgress.Result.UNKNOWN_ITEM:
			return "HUD_SHOP_R_INVALID"
	return ShopModel.result_key(r)


# --- All Items ---------------------------------------------------------------------

## Grid row of an item (-1 = not sold by the v2 shop, e.g. a v1 tiered line).
static func shelf_of(it: ArmoryItemDef) -> int:
	if it == null:
		return -1
	match it.kind:
		ArmoryItemDef.Kind.CONSUMABLE:
			return Shelf.CONSUMABLE
		ArmoryItemDef.Kind.SQUAD:
			return Shelf.SQUAD
		ArmoryItemDef.Kind.AMMO, ArmoryItemDef.Kind.AMMO_MOD:
			return Shelf.AMMO
	match it.tier:
		ArmoryItemDef.Tier.COMPONENT:
			return Shelf.COMPONENT
		ArmoryItemDef.Tier.ASSEMBLY:
			return Shelf.ASSEMBLY
		ArmoryItemDef.Tier.SIGNATURE:
			return Shelf.SIGNATURE
	return -1


## True when item `index` has stat filter `f`.
func has_filter(index: int, f: StringName) -> bool:
	var it := catalog.at(index)
	if it == null:
		return false
	match f:
		&"ammo":
			return it.kind == ArmoryItemDef.Kind.AMMO or it.kind == ArmoryItemDef.Kind.AMMO_MOD
		&"squad":
			return it.kind == ArmoryItemDef.Kind.SQUAD
		&"consumable":
			return it.kind == ArmoryItemDef.Kind.CONSUMABLE
		&"siege":
			if it.passive == &"siegebreaker":
				return true
	var ids := it.stat_ids if mana_gun() or it.mech_stat_ids.is_empty() else it.mech_stat_ids
	for s in FILTER_STATS.get(f, []):
		if ids.has(s):
			return true
	return false


func toggle_filter(f: StringName) -> void:
	if filters.has(f):
		filters.erase(f)
	else:
		filters[f] = true


## [{shelf, items}] for the grid: non-empty shelves in Shelf order, items by
## Total then data order, every active filter matched, `query` a substring of
## the name (both forms) or keywords.
func shelves(query: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalog == null:
		return out
	var q := query.strip_edges().to_lower()
	var by: Array = []
	for s in Shelf.size():
		by.append([])
	for i in catalog.items.size():
		var it := catalog.items[i]
		var s := shelf_of(it)
		if s < 0 or not _matches(i, q):
			continue
		var ok := true
		for f in filters:
			if not has_filter(i, f):
				ok = false
				break
		if ok:
			by[s].append(i)
	for s in Shelf.size():
		var items: Array[int] = []
		items.assign(by[s])
		items.sort_custom(func(a: int, b: int) -> bool:
			var ta := total(a)
			var tb := total(b)
			return ta < tb if ta != tb else a < b)
		if not items.is_empty():
			out.append({"shelf": s, "items": items})
	return out


func _matches(index: int, q: String) -> bool:
	if q == "":
		return true
	var it := catalog.at(index)
	if it.label().to_lower().contains(q) or name_of(index).to_lower().contains(q) or it.effect_label().to_lower().contains(q):
		return true
	for k in it.keywords:
		if k.to_lower().contains(q):
			return true
	return false


## Recipe tree of `index`, depth first: [{index, depth, owned, place}] with
## the item itself first (depth 0). Parts are matched to owned instances like
## RecipeMath.resolve (target socket first, then the last open slot holding
## the id, each instance once); owned parts are leaves (their own parts are
## already used up).
func tree(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var it := catalog.at(index) if catalog != null else null
	if it == null:
		return out
	var held := places_of(index)
	out.append({"index": index, "depth": 0, "owned": not held.is_empty() and it.tier != ArmoryItemDef.Tier.COMPONENT,
		"place": held[0] if not held.is_empty() else -1})
	_tree(index, int(it.socket), 1, {}, out)
	return out


func _tree(index: int, socket: int, depth: int, used: Dictionary, out: Array[Dictionary]) -> void:
	for part in catalog.at(index).recipe:
		var pi := catalog.index_of(StringName(part))
		var k := _match_place(pi, socket, used)
		if k >= 0:
			used[k] = true
		out.append({"index": pi, "depth": depth, "owned": k >= 0, "place": k})
		if k < 0 and catalog.at(pi) != null and not catalog.at(pi).recipe.is_empty():
			_tree(pi, socket, depth + 1, used, out)


func _match_place(index: int, socket: int, used: Dictionary) -> int:
	if socket != ArmoryItemDef.Socket.NONE:
		var sk := SnapshotData.ProgressState.INV_LOCS.find(socket)
		if sk >= 0 and item_at(sk) == index and not used.has(sk):
			return sk
	for k in range(PLACES - 1, P_SLOT - 1, -1):
		if item_at(k) == index and not used.has(k):
			return k
	return -1


## Items whose recipe names `index` directly ("Builds into").
func builds_into(index: int) -> Array[int]:
	var out: Array[int] = []
	var it := catalog.at(index) if catalog != null else null
	if it == null:
		return out
	for i in catalog.items.size():
		var o := catalog.items[i]
		if o != null and o.recipe.has(String(it.id)) and not out.has(i):
			out.append(i)
	return out


## Sum of stat `id` over the items that give stats now (sockets, Chamber,
## first copies in open slots; spares give nothing).
func current_stat(id: String) -> float:
	var v := 0.0
	for k in PLACES:
		var idx := item_at(k)
		if idx < 0 or is_spare(k):
			continue
		v += _stat_of(catalog.at(idx), id)
	return v


func _stat_of(it: ArmoryItemDef, id: String) -> float:
	if it == null:
		return 0.0
	var ids := it.stat_ids
	var vals := it.stat_values
	if not mana_gun() and not it.mech_stat_ids.is_empty():
		ids = it.mech_stat_ids
		vals = it.mech_stat_values
	var v := 0.0
	for i in mini(ids.size(), vals.size()):
		if ids[i] == id:
			v += vals[i]
	return v


## Stat lines of `index` for this gun: [{id, key, value, capped}]. `capped`
## is true when the hero's current total already reaches the §3.7 cap, or
## this item would push it over (the extra is lost, §3.7).
func stat_lines(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var it := catalog.at(index) if catalog != null else null
	if it == null:
		return out
	var ids := it.stat_ids
	var vals := it.stat_values
	if not mana_gun() and not it.mech_stat_ids.is_empty():
		ids = it.mech_stat_ids
		vals = it.mech_stat_values
	var owned := not places_of(index).is_empty()
	for i in mini(ids.size(), vals.size()):
		var id := ids[i]
		var capped := false
		if CAPS.has(id):
			var cap: float = CAPS[id]
			var now := current_stat(id)
			var after := now if owned else now + vals[i]
			capped = after > cap + 0.0001 if cap > 0.0 else after < cap - 0.0001
			capped = capped or (not owned and absf(now) >= absf(cap) - 0.0001)
		out.append({"id": id, "key": STAT_KEYS.get(id, ""), "value": vals[i], "capped": capped})
	return out


## Formats a stat value: "+25" for flat stats, "+8%" / "-10%" for fractions.
static func stat_text(id: String, value: float) -> String:
	if FLAT_STATS.has(id):
		return "%+d" % roundi(value)
	return "%+d%%" % roundi(value * 100.0)


## Localization key of where `index` goes / shows ("Shows on: shoulders",
## a gun socket, or the Chamber).
func shows_on_key(index: int) -> String:
	var it := catalog.at(index)
	if it == null:
		return ""
	if it.body_anchor != &"":
		return "HUD_SHOP2_ON_" + String(it.body_anchor).trim_prefix("body_").to_upper()
	match it.socket:
		ArmoryItemDef.Socket.CORE:
			return "HUD_SOCKET_CORE"
		ArmoryItemDef.Socket.BARREL:
			return "HUD_SOCKET_BARREL"
		ArmoryItemDef.Socket.FRAME:
			return "HUD_SOCKET_FRAME"
		ArmoryItemDef.Socket.CHAMBER:
			return "HUD_SOCKET_CHAMBER"
	return ""


# --- Recommended ----------------------------------------------------------------------

func build() -> RecommendedBuildDef:
	if custom_guide != null:
		return custom_guide
	if builds == null:
		return null
	var b := builds.for_hero(hero_id, mode)
	return b if b != null else builds.for_hero(hero_id)


func advice() -> BuildAdvisor.Result:
	if _advice == null:
		var b := build()
		_advice = BuildAdvisor.evaluate(b, build_state(), advice_rules) if b != null and progress != null \
			else BuildAdvisor.Result.new()
	return _advice


## One Recommended card for finished item `goal`: {goal, next, next_cost,
## total, reason, state, done, situational}. `next` is the part to buy now
## (BuildAdvisor.next_part, §3.10 rule 2) and `state` its buy state.
func card(goal: int, reason_key: String, situational: bool = false) -> Dictionary:
	var st := build_state()
	var it := catalog.at(goal)
	var done := false
	if it != null:
		match it.kind:
			ArmoryItemDef.Kind.SQUAD:
				done = state(goal) == State.OWNED
			ArmoryItemDef.Kind.CONSUMABLE:
				done = false
			_:
				done = not places_of(goal).is_empty()
	var nxt := {"index": goal, "cost": cost(goal)}
	if it != null and it.is_recipe_item() and not done:
		nxt = BuildAdvisor.next_part(st, goal)
	var ni := int(nxt["index"])
	return {"goal": goal, "next": ni, "next_cost": cost(ni), "total": total(goal), "reason": reason_key,
		"state": state(ni) if not done else State.OWNED, "done": done, "situational": situational}


## The four Recommended sections (§3.9): {starter: cards, core: [{node, cards}],
## situational: cards, ammo: cards}. Core holds one row per open guide step
## (2-3 choices); Situational the counter nodes the advisor offers now, with
## its reason; Ammo one Ammo Type and one Mod suggestion.
func sections() -> Dictionary:
	var out := {"starter": [], "core": [], "situational": [], "ammo": []}
	var b := build()
	if b == null or catalog == null or progress == null:
		return out
	var offered := {}
	for a in advice().advice:
		offered[a.node] = a
	var done := advice().done
	var nodes: Array[BuildNodeDef] = b.nodes if b.is_guide() else BuildAdvisor.simple_nodes(b)
	var ordered := nodes.duplicate()
	ordered.sort_custom(func(x: BuildNodeDef, y: BuildNodeDef) -> bool:
		return x.priority > y.priority if x.priority != y.priority else nodes.find(x) < nodes.find(y))
	var have_ammo := false
	var have_mod := false
	var seen_starter := {}
	for n: BuildNodeDef in ordered:
		if n == null:
			continue
		var idx := catalog.index_of(n.item_id)
		var it := catalog.at(idx)
		if it == null:
			continue
		var a: BuildAdvisor.Advice = offered.get(n)
		var reason := a.reason_key if a != null else _node_reason(n)
		if not n.conditions.is_empty():
			if a != null:
				out["situational"].append(card(a.goal_index if a.goal_index >= 0 else idx, reason, true))
			continue
		if it.kind == ArmoryItemDef.Kind.AMMO or it.kind == ArmoryItemDef.Kind.AMMO_MOD:
			var is_mod := it.kind == ArmoryItemDef.Kind.AMMO_MOD
			if (is_mod and have_mod) or (not is_mod and have_ammo):
				continue
			var goal := a.goal_index if a != null and a.goal_index >= 0 else idx
			out["ammo"].append(card(goal, reason))
			if is_mod:
				have_mod = true
			else:
				have_ammo = true
			continue
		var choices: Array[int] = [idx]
		for alt in n.alternatives:
			var ai := catalog.index_of(StringName(alt))
			if ai >= 0 and not choices.has(ai):
				choices.append(ai)
		if n.section == BuildNodeDef.Section.OPENING or n.section == BuildNodeDef.Section.EARLY:
			for c in choices:
				if not seen_starter.has(c):
					seen_starter[c] = true
					out["starter"].append(card(c, reason))
			continue
		if done.has(String(n.id)):
			continue
		var cards: Array = []
		for c in choices.slice(0, 3):
			cards.append(card(c, reason))
		out["core"].append({"node": n, "cards": cards, "next": a != null and advice().best() == a})
	return out


func _node_reason(n: BuildNodeDef) -> String:
	if n.reason_key != "":
		return n.reason_key
	return BuildAdvisor.SECTION_REASONS[clampi(n.section, 0, BuildAdvisor.SECTION_REASONS.size() - 1)]
