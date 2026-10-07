class_name CustomBuildStore
extends RefCounted
## Private custom Armory builds, kept on this PC only (owner decision
## 2026-10-06: `user://builds.json`, never sent to a server). A custom build is
## an ordered list of steps ("own item X at tier / count N", in a section, with
## optional alternatives and a note); `to_build_def()` turns it into a guide
## the shared BuildAdvisor reads, so custom and default builds recommend the
## same way. See docs/armory.md "Custom builds".
##
## File format (versioned JSON):
##   {"version": 1,
##    "selected": {"<hero id>": "<build id>"},
##    "builds": [{"id", "hero", "name", "notes",
##                "steps": [{"item", "target", "section", "alts": [...], "note"}]}]}
## Unknown or invalid references are kept and reported by `warnings()`: a
## build is never silently changed because an item was renamed or removed.

const DEFAULT_PATH := "user://builds.json"
const VERSION: int = 1
## Prefix of an exported build string (import refuses anything else).
const EXPORT_PREFIX := "CGB1:"
const MAX_BUILDS: int = 64
const MAX_STEPS: int = 40
const MAX_TEXT: int = 200

var builds: Array[Dictionary] = []
## hero id (String) -> build id (String); absent = the default guide.
var selected: Dictionary = {}
var _next_id: int = 1


# --- persistence ------------------------------------------------------------------

