class_name ModelCatalog
extends RefCounted
## Data hook: resolves HeroDef / WeaponDef / WardlingDef to a procedural model
## key. A def's `model_id` wins; otherwise the key is derived from its `id`
## ("hero_vesper_loom" -> vesper, "weapon_breakline_ar7" -> breakline). When
## real art lands, a def can name a scene instead (`model_scene`) and the
## views instance that rather than calling the builders.

const HERO_KEYS: Array[StringName] = [&"vesper", &"sable", &"juniper", &"ryker", &"brannoc", &"liora", &"hex"]
const WEAPON_KEYS: Array[StringName] = [&"threadcaster", &"whisperfang", &"tackhammer", &"breakline", &"ironmaw",
	&"halo_repeater", &"glitchcaster"]
const WARDLING_KEYS: Array[StringName] = [&"picket"]
## Each hero's signature weapon (heroes.md §3, weapons-and-mods.md §3.3).
const HERO_WEAPON := {
	&"vesper": &"threadcaster", &"sable": &"whisperfang", &"juniper": &"tackhammer", &"ryker": &"breakline",
	&"brannoc": &"ironmaw", &"liora": &"halo_repeater", &"hex": &"glitchcaster",
}
const HERO_NAMES := {
	&"vesper": "Vesper Loom", &"sable": "Sable", &"juniper": "Juniper Quill", &"ryker": "Ryker Vance",
	&"brannoc": "Brannoc", &"liora": "Liora Vale", &"hex": "Hex",
}
## Budgets (art bible §10.6): hero 3P LOD0 <= 30k tris (incl. its 3P gun);
## viewmodel weapon <= 20k; 3P weapon <= 6k; Wardling <= 4k. Node budgets are
## ours (draw calls: MeshInstances per instance, before the outline pass).
const HERO_TRI_BUDGET: int = 30000
const WEAPON_FP_TRI_BUDGET: int = 20000
const WEAPON_TP_TRI_BUDGET: int = 6000
const WARDLING_TRI_BUDGET: int = 4000
const HERO_MESH_BUDGET: int = 24
const WEAPON_MESH_BUDGET: int = 10
const WARDLING_MESH_BUDGET: int = 8


static var _enabled: int = -1


## False when launched with `-- --greybox-models` (debug A/B: perf baseline
## and readability comparison against the old greybox views).
static func models_enabled() -> bool:
	if _enabled < 0:
		_enabled = 0 if OS.get_cmdline_user_args().has("--greybox-models") else 1
	return _enabled == 1


static func hero_key(def: HeroDef) -> StringName:
	if def == null:
		return &""
	return _match(def.model_id if def.model_id != &"" else def.id, HERO_KEYS)


static func weapon_key(def: WeaponDef) -> StringName:
	if def == null:
		return &""
	return _match(def.model_id if def.model_id != &"" else def.id, WEAPON_KEYS)


static func wardling_key(def: WardlingDef) -> StringName:
	if def == null:
		return &"picket"
	var k := _match(def.model_id if def.model_id != &"" else def.id, WARDLING_KEYS)
	return k if k != &"" else &"picket"


## Key from a free id ("hero_ryker_vance", "ryker", "Breakline AR-7"...).
static func hero_key_from_id(id: String) -> StringName:
	return _match(StringName(id), HERO_KEYS)


static func weapon_key_from_id(id: String) -> StringName:
	return _match(StringName(id), WEAPON_KEYS)


static func _match(id: StringName, keys: Array[StringName]) -> StringName:
	var s := String(id).to_lower().replace("-", "_").replace(" ", "_")
	for k in keys:
		if s == String(k) or s.contains(String(k)):
			return k
	return &""
