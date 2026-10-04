class_name HeroCatalog
extends RefCounted
## Data-driven hero list for the menus (design/ux/lobby-and-social.md §2.2):
## every assets/data/heroes/hero_*.tres that ContentDB indexes, with its net
## index, display name (tr("HUD_HERO_NAME_<STEM>") when that key exists, else
## HeroDef.display_name) and badge colours (ModelPalette signature). A hero
## added as data appears in the main menu and the lobby with no code change.
##
## Example:
##   for h in HeroCatalog.entries(): print(h.index, " ", h.name)
##   HeroCatalog.find_stem("brannoc").index

## Cached entries (the content does not change at runtime).
static var _cache: Array = []


## Array of {index: int, stem: String ("vesper_loom"), name: String,
## color: Color, color2: Color, initials: String}, sorted by name.
static func entries() -> Array:
	if not _cache.is_empty():
		return _cache
	var db := ContentDB.shared()
	var out: Array = []
	for i in range(1, db.count(ContentDB.HERO) + 1):
		var id := String(db.id_at(ContentDB.HERO, i))
		var path := "%s/%s.tres" % [ContentDB.SOURCES[ContentDB.HERO][0], id]
		var def := load(path) as HeroDef if ResourceLoader.exists(path) else null
		var stem := id.trim_prefix(String(ContentDB.SOURCES[ContentDB.HERO][1]))
		var key := ModelCatalog.hero_key(def) if def != null else &""
		out.append({"index": i, "stem": stem, "name": display_name(stem, def),
			"color": ModelPalette.signature(key), "color2": ModelPalette.secondary(key),
			"initials": initials(display_name(stem, def))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name) < String(b.name))
	_cache = out
	return out


## Entry with ContentDB index `index`, or {} (NONE / unknown).
static func find_index(index: int) -> Dictionary:
	for h in entries():
		if h.index == index:
			return h
	return {}


## Entry for an id stem ("brannoc"), or {}.
static func find_stem(stem: String) -> Dictionary:
	for h in entries():
		if h.stem == stem:
			return h
	return {}


## Localised display name of a hero.
static func display_name(stem: String, def: HeroDef) -> String:
	var key := "HUD_HERO_NAME_" + stem.to_upper()
	var t := TranslationServer.translate(key)
	if t != key and t != "":
		return t
	if def != null and def.display_name != "":
		return def.display_name
	return stem.capitalize()


## Up to two initials ("Vesper Loom" -> "VL", "Hex" -> "HE").
static func initials(name: String) -> String:
	var words := name.split(" ", false)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	return name.left(2).to_upper()
