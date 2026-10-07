class_name ShopModel
extends RefCounted
## Pure logic of the Armory shop screen (design/ux/hud.md §10): tab / search
## filtering, per-item buy state and affordability, the per-hero recommended
## build and its next step, and sell / undo values. Reads the replicated
## SnapshotData.ProgressState only; it never mutates anything. The panel turns
## its answers into ACTION_BUY / ACTION_SELL requests (the server stays
## authoritative and re-checks every rule).
##
## Sell / undo decision (weapons-and-mods.md §3.6.4 rule 4, §4.7): the GDD
## allows both. A mount can be sold any time on the pad: 100% of what was paid
## during the current Armory visit (an undo), 60% of the rest rounded down to 5.
## "Undo last purchase" is therefore the same server action as sell
## (ACTION_SELL by socket), offered as "Undo" only while the whole line was
## bought this visit (paid_visit >= paid). Squad upgrades and Med-Packs cannot
## be sold, but since v21 they can be undone for a full refund during the visit
## they were bought in (ACTION_SELL with InputCommand.UNDO_ITEM_FLAG | index;
## ProgressState.visit_owned_bits / visit_medpacks say what is undoable). The
## server closes the visit (and every undo) when the hero leaves the pad.
##
## Example:
##   var m := ShopModel.new(catalog, rules, builds, &"hero_vesper_loom", weapon)
##   m.update(client.progress)
##   var rows := m.rows(ShopModel.Tab.CORE, "ember")

## Tab ids (values are stable; RECOMMENDED and BARREL were appended in v21).
enum Tab { ALL, CORE, FRAME, CHAMBER, SQUAD, CONSUMABLES, RECOMMENDED, BARREL }
## Why an item cannot be bought right now (AVAILABLE = it can).
enum State { AVAILABLE, CANT_AFFORD, OWNED, MAXED, LOCKED, WRONG_FAMILY, CARRY_FULL, DISABLED }
## Catalog list order.
enum Sort { DEFAULT, PRICE, NAME }

## Localization keys per Tab value (HUD_ rows in hud.csv).
const TAB_KEYS: Array[String] = ["HUD_SHOP_TAB_ALL", "HUD_SOCKET_CORE", "HUD_SOCKET_FRAME", "HUD_SOCKET_CHAMBER",
	"HUD_ARMORY_SQUAD", "HUD_ARMORY_CONSUMABLES", "HUD_SHOP_TAB_REC", "HUD_SOCKET_BARREL"]
## Tabs left to right (Barrel only while the catalog sells Barrel lines: tabs()).
const TAB_ORDER: Array[int] = [Tab.RECOMMENDED, Tab.ALL, Tab.CORE, Tab.FRAME, Tab.BARREL, Tab.CHAMBER, Tab.SQUAD,
	Tab.CONSUMABLES]
## Display order of the sections inside the All tab.
const SECTION_ORDER: Array[int] = [Tab.CORE, Tab.FRAME, Tab.BARREL, Tab.CHAMBER, Tab.SQUAD, Tab.CONSUMABLES]
const SORT_KEYS: Array[String] = ["HUD_SHOP_SORT_DEFAULT", "HUD_SHOP_SORT_PRICE", "HUD_SHOP_SORT_NAME"]

var catalog: ArmoryCatalogDef
var rules: EconomyRulesDef
var builds: RecommendedBuildsDef
var hero_id: StringName = &""
var weapon: WeaponDef
var progress: SnapshotData.ProgressState
## Catalog view options (the Recommended tab ignores them).
var sort_mode: int = Sort.DEFAULT
var affordable_only: bool = false
## Recommendation context (set_context) and tuning.
var advice_rules: AdviceRulesDef
var time_s: float = 0.0
var mode: StringName = &""
var team_size: int = 5
var enemy_defs: Array = []
var ally_defs: Array = []
var _advice: BuildAdvisor.Result


func _init(cat: ArmoryCatalogDef = null, rules_: EconomyRulesDef = null, builds_: RecommendedBuildsDef = null,
		hero: StringName = &"", weapon_: WeaponDef = null) -> void:
	catalog = cat
	rules = rules_
	builds = builds_
	hero_id = hero
	weapon = weapon_