## Loads `path`. A missing file is an empty store; a damaged file is left on
## disk untouched (renamed copy kept by the caller if wanted) and returns false.
func load_file(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var text := FileAccess.get_file_as_string(path)
	return from_json(text)


func save_file(path: String = DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json())
	f.close()
	return true


func to_json() -> String:
	return JSON.stringify({"version": VERSION, "selected": selected, "builds": builds}, "\t")


## Replaces the store with `text`. False (and the store unchanged) when the
## text is not a v1 build file.
func from_json(text: String) -> bool:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		return false
	var list = data.get("builds", [])
	if typeof(list) != TYPE_ARRAY:
		return false
	var out: Array[Dictionary] = []
	for b in list:
		var clean := _sanitize(b)
		if not clean.is_empty() and out.size() < MAX_BUILDS:
			out.append(clean)
	builds = out
	selected = {}
	var sel = data.get("selected", {})
	if typeof(sel) == TYPE_DICTIONARY:
		for k in sel:
			if not find(String(sel[k])).is_empty():
				selected[String(k)] = String(sel[k])
	_next_id = 1
	for b in builds:
		var n := String(b["id"]).trim_prefix("b").to_int()
		_next_id = maxi(_next_id, n + 1)
	return true


# --- editing ------------------------------------------------------------------------

## A new empty build for `hero`; returns its id ("" when the store is full).
func create(hero: StringName, name: String) -> String:
	if builds.size() >= MAX_BUILDS:
		return ""
	var b := {"id": _new_id(), "hero": String(hero), "name": _text(name), "notes": "", "steps": []}
	builds.append(b)
	return b["id"]


func duplicate_build(id: String) -> String:
	var b := find(id)
	if b.is_empty() or builds.size() >= MAX_BUILDS:
		return ""
	var c: Dictionary = b.duplicate(true)
	c["id"] = _new_id()
	c["name"] = _text(String(b["name"]) + " (copy)")
	builds.append(c)
	return c["id"]


func rename(id: String, name: String) -> bool:
	var b := find(id)
	if b.is_empty():
		return false
	b["name"] = _text(name)
	return true


func set_notes(id: String, notes: String) -> bool:
	var b := find(id)
	if b.is_empty():
		return false
	b["notes"] = _text(notes)
	return true


func remove(id: String) -> bool:
	for i in builds.size():
		if builds[i]["id"] == id:
			builds.remove_at(i)
			for k in selected.keys():
				if selected[k] == id:
					selected.erase(k)
			return true
	return false


## Appends a step (or raises the target of the last step on the same item).
func add_step(id: String, item: StringName, target: int = 1, section: int = BuildNodeDef.Section.CORE,
		alts: PackedStringArray = PackedStringArray(), note: String = "") -> bool:
	var b := find(id)
	if b.is_empty():
		return false
	var steps: Array = b["steps"]
	if steps.size() >= MAX_STEPS:
		return false
	steps.append({"item": String(item), "target": clampi(target, 1, 99), "section": clampi(section, 0, 10),
		"alts": Array(alts), "note": _text(note)})
	return true


func remove_step(id: String, step: int) -> bool:
	var b := find(id)
	if b.is_empty() or step < 0 or step >= (b["steps"] as Array).size():
		return false
	(b["steps"] as Array).remove_at(step)
	return true


## Moves step `step` by `delta` (-1 = earlier).
func move_step(id: String, step: int, delta: int) -> bool:
	var b := find(id)
	if b.is_empty():
		return false
	var steps: Array = b["steps"]
	var to := step + delta
	if step < 0 or step >= steps.size() or to < 0 or to >= steps.size():
		return false
	var s = steps[step]
	steps.remove_at(step)
	steps.insert(to, s)
	return true


## Replaces the build's steps with the default guide's core path (nodes
## without conditions, in priority order): "reset to default".
func reset_to_default(id: String, guide: RecommendedBuildDef) -> bool:
	var b := find(id)
	if b.is_empty() or guide == null:
		return false
	var steps: Array = []
	if guide.is_guide():
		var ns: Array = guide.nodes.filter(func(n: BuildNodeDef) -> bool: return n != null and n.conditions.is_empty())
		ns.sort_custom(func(a: BuildNodeDef, c: BuildNodeDef) -> bool: return a.priority > c.priority)
		for n in ns:
			steps.append({"item": String(n.item_id), "target": n.target_or_one(), "section": int(n.section),
				"alts": Array(n.alternatives), "note": ""})
	else:
		for i in guide.steps():
			steps.append({"item": String(guide.item_at(i)), "target": guide.target_at(i),
				"section": BuildNodeDef.Section.CORE, "alts": [], "note": ""})
	b["steps"] = steps.slice(0, MAX_STEPS)
	return true


func select(hero: StringName, id: String) -> bool:
	if id == "":
		selected.erase(String(hero))
		return true
	var b := find(id)
	if b.is_empty() or b["hero"] != String(hero):
		return false
	selected[String(hero)] = id
	return true


# --- reading ------------------------------------------------------------------------

## The build with `id`, or {} (the store's own dictionary: edits stick).
func find(id: String) -> Dictionary:
	for b in builds:
		if b["id"] == id:
			return b
	return {}


func for_hero(hero: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in builds:
		if b["hero"] == String(hero):
			out.append(b)
	return out


## The selected custom build of `hero` as a guide, or null (= use the default).
func selected_guide(hero: StringName) -> RecommendedBuildDef:
	var b := find(String(selected.get(String(hero), "")))
	return to_build_def(b) if not b.is_empty() else null


## A guide the BuildAdvisor reads: one node per step, each requiring the
## step before it (an ordered path), priority falling with the order.
static func to_build_def(b: Dictionary) -> RecommendedBuildDef:
	var g := RecommendedBuildDef.new()
	g.hero_id = StringName(b.get("hero", ""))
	g.display_name = String(b.get("name", ""))
	g.beginner = false
	var steps: Array = b.get("steps", [])
	for i in steps.size():
		var s: Dictionary = steps[i]
		var n := BuildNodeDef.new()
		n.id = StringName("s%d" % i)
		n.item_id = StringName(s.get("item", ""))
		n.target = clampi(int(s.get("target", 1)), 1, 99)
		n.section = clampi(int(s.get("section", BuildNodeDef.Section.CORE)), 0, 10) as BuildNodeDef.Section
		n.priority = maxi(1000 - i * 10, 0)
		n.alternatives = PackedStringArray(s.get("alts", []))
		if i > 0:
			n.requires = PackedStringArray(["s%d" % (i - 1)])
		g.nodes.append(n)
		g.item_ids.append(String(n.item_id))
		g.targets.append(n.target)
	return g


## Human-readable problems of build `b` against `cat` (and the hero's gun
## family when `weapon` is given). Never edits the build.
static func warnings(b: Dictionary, cat: ArmoryCatalogDef, weapon: WeaponDef = null) -> PackedStringArray:
	var out := PackedStringArray()
	var steps: Array = b.get("steps", [])
	if steps.is_empty():
		out.append("build has no steps")
	var st := BuildState.new()
	st.catalog = cat
	st.weapon = weapon
	for i in steps.size():
		var s: Dictionary = steps[i]
		var id := StringName(s.get("item", ""))
		var it := cat.find(id) if cat != null else null
		if it == null:
			out.append("step %d: unknown item %s" % [i + 1, id])
			continue
		if it.disabled:
			out.append("step %d: %s is not sold" % [i + 1, id])
		var cap := it.carry_limit if it.kind == ArmoryItemDef.Kind.CONSUMABLE else it.tiers()
		if int(s.get("target", 1)) > maxi(cap, 1):
			out.append("step %d: %s has no tier / count %d" % [i + 1, id, int(s.get("target", 1))])
		if weapon != null and not st.fits(it):
			out.append("step %d: %s does not fit this gun" % [i + 1, id])
		for a in s.get("alts", []):
			if cat.find(StringName(a)) == null:
				out.append("step %d: unknown alternative %s" % [i + 1, a])
	return out


# --- sharing (copy / paste, no server) --------------------------------------------

## One build as a single-line string the player can paste elsewhere.
func export_string(id: String) -> String:
	var b := find(id)
	if b.is_empty():
		return ""
	var data := {"hero": b["hero"], "name": b["name"], "notes": b["notes"], "steps": b["steps"]}
	return EXPORT_PREFIX + Marshalls.utf8_to_base64(JSON.stringify(data))


## Imports a string from `export_string` as a new build; returns its id or "".
func import_string(text: String) -> String:
	var t := text.strip_edges()
	if not t.begins_with(EXPORT_PREFIX) or builds.size() >= MAX_BUILDS:
		return ""
	var raw := Marshalls.base64_to_utf8(t.trim_prefix(EXPORT_PREFIX))
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	data["id"] = _new_id()
	var clean := _sanitize(data)
	if clean.is_empty():
		return ""
	builds.append(clean)
	return clean["id"]


# --- internals ----------------------------------------------------------------------

func _new_id() -> String:
	var id := "b%d" % _next_id
	_next_id += 1
	return id


static func _text(s: String) -> String:
	return s.strip_edges().left(MAX_TEXT)


## A well-formed copy of `b`, or {} when it is not a build at all. Unknown
## item ids are kept (warnings() reports them).
static func _sanitize(b) -> Dictionary:
	if typeof(b) != TYPE_DICTIONARY or String(b.get("hero", "")) == "" or String(b.get("id", "")) == "":
		return {}
	var steps: Array = []
	var raw = b.get("steps", [])
	if typeof(raw) == TYPE_ARRAY:
		for s in raw:
			if typeof(s) != TYPE_DICTIONARY or String(s.get("item", "")) == "":
				continue
			var alts: Array = []
			var ra = s.get("alts", [])
			if typeof(ra) == TYPE_ARRAY:
				for a in ra:
					alts.append(String(a))
			steps.append({"item": String(s["item"]), "target": clampi(int(s.get("target", 1)), 1, 99),
				"section": clampi(int(s.get("section", BuildNodeDef.Section.CORE)), 0, 10),
				"alts": alts, "note": _text(String(s.get("note", "")))})
			if steps.size() >= MAX_STEPS:
				break
	return {"id": String(b["id"]), "hero": String(b["hero"]), "name": _text(String(b.get("name", ""))),
		"notes": _text(String(b.get("notes", ""))), "steps": steps}
