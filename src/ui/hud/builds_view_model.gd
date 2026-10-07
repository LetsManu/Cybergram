class_name BuildsViewModel
extends RefCounted
## Logic of the Armory "My builds" tab (docs/armory.md "Custom builds"): the
## hero's default guide plus the player's private builds from
## CustomBuildStore, which one the Recommended tab follows, and the editing
## actions (new from the default guide, duplicate, delete with a confirm
## press, add / remove the focused item, copy / paste a build string).
## Pure: ArmoryPanel draws it and calls these on input. Every change is saved
## at once to `path` ("" = never written, for tests).

## Entry 0 is always the default guide (id "").
var store: CustomBuildStore
var hero_id: StringName = &""
var catalog: ArmoryCatalogDef
var weapon: WeaponDef
var defaults: RecommendedBuildsDef
var path: String = CustomBuildStore.DEFAULT_PATH
## Build id waiting for a second delete press ("" = none).
var confirm_delete: String = ""
## Bumped on every change; active_guide() is rebuilt only when it moves.
var revision: int = 0
var _guide: RecommendedBuildDef
var _guide_key: String = "-"


func _init(store_: CustomBuildStore = null, path_: String = CustomBuildStore.DEFAULT_PATH) -> void:
	store = store_ if store_ != null else CustomBuildStore.new()
	path = path_


## Loads the store from `path` (a damaged file is left alone: empty store).
func load_store() -> void:
	if path != "" and not store.load_file(path):
		store = CustomBuildStore.new()


func setup(hero: StringName, cat: ArmoryCatalogDef, weapon_: WeaponDef, defaults_: RecommendedBuildsDef) -> void:
	if hero != hero_id:
		confirm_delete = ""
	hero_id = hero
	catalog = cat
	weapon = weapon_
	defaults = defaults_


## [{id, name, steps, warnings, active}], the default guide first.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var active := active_id()
	var d := defaults.for_hero(hero_id) if defaults != null else null
	out.append({"id": "", "name": d.display_name if d != null else "", "steps": d.nodes.size() if d != null else 0,
		"warnings": PackedStringArray(), "active": active == ""})
	for b in store.for_hero(hero_id):
		out.append({"id": b["id"], "name": b["name"], "steps": (b["steps"] as Array).size(),
			"warnings": CustomBuildStore.warnings(b, catalog, weapon), "active": active == b["id"]})
	return out


func active_id() -> String:
	return String(store.selected.get(String(hero_id), ""))


## The guide the Recommended tab should follow (null = the default guide).
func active_guide() -> RecommendedBuildDef:
	var key := "%s:%s:%d" % [hero_id, active_id(), revision]
	if key != _guide_key:
		_guide_key = key
		_guide = store.selected_guide(hero_id)
	return _guide


## The build under entry `i` ({} for the default guide or out of range).
func build_at(i: int) -> Dictionary:
	var e := entries()
	return store.find(String(e[i]["id"])) if i > 0 and i < e.size() else {}


func use(i: int) -> bool:
	var e := entries()
	if i < 0 or i >= e.size():
		return false
	var ok := store.select(hero_id, String(e[i]["id"]))
	_save()
	return ok


## A new build seeded with the default guide's core path; returns its entry.
func new_from_default() -> int:
	var id := store.create(hero_id, _next_name())
	if id == "":
		return -1
	store.reset_to_default(id, defaults.for_hero(hero_id) if defaults != null else null)
	_save()
	return _entry_of(id)


func duplicate_entry(i: int) -> int:
	var b := build_at(i)
	if b.is_empty():
		return -1
	var id := store.duplicate_build(String(b["id"]))
	_save()
	return _entry_of(id)


## First press arms, a second press on the same build deletes it. Returns
## true once deleted.
func delete_entry(i: int) -> bool:
	var b := build_at(i)
	if b.is_empty():
		confirm_delete = ""
		return false
	var id := String(b["id"])
	if confirm_delete != id:
		confirm_delete = id
		return false
	confirm_delete = ""
	var ok := store.remove(id)
	_save()
	return ok


## Adds catalog item `index` at `target` to the active custom build (none
## active: a new build is made from the default guide first). Returns the
## step count, or -1.
func add_item(index: int, target: int) -> int:
	var it := catalog.at(index) if catalog != null else null
	if it == null:
		return -1
	var id := active_id()
	if id == "":
		var e := new_from_default()
		if e < 0:
			return -1
		id = String(entries()[e]["id"])
		store.select(hero_id, id)
	var section := _section_of(it)
	if not store.add_step(id, it.id, target, section):
		return -1
	_save()
	return (store.find(id)["steps"] as Array).size()


## Removes the last step of the active custom build that buys catalog item `index`.
func remove_item(index: int) -> bool:
	var it := catalog.at(index) if catalog != null else null
	var b := store.find(active_id())
	if it == null or b.is_empty():
		return false
	var steps: Array = b["steps"]
	for k in range(steps.size() - 1, -1, -1):
		if String(steps[k]["item"]) == String(it.id):
			store.remove_step(String(b["id"]), k)
			_save()
			return true
	return false


func export_entry(i: int) -> String:
	var b := build_at(i)
	return store.export_string(String(b["id"])) if not b.is_empty() else ""


## Pastes a build string; only a build for this hero is accepted. Returns its entry or -1.
func import_text(text: String) -> int:
	var id := store.import_string(text)
	if id == "":
		return -1
	if store.find(id)["hero"] != String(hero_id):
		store.remove(id)
		return -1
	_save()
	return _entry_of(id)


func _entry_of(id: String) -> int:
	var e := entries()
	for i in e.size():
		if e[i]["id"] == id:
			return i
	return -1


func _next_name() -> String:
	return tr("HUD_BUILDS_NEW_NAME").replace("{n}", str(store.for_hero(hero_id).size() + 1))


static func _section_of(it: ArmoryItemDef) -> int:
	match it.kind:
		ArmoryItemDef.Kind.CONSUMABLE:
			return BuildNodeDef.Section.CONSUMABLE
		ArmoryItemDef.Kind.SQUAD:
			return BuildNodeDef.Section.SQUAD
	return BuildNodeDef.Section.CORE


func _save() -> void:
	revision += 1
	if path != "":
		store.save_file(path)