## Sets the latest replicated progress (call every frame; it is a reference).
func update(p: SnapshotData.ProgressState) -> void:
	progress = p
	_advice = null


## Match context for the recommendations: clock, mode, team size and the
## HeroDefs of both teams (enemy threat tags, allied roles; self included).
func set_context(time_s_: float, mode_: StringName, team_size_: int, enemies: Array, allies: Array) -> void:
	time_s = time_s_
	mode = mode_
	team_size = team_size_
	enemy_defs = enemies
	ally_defs = allies
	_advice = null


## Tabs to show, left to right.
func tabs() -> Array[int]:
	var out: Array[int] = []
	for t in TAB_ORDER:
		if t == Tab.BARREL and not _sells_socket(ArmoryItemDef.Socket.BARREL):
			continue
		out.append(t)
	return out


func _sells_socket(socket: int) -> bool:
	if catalog == null:
		return false
	for it in catalog.items:
		if it != null and int(it.socket) == socket:
			return true
	return false


## The tab an item lives in (never Tab.ALL for a catalog item).
static func tab_of(it: ArmoryItemDef) -> int:
	match it.kind:
		ArmoryItemDef.Kind.SQUAD:
			return Tab.SQUAD
		ArmoryItemDef.Kind.CONSUMABLE:
			return Tab.CONSUMABLES
	match it.socket:
		ArmoryItemDef.Socket.CORE:
			return Tab.CORE
		ArmoryItemDef.Socket.BARREL:
			return Tab.BARREL
		ArmoryItemDef.Socket.FRAME:
			return Tab.FRAME
		ArmoryItemDef.Socket.CHAMBER:
			return Tab.CHAMBER
	return Tab.ALL


## Catalog indices shown for `tab` and the search `query` (case-insensitive
## substring of name, effect text, keywords or tags; empty = no filter). The
## Recommended tab lists the open recommendations, best first; every other tab
## lists catalog items in section order, then `sort_mode`, optionally only
## what can be bought now (`affordable_only`).
func rows(tab: int, query: String = "") -> Array[int]:
	var out: Array[int] = []
	if catalog == null:
		return out
	var q := query.strip_edges().to_lower()
	if tab == Tab.RECOMMENDED:
		var r := advice()
		if r != null:
			for a in r.advice:
				if a.item_index >= 0 and not out.has(a.item_index) and _matches(catalog.at(a.item_index), q):
					out.append(a.item_index)
		return out
	for sec in SECTION_ORDER:
		if tab != Tab.ALL and tab != sec:
			continue
		var section: Array[int] = []
		for i in catalog.items.size():
			var it := catalog.items[i]
			if it == null or tab_of(it) != sec or not _matches(it, q):
				continue
			if affordable_only and state(i) != State.AVAILABLE:
				continue
			section.append(i)
		match sort_mode:
			Sort.PRICE:
				section.sort_custom(func(a: int, b: int) -> bool:
					var ca := _list_cost(a)
					var cb := _list_cost(b)
					return ca < cb if ca != cb else a < b)
			Sort.NAME:
				section.sort_custom(func(a: int, b: int) -> bool:
					return catalog.at(a).label().naturalnocasecmp_to(catalog.at(b).label()) < 0)
		out.append_array(section)
	return out


func _matches(it: ArmoryItemDef, q: String) -> bool:
	if q == "":
		return true
	if it.label().to_lower().contains(q) or it.effect_label().to_lower().contains(q) \
			or it.display_name.to_lower().contains(q) or it.effect_text.to_lower().contains(q):
		return true
	for k in it.keywords:
		if k.to_lower().contains(q):
			return true
	for t in it.tags:
		if t.contains(q):
			return true
	return false


## Price used for sorting: what the next purchase costs, else the base price.
func _list_cost(index: int) -> int:
	var c := purchase_cost(index)
	return c if c >= 0 else catalog.at(index).price(1)


## Index into ProgressState.mount_* of an item's socket, -1 for non-mounts.
func slot_of(it: ArmoryItemDef) -> int:
	if it.socket == ArmoryItemDef.Socket.NONE:
		return -1
	return SnapshotData.ProgressState.MOUNT_SOCKETS.find(int(it.socket))


