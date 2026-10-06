class_name MapPlacementAudit
extends RefCounted
## Collects every placed world object of a map as PlacementValidator items
## (world props and floor decals today; objective dressing as it lands) and
## validates them against the map's collision (docs/placement.md).
## Used by tools/validate_placement.gd (report) and the integration test that
## gates CI.
##
## Waivers: WAIVERS maps an item id prefix to the reason; keep it short and
## reviewed (each entry is a known, accepted exception).

const RULES_PATH := "res://assets/data/world/placement_rules.tres"
## Item kinds that face the player and need open floor in front.
const FACES_WALKABLE: Array[StringName] = [&"kiosk", &"vending", &"terminal", &"holo_sign"]
## Kit pieces that are sheets lying on the floor.
const FLAT: Array[StringName] = [&"puddle"]
## id prefix -> reason.
const WAIVERS := {}


## Rules from RULES_PATH (defaults when absent).
static func rules() -> PlacementRulesDef:
	if ResourceLoader.exists(RULES_PATH):
		return load(RULES_PATH) as PlacementRulesDef
	return PlacementRulesDef.new()


## Items for the world props placed on `md` (needs the map's collision in `space`).
static func prop_items(md: MapDef, space: PhysicsDirectSpaceState3D) -> Array:
	var def := load(WorldProps.DEF_PATH) as WorldPropsDef
	var bounds := WorldProps.bounds_of(WorldProps.piece_meshes(def.model_key))
	var out: Array = []
	var n := 0
	for pl: WorldProps.Placement in WorldProps.place(md, def, space, bounds):
		var kind: StringName = &"roof" if pl.kind == &"roof" else &"wall"
		if FLAT.has(pl.piece):
			kind = &"flat"
		var it := PlacementValidator.Item.new("%s#%d@%s" % [pl.piece, n, _at(pl.xform.origin)], kind, pl.xform, bounds[pl.piece])
		if pl.foot.size() == 4:
			it.foot = pl.foot
		it.faces_walkable = FACES_WALKABLE.has(pl.piece)
		it.waiver = _waiver(it.id)
		out.append(it)
		n += 1
	return out


## Items for the floor decals planned on `md`; `ground` = Callable(Vector3) -> {pos, normal}.
static func decal_items(md: MapDef, ground: Callable) -> Array:
	var def := load(WorldDecals.DEF_PATH) as WorldDecalsDef
	var out: Array = []
	var n := 0
	for p: WorldDecals.Placement in WorldDecals.plan(md, def):
		var hit: Dictionary = ground.call(p.pos)
		if hit.is_empty():
			continue
		var d := WorldDecals.make_decal_transform(p, hit.pos, hit.normal)
		var box := AABB(Vector3(-p.size.x, -def.box_height_m, -p.size.y) * 0.5, Vector3(p.size.x, def.box_height_m, p.size.y))
		var it := PlacementValidator.Item.new("decal_%s#%d@%s" % [p.cell, n, _at(hit.pos)], &"decal", d, box)
		it.normal_fade = def.normal_fade
		it.waiver = _waiver(it.id)
		out.append(it)
		n += 1
	return out


## Validates props + decals; returns [items, report].
static func run(md: MapDef, space: PhysicsDirectSpaceState3D, ground: Callable) -> Array:
	var def := load(WorldProps.DEF_PATH) as WorldPropsDef
	var corridors := WorldProps.lane_corridors(md)
	var v := PlacementValidator.new(rules())
	v.keep_out = func(p: Vector3, r: float) -> String: return WorldProps.excluded(md, def, p, r, corridors)
	var items := prop_items(md, space) + decal_items(md, ground)
	return [items, v.validate(space, items)]


static func _waiver(id: String) -> String:
	for k: String in WAIVERS:
		if id.begins_with(k):
			return WAIVERS[k]
	return ""


static func _at(p: Vector3) -> String:
	return "%.0f,%.0f,%.0f" % [p.x, p.y, p.z]
