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
## bought this visit (paid_visit >= paid). Squad upgrades and Med-Packs have no
## sell rule in the GDD, so they can be neither sold nor undone. The server
## closes the visit (and the undo) when the hero leaves the pad.
##
## Example:
##   var m := ShopModel.new(catalog, rules, builds, &"hero_vesper_loom", weapon)
##   m.update(client.progress)
##   var rows := m.rows(ShopModel.Tab.CORE, "ember")

enum Tab { ALL, CORE, FRAME, CHAMBER, SQUAD, CONSUMABLES }
## Why an item cannot be bought right now (AVAILABLE = it can).
enum State { AVAILABLE, CANT_AFFORD, OWNED, MAXED, LOCKED, WRONG_FAMILY, CARRY_FULL }

## Localization keys per Tab (HUD_ rows in hud.csv).
const TAB_KEYS: Array[String] = ["HUD_SHOP_TAB_ALL", "HUD_SOCKET_CORE", "HUD_SOCKET_FRAME", "HUD_SOCKET_CHAMBER",
	"HUD_ARMORY_SQUAD", "HUD_ARMORY_CONSUMABLES"]
## Display order of the sections inside the All tab.
const SECTION_ORDER: Array[int] = [Tab.CORE, Tab.FRAME, Tab.CHAMBER, Tab.SQUAD, Tab.CONSUMABLES]

var catalog: ArmoryCatalogDef
var rules: EconomyRulesDef
var builds: RecommendedBuildsDef
var hero_id: StringName = &""
var weapon: WeaponDef
var progress: SnapshotData.ProgressState


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
		ArmoryItemDef.Socket.FRAME:
			return Tab.FRAME
		ArmoryItemDef.Socket.CHAMBER:
			return Tab.CHAMBER
	return Tab.ALL


## Catalog indices shown for `tab` and the search `query` (case-insensitive
## substring of name or effect text; empty = no filter), in section order.
func rows(tab: int, query: String = "") -> Array[int]:
	var out: Array[int] = []
	if catalog == null:
		return out
	var q := query.strip_edges().to_lower()
	for sec in SECTION_ORDER:
		if tab != Tab.ALL and tab != sec:
			continue
		for i in catalog.items.size():
			var it := catalog.items[i]
			if it == null or tab_of(it) != sec:
				continue
			if q != "" and not (it.display_name.to_lower().contains(q) or it.effect_text.to_lower().contains(q)):
				continue
			out.append(i)
	return out


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


# --- Recommended build ----------------------------------------------------------------

func build() -> RecommendedBuildDef:
	return builds.for_hero(hero_id) if builds != null else null


## True once step `step` of the build is satisfied by what the hero owns.
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


## First unsatisfied step whose item fits the weapon, or -1 (complete / no build).
func next_step() -> int:
	var b := build()
	if b == null or progress == null:
		return -1
	for s in b.steps():
		var index := catalog.index_of(b.item_at(s))
		if index >= 0 and fits(index) and not step_done(s):
			return s
	return -1


## Catalog index of the next recommended item (-1 if none).
func recommended_next() -> int:
	var s := next_step()
	return catalog.index_of(build().item_at(s)) if s >= 0 else -1


## Tier / count the next step aims for (0 if none).
func recommended_target() -> int:
	var s := next_step()
	return build().target_at(s) if s >= 0 else 0


## True when `index` appears in a still-open step of the build.
func is_recommended(index: int) -> bool:
	var b := build()
	if b == null or progress == null:
		return false
	for s in b.steps():
		if catalog.index_of(b.item_at(s)) == index and not step_done(s):
			return true
	return false


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
