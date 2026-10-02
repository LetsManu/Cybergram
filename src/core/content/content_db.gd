class_name ContentDB
extends RefCounted
## Stable net indices for content ids (architecture.md §3 / §5 "Ids", ADR-0003
## §5). Per content type, the ids (file stems under assets/data, ADR-0003 §1:
## stem = id) are sorted; index 0 means "none" and index i >= 1 is the
## (i-1)-th sorted id. Both sides build the same table from the same content,
## so an index is safe on the wire (u16).
##
## M1 scope: indexes the types the snapshot needs (heroes). The handshake
## content hash and get_def() of the full ADR-0003 ContentDB are later work.
## Core layer: it knows directories and ids, never gameplay classes.
##
## Example:
##   var db := ContentDB.shared()
##   var i := db.index_of(ContentDB.HERO, &"hero_brannoc")   # e.g. 1
##   db.id_at(ContentDB.HERO, i)                             # &"hero_brannoc"
##   var fixture := ContentDB.from_ids({ContentDB.HERO: [&"hero_a", &"hero_b"]})

const HERO: StringName = &"hero"
## Content type -> [directory, file stem prefix].
const SOURCES := {
	HERO: ["res://assets/data/heroes", "hero_"],
}
const NONE: int = 0

static var _shared: ContentDB

## type -> Array[StringName] (sorted ids).
var _ids: Dictionary = {}
## type -> {id: index}.
var _index: Dictionary = {}


## The project's content, scanned once (read-only afterwards).
static func shared() -> ContentDB:
	if _shared == null:
		_shared = ContentDB.new()
		for type in SOURCES:
			_shared._set_ids(type, _scan(SOURCES[type][0], SOURCES[type][1]))
	return _shared


## Fixture DB from explicit ids per type (tests); ids are sorted like a scan.
static func from_ids(ids_by_type: Dictionary) -> ContentDB:
	var db := ContentDB.new()
	for type in ids_by_type:
		var ids: Array[StringName] = []
		for id in ids_by_type[type]:
			ids.append(StringName(id))
		db._set_ids(type, ids)
	return db


## Stable index of `id` (1-based), or NONE if unknown.
func index_of(type: StringName, id: StringName) -> int:
	var m: Dictionary = _index.get(type, {})
	return int(m.get(id, NONE))


## Id at `index`, or &"" for NONE / out of range.
func id_at(type: StringName, index: int) -> StringName:
	var ids: Array = _ids.get(type, [])
	if index < 1 or index > ids.size():
		return &""
	return ids[index - 1]


## Number of ids of `type`.
func count(type: StringName) -> int:
	return (_ids.get(type, []) as Array).size()


func _set_ids(type: StringName, ids: Array[StringName]) -> void:
	var sorted := ids.duplicate()
	sorted.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var uniq: Array[StringName] = []
	for id in sorted:
		if uniq.is_empty() or uniq[-1] != id:
			uniq.append(id)
	_ids[type] = uniq
	var m := {}
	for i in uniq.size():
		m[uniq[i]] = i + 1
	_index[type] = m


## File stems `<prefix>*.tres` in `dir`. ResourceLoader.list_directory (4.4+)
## sees through export remaps; a stray .remap / .res suffix is stripped anyway.
static func _scan(dir: String, prefix: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for f in ResourceLoader.list_directory(dir):
		var name := String(f).trim_suffix(".remap")
		if not name.begins_with(prefix):
			continue
		if name.ends_with(".tres"):
			out.append(StringName(name.trim_suffix(".tres")))
		elif name.ends_with(".res"):
			out.append(StringName(name.trim_suffix(".res")))
	return out
