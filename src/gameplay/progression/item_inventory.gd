class_name ItemInventory
extends RefCounted
## One hero's Armory v2 equipment (items-and-armory.md §3.1, §3.4): the gun's
## Core / Barrel / Frame sockets, the Chamber (Ammo Type + Ammo Mod) and the
## open item slots, plus the per-visit transaction log behind undo (§3.6
## rule 8). Squad upgrades and Med-Packs stay on HeroProgress (own row).
##
## Every owned instance has a serial, so undo knows exactly which part a later
## purchase used up. Only the first copy of an item id in the open slots is
## active (gives stats); later copies are spares (§3.4 rule 3).

## Locations: the three gun sockets use ArmoryItemDef.Socket values.
const LOC_CORE: int = ArmoryItemDef.Socket.CORE
const LOC_BARREL: int = ArmoryItemDef.Socket.BARREL
const LOC_FRAME: int = ArmoryItemDef.Socket.FRAME
const LOC_AMMO: int = ArmoryItemDef.Socket.CHAMBER
const LOC_MOD: int = 5
## Squad upgrades / Med-Packs (HeroProgress row; used by undo only).
const LOC_ROW: int = 6
## Open slot i is LOC_SLOT + i.
const LOC_SLOT: int = 16
const SOCKET_LOCS: Array[int] = [LOC_CORE, LOC_BARREL, LOC_FRAME, LOC_AMMO, LOC_MOD]


class Entry:
	var index: int = -1
	var serial: int = 0

	func _init(index_: int = -1, serial_: int = 0) -> void:
		index = index_
		serial = serial_


## Socket / Chamber location -> Entry.
var sockets: Dictionary = {}
## Open slots in order (Entry).
var slots: Array = []
## Per-visit transaction log, oldest first: {op, index, lumen, placed: Entry, at: int,
## taken: [[loc, Entry]], sold: [[loc, Entry]]}. op is &"buy", &"sell" or &"row".
var txns: Array = []
var _serial: int = 0


func new_entry(index: int) -> Entry:
	_serial += 1
	return Entry.new(index, _serial)


func at(loc: int) -> Entry:
	if loc >= LOC_SLOT:
		var i := loc - LOC_SLOT
		return slots[i] if i < slots.size() else null
	return sockets.get(loc)


## Every owned instance as a RecipeMath pool: {index, loc, key, entry}.
func pool() -> Array:
	var out: Array = []
	for loc in SOCKET_LOCS:
		var e: Entry = sockets.get(loc)
		if e != null:
			out.append({"index": e.index, "loc": loc, "key": e.serial, "entry": e})
	for i in slots.size():
		var e: Entry = slots[i]
		out.append({"index": e.index, "loc": LOC_SLOT + i, "key": e.serial, "entry": e})
	return out


## Location of `e` (or -1).
func loc_of(e: Entry) -> int:
	for loc in sockets:
		if sockets[loc] == e:
			return loc
	var i := slots.find(e)
	return LOC_SLOT + i if i >= 0 else -1


## Removes `e` from wherever it is; returns its old location (or -1).
func remove(e: Entry) -> int:
	var loc := loc_of(e)
	if loc < 0:
		return -1
	if loc >= LOC_SLOT:
		slots.remove_at(loc - LOC_SLOT)
	else:
		sockets.erase(loc)
	return loc


## Puts `e` at `loc` (an open-slot location appends, a socket replaces).
func place(e: Entry, loc: int) -> void:
	if loc >= LOC_SLOT:
		slots.insert(clampi(loc - LOC_SLOT, 0, slots.size()), e)
	else:
		sockets[loc] = e


## True if open slot `i` holds the first copy of its item id (gives stats).
func is_active_slot(i: int) -> bool:
	if i < 0 or i >= slots.size():
		return false
	var idx: int = slots[i].index
	for k in i:
		if slots[k].index == idx:
			return false
	return true


## Catalog indices that give stats now: sockets, Chamber and active open slots.
func active_indices() -> Array[int]:
	var out: Array[int] = []
	for loc in SOCKET_LOCS:
		var e: Entry = sockets.get(loc)
		if e != null:
			out.append(e.index)
	for i in slots.size():
		if is_active_slot(i):
			out.append(slots[i].index)
	return out


func owns(index: int) -> bool:
	for p in pool():
		if int(p["index"]) == index:
			return true
	return false


func signature_count(cat: ArmoryCatalogDef) -> int:
	var n := 0
	for p in pool():
		var it := cat.at(int(p["index"]))
		if it != null and it.tier == ArmoryItemDef.Tier.SIGNATURE:
			n += 1
	return n


## Catalog index at `loc` (-1 = empty).
func index_at(loc: int) -> int:
	var e := at(loc)
	return e.index if e != null else -1


## The visit is over (left the Armory zone or died): no more undo.
func end_visit() -> void:
	txns.clear()


## Index into `txns` of the transaction that placed the entry now at `loc`
## (-1 = none this visit).
func txn_for(loc: int) -> int:
	var e := at(loc)
	if e == null:
		return -1
	for k in range(txns.size() - 1, -1, -1):
		var t: Dictionary = txns[k]
		if t.get("placed") == e:
			return k
	return -1


## True if a transaction after `k` used up, sold or moved what `k` placed.
func is_blocked(k: int) -> bool:
	var placed = txns[k].get("placed")
	if placed == null:
		return false
	for j in range(k + 1, txns.size()):
		var t: Dictionary = txns[j]
		for pair in t.get("taken", []):
			if pair[1] == placed:
				return true
		for pair in t.get("sold", []):
			if pair[1] == placed:
				return true
	return false