## Tier held on the item's line (mounts 0..3), 1 for an owned squad upgrade, else 0.
func held_tier(index: int) -> int:
	var it := catalog.at(index)
	if it == null or progress == null:
		return 0
	if it.kind == ArmoryItemDef.Kind.SQUAD:
		return 1 if (progress.owned_bits & (1 << index)) != 0 else 0
	var slot := slot_of(it)
	return progress.mount_tier[slot] if slot >= 0 and progress.mount_item[slot] == index else 0


## The item currently in the socket of `it` (null if empty / not a mount).
func held_item(it: ArmoryItemDef) -> ArmoryItemDef:
	var slot := slot_of(it)
	return catalog.at(progress.mount_item[slot]) if slot >= 0 and progress != null else null


## True when the item can go on the hero's weapon (family rule).
func fits(index: int) -> bool:
	var it := catalog.at(index)
	return it != null and (it.kind != ArmoryItemDef.Kind.MOUNT or it.fits(weapon))


## Lumen the purchase of `tier` (0 = next) would cost now: the upgrade
## difference on a held line, else the list price. -1 if nothing can be bought.
func purchase_cost(index: int, tier: int = 0) -> int:
	var it := catalog.at(index)
	if it == null or progress == null:
		return -1
	if it.kind == ArmoryItemDef.Kind.SQUAD or it.kind == ArmoryItemDef.Kind.CONSUMABLE:
		return it.price(1)
	var held := held_tier(index)
	var t := tier if tier > 0 else held + 1
	if t > it.tiers() or (held > 0 and t <= held):
		return -1
	return EconomyMath.upgrade_cost(it, t, held)


## Lumen credited by the auto-sell when buying `index` swaps out another line.
func swap_credit(index: int) -> int:
	var it := catalog.at(index)
	if it == null or progress == null:
		return 0
	var slot := slot_of(it)
	if slot < 0 or progress.mount_item[slot] < 0 or progress.mount_item[slot] == index:
		return 0
	return EconomyMath.sell_value(rules, progress.mount_paid[slot], progress.mount_paid_visit[slot])


## What stops a buy of `index` (tier 0 = next), or State.AVAILABLE.
func state(index: int, tier: int = 0) -> int:
	var it := catalog.at(index)
	if it == null or progress == null:
		return State.LOCKED
	if it.disabled:
		return State.DISABLED
	if not fits(index):
		return State.WRONG_FAMILY
	match it.kind:
		ArmoryItemDef.Kind.SQUAD:
			if held_tier(index) > 0:
				return State.OWNED
			var req := catalog.index_of(it.requires) if it.requires != &"" else -1
			if req >= 0 and held_tier(req) == 0:
				return State.LOCKED
		ArmoryItemDef.Kind.CONSUMABLE:
			if progress.medpacks >= it.carry_limit:
				return State.CARRY_FULL
	var cost := purchase_cost(index, tier)
	if cost < 0:
		return State.MAXED
	return State.AVAILABLE if progress.lumen + swap_credit(index) >= cost else State.CANT_AFFORD


func can_buy(index: int, tier: int = 0) -> bool:
	return state(index, tier) == State.AVAILABLE


## Wire argument of ACTION_BUY (item index | tier << 8; tier 0 = next tier).
static func buy_arg(index: int, tier: int = 0) -> int:
	return index | (maxi(tier, 0) << 8)


## Socket a sell request for `index` would target, -1 if the item is not a held mount line.
func sell_socket(index: int) -> int:
	var it := catalog.at(index)
	if it == null or (it.kind != ArmoryItemDef.Kind.MOUNT and it.kind != ArmoryItemDef.Kind.AMMO):
		return -1
	return int(it.socket) if held_tier(index) > 0 else -1


## Lumen a sell of the line in `socket` pays now (undo 100% part + 60% of the rest).
func sell_value(socket: int) -> int:
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(socket)
	if slot < 0 or progress == null or progress.mount_item[slot] < 0:
		return 0
	return EconomyMath.sell_value(rules, progress.mount_paid[slot], progress.mount_paid_visit[slot])


