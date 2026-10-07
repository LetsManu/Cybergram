class_name BuildVisuals
extends RefCounted
## Pure build-to-visual planning for Armory v2 (items-and-armory.md §3.4,
## §3.8). Input: an 11-place build (SnapshotData.EntityState.build or
## ProgressState.inv_items: Core, Barrel, Frame, Ammo Type, Ammo Mod, open
## slots 0..5). Output: which item goes on which gun socket and which body
## anchor sub-position, spares flagged unlit, overflow onto the anchor's
## overflow position, then a back-plate badge: nothing is ever invisible
## (§3.8 rule 3). No nodes here, so it is unit-testable.

## Visual places of a planned body item.
const PLACE_SUB: int = 0
const PLACE_OVERFLOW: int = 1
const PLACE_BADGE: int = 2

## Fallback anchor sub counts (§3.8 table) when the data file lacks one.
const SUB_COUNTS := {&"body_belt": 6, &"body_chest": 2, &"body_shoulders": 2, &"body_back": 2,
	&"body_head": 1, &"body_legs": 2, &"body_forearm": 2}


## One body item placement.
class Placement:
	var slot: int = 0
	var item: ArmoryItemDef = null
	var anchor: StringName = &""
	## PLACE_SUB, PLACE_OVERFLOW or PLACE_BADGE.
	var place: int = PLACE_SUB
	## Sub-position index (PLACE_SUB) or badge index (PLACE_BADGE).
	var index: int = 0
	var spare: bool = false
	## Visual tier 1..3 (Component / Assembly / Signature).
	var tier: int = 1


## Visual tier 1..3 of an item: v22 recipe tier, else 1.
static func visual_tier(item: ArmoryItemDef) -> int:
	if item == null:
		return 0
	return clampi(int(item.tier), 1, 3) if item.is_recipe_item() else 1


## Item at build place `i` (null if empty / unknown).
static func item_at(build: PackedInt32Array, i: int, cat: ArmoryCatalogDef) -> ArmoryItemDef:
	if cat == null or i < 0 or i >= build.size() or build[i] < 0:
		return null
	return cat.at(build[i])


## The 5 gun places (Core, Barrel, Frame, Ammo Type, Ammo Mod) as items (null = empty).
static func gun_items(build: PackedInt32Array, cat: ArmoryCatalogDef) -> Array:
	var out: Array = []
	for i in SnapshotData.EntityState.B_OPEN0:
		out.append(item_at(build, i, cat))
	return out


## DamageMath ammo type loaded in the Chamber (0 = Standard).
static func ammo_type(build: PackedInt32Array, cat: ArmoryCatalogDef) -> int:
	var it := item_at(build, SnapshotData.EntityState.B_AMMO, cat)
	return it.ammo_type if it != null else 0


## DamageMath ammo mod in the Chamber (0 = none).
static func ammo_mod(build: PackedInt32Array, cat: ArmoryCatalogDef) -> int:
	var it := item_at(build, SnapshotData.EntityState.B_MOD, cat)
	return it.ammo_mod if it != null else 0


## Anchor of an open-slot item (weapon components default to the belt).
static func anchor_of(item: ArmoryItemDef) -> StringName:
	if item.body_anchor != &"":
		return item.body_anchor
	return &"body_belt" if item.kind == ArmoryItemDef.Kind.MOUNT else &"body_back"


## Places the open-slot items of `build` on body anchors. `subs` maps an
## anchor to its sub-position count and `has_overflow` to whether it has an
## overflow position (defaults: §3.8 table, every anchor but the belt).
## `fp_only` keeps only the anchors first-person arms show (belt, forearm).
static func plan_body(build: PackedInt32Array, cat: ArmoryCatalogDef, subs: Dictionary = SUB_COUNTS,
		has_overflow: Dictionary = {}, fp_only: bool = false) -> Array[Placement]:
	var used := {}
	var overflow_used := {}
	var badges := 0
	var out: Array[Placement] = []
	for slot in 6:
		var it := item_at(build, SnapshotData.EntityState.B_OPEN0 + slot, cat)
		if it == null:
			continue
		var p := Placement.new()
		p.slot = slot
		p.item = it
		p.anchor = anchor_of(it)
		p.spare = SnapshotData.spare_at(build, slot)
		p.tier = visual_tier(it)
		var n: int = int(subs.get(p.anchor, 1))
		var k: int = int(used.get(p.anchor, 0))
		if k < n:
			p.place = PLACE_SUB
			p.index = k
			used[p.anchor] = k + 1
		elif bool(has_overflow.get(p.anchor, p.anchor != &"body_belt")) and not overflow_used.has(p.anchor):
			p.place = PLACE_OVERFLOW
			overflow_used[p.anchor] = true
		else:
			p.place = PLACE_BADGE
			p.index = badges
			badges += 1
		if fp_only and not (p.anchor == &"body_belt" or p.anchor == &"body_forearm"):
			continue
		out.append(p)
	return out


## Short build summary for icons: [{item, tier, spare, place}] in build order
## (gun places first, then open slots). Empty places are skipped.
static func icon_list(build: PackedInt32Array, cat: ArmoryCatalogDef) -> Array:
	var out: Array = []
	for i in build.size():
		var it := item_at(build, i, cat)
		if it == null:
			continue
		var open := i >= SnapshotData.EntityState.B_OPEN0
		out.append({"item": it, "tier": visual_tier(it), "place": i,
			"spare": open and SnapshotData.spare_at(build, i - SnapshotData.EntityState.B_OPEN0)})
	return out