## True when selling `socket` refunds everything (the whole line was bought this visit).
func is_undo(socket: int) -> bool:
	var slot := SnapshotData.ProgressState.MOUNT_SOCKETS.find(socket)
	return slot >= 0 and progress != null and progress.mount_item[slot] >= 0 \
		and progress.mount_paid_visit[slot] >= progress.mount_paid[slot]


## `last_socket` (socket of the last purchase) if it can still be fully undone, else -1.
func undo_socket(last_socket: int) -> int:
	return last_socket if last_socket >= 0 and is_undo(last_socket) else -1


## ACTION_SELL argument that undoes the purchase of `index` this visit (full
## refund), or -1 when it cannot be undone (bought before this visit, not owned).
func undo_arg(index: int) -> int:
	var it := catalog.at(index) if catalog != null else null
	if it == null or progress == null:
		return -1
	match it.kind:
		ArmoryItemDef.Kind.MOUNT, ArmoryItemDef.Kind.AMMO:
			var sock := sell_socket(index)
			return sock if sock >= 0 and is_undo(sock) else -1
		ArmoryItemDef.Kind.SQUAD:
			if index < 32 and (progress.visit_owned_bits & (1 << index)) != 0:
				return InputCommand.UNDO_ITEM_FLAG | index
		ArmoryItemDef.Kind.CONSUMABLE:
			if progress.visit_medpacks > 0 and progress.medpacks > 0:
				return InputCommand.UNDO_ITEM_FLAG | index
	return -1


## Lumen an undo of `index` gives back (0 = cannot undo).
func undo_value(index: int) -> int:
	var arg := undo_arg(index)
	if arg < 0:
		return 0
	if arg & InputCommand.UNDO_ITEM_FLAG:
		return catalog.at(index).price(1)
	return sell_value(arg)


## Localization key of the plain-language text for a server Result.
static func result_key(r: int) -> String:
	match r:
		HeroProgress.Result.OK:
			return ""
		HeroProgress.Result.NOT_AT_ARMORY:
			return "HUD_SHOP_R_NOT_AT_ARMORY"
		HeroProgress.Result.DEAD:
			return "HUD_SHOP_R_DEAD"
		HeroProgress.Result.NO_FUNDS:
			return "HUD_SHOP_R_NO_FUNDS"
		HeroProgress.Result.WRONG_FAMILY:
			return "HUD_SHOP_R_WRONG_FAMILY"
		HeroProgress.Result.REQUIRES:
			return "HUD_SHOP_R_REQUIRES"
		HeroProgress.Result.LIMIT:
			return "HUD_SHOP_R_LIMIT"
		HeroProgress.Result.NOT_OWNED:
			return "HUD_SHOP_R_NOT_OWNED"
		HeroProgress.Result.MAXED:
			return "HUD_SHOP_R_MAXED"
		HeroProgress.Result.DISABLED:
			return "HUD_SHOP_R_DISABLED"
	return "HUD_SHOP_R_INVALID"


# --- Recommended build ----------------------------------------------------------------

func build() -> RecommendedBuildDef:
	if builds == null:
		return null
	var b := builds.for_hero(hero_id, mode)
	return b if b != null else builds.for_hero(hero_id)


## What BuildAdvisor sees for this hero (holdings, Lumen, gun, context, signals).
func build_state() -> BuildState:
	var st := BuildState.from_progress(progress, catalog, weapon, rules)
	st.time_s = time_s
	st.mode = mode
	st.team_size = team_size
	for d in enemy_defs:
		st.add_enemy(d)
	for d in ally_defs:
		st.add_ally(d)
	return st


## The recommendations (cached until the next update() / set_context()).
func advice() -> BuildAdvisor.Result:
	if _advice == null:
		var b := build()
		_advice = BuildAdvisor.evaluate(b, build_state(), advice_rules) if b != null and progress != null \
			else BuildAdvisor.Result.new()
	return _advice


## The best recommendation for `index`, or null when it is not recommended now.
func advice_for(index: int) -> BuildAdvisor.Advice:
	for a in advice().advice:
		if a.item_index == index:
			return a
	return null


## True once step `step` of the simple list is satisfied by what the hero owns.
func step_done(step: int) -> bool:
	var b := build()
	if b == null or step < 0 or step >= b.steps():
		return true
	var index := catalog.index_of(b.item_at(step))
	if index < 0:
		return true  # unknown ids never block the list
	var it := catalog.at(index)
	if it.kind == ArmoryItemDef.Kind.CONSUMABLE:
		return progress != null and progress.medpacks >= b.target_at(step)
	return held_tier(index) >= mini(b.target_at(step), it.tiers())


## Catalog index of the next recommended item (-1 if none).
func recommended_next() -> int:
	var a := advice().best()
	return a.item_index if a != null else -1


## Tier / count the next recommendation aims for (0 if none).
func recommended_target() -> int:
	var a := advice().best()
	return a.target if a != null else 0


## Localization key of why `index` is recommended ("" when it is not).
func reason_key(index: int) -> String:
	var a := advice_for(index)
	return a.reason_key if a != null else ""


## True when `index` is recommended now or still ahead on the build's core
## path (the REC tag on catalog cards).
func is_recommended(index: int) -> bool:
	if advice_for(index) != null:
		return true
	for e in path():
		if int(e["item"]) == index and not bool(e["done"]):
			return true
	return false


## Core path of the build for the strip, in order: {item, target, done, next,
## section, situational}. Situational, optional and inactive fallback nodes are
## left out (they show up in the Recommended tab when they apply).
func path() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b := build()
	if b == null or progress == null:
		return out
	var r := advice()
	var best := r.best()
	var nodes: Array[BuildNodeDef] = b.nodes if b.is_guide() else BuildAdvisor.simple_nodes(b)
	var ordered := nodes.duplicate()
	ordered.sort_custom(func(x: BuildNodeDef, y: BuildNodeDef) -> bool:
		return x.priority > y.priority if x.priority != y.priority else nodes.find(x) < nodes.find(y))
	for n in ordered:
		if n == null or not n.conditions.is_empty() or n.optional or n.fallback or not n.core:
			continue
		var idx := catalog.index_of(n.item_id)
		if idx < 0 or not fits(idx):
			continue
		out.append({"item": idx, "target": n.target_or_one(), "done": r.done.has(String(n.id)),
			"next": best != null and best.node == n, "section": n.section, "situational": false})
	return out


## Core nodes done / total.
func progress_counts() -> Vector2i:
	var r := advice()
	return Vector2i(r.core_done, r.core_total)


## True when `index` is out of reach now but within the expected income of
## the next AdviceRulesDef.affordable_soon_s.
func affordable_soon(index: int) -> bool:
	if progress == null or state(index) != State.CANT_AFFORD:
		return false
	var ar := advice_rules if advice_rules != null else AdviceRulesDef.new()
	var short := purchase_cost(index) - progress.lumen - swap_credit(index)
	return short <= ar.expected_income_per_min * ar.affordable_soon_s / 60.0


## Badge key for what buying `index` would do: tier upgrade, new mount, squad
## upgrade, consumable, or completed (maxed / owned).
func kind_key(index: int) -> String:
	var it := catalog.at(index)
	if it == null:
		return ""
	match it.kind:
		ArmoryItemDef.Kind.SQUAD:
			return "HUD_SHOP_KIND_DONE" if held_tier(index) > 0 else "HUD_SHOP_KIND_SQUAD"
		ArmoryItemDef.Kind.CONSUMABLE:
			return "HUD_SHOP_KIND_CONSUMABLE"
	var held := held_tier(index)
	if held >= it.tiers():
		return "HUD_SHOP_KIND_DONE"
	return "HUD_SHOP_KIND_TIER_UP" if held > 0 else "HUD_SHOP_KIND_NEW_MOUNT"


## Per-tier rows of an item for the detail pane: tier, price, upgrade, value, value2, held.
func tier_rows(index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var it := catalog.at(index)
	if it == null:
		return out
	var held := held_tier(index)
	for t in it.tiers():
		out.append({
			"tier": t + 1,
			"price": it.prices[t],
			"upgrade": EconomyMath.upgrade_cost(it, t + 1, t) if t > 0 else it.prices[t],
			"value": it.values[t] if t < it.values.size() else 0.0,
			"value2": it.values2[t] if t < it.values2.size() else 0.0,
			"held": held == t + 1,
		})
	return out
