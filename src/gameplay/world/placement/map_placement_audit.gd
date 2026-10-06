class_name MapPlacementAudit
extends RefCounted
## Collects every placed world object of a map as PlacementValidator items
## (world props and floor decals today; objective dressing as it lands) and
## validates them against the map's collision (docs/placement.md).
## Used by tools/validate_placement.gd (report) and the integration test that
## gates CI.
##
## Waivers: WAIVERS maps an id fragment (the "@x,y,z" position works) to the
## reason; keep it short and reviewed (each entry is a known, accepted exception).

const RULES_PATH := "res://assets/data/world/placement_rules.tres"
## Item kinds that face the player and need open floor in front.
const FACES_WALKABLE: Array[StringName] = [&"kiosk", &"vending", &"terminal", &"holo_sign"]
## Kit pieces that are sheets lying on the floor.
const FLAT: Array[StringName] = [&"puddle"]
## id fragment -> reason.
const WAIVERS := {
	"cover_box#12@-4,2,-58": "map layout: cover box overhangs a step edge (move inward: docs/polish-backlog.md)",
	"cover_box#19@-4,2,-362": "mirror of the -58 step-edge cover box (docs/polish-backlog.md)",
	"@-42,1,-98": "map layout: cover box overhangs a ledge by ~0.6 m (docs/polish-backlog.md)",
	"@42,1,-98": "mirror of the -42,-98 ledge cover box (docs/polish-backlog.md)",
	"@-42,1,-322": "mirror of the -42,-98 ledge cover box (docs/polish-backlog.md)",
	"@42,1,-322": "mirror of the -42,-98 ledge cover box (docs/polish-backlog.md)",
}


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
		var it := item_of(pl, bounds[pl.piece], "%s#%d@%s" % [pl.piece, n, _at(pl.xform.origin)])
		it.waiver = _waiver(it.id)
		out.append(it)
		n += 1
	return out


## The validator item for a world prop placement (`box` = the piece's unscaled bounds).
static func item_of(pl: WorldProps.Placement, box: AABB, id: String = "") -> PlacementValidator.Item:
	var kind: StringName = &"roof" if pl.kind == &"roof" else &"wall"
	if FLAT.has(pl.piece):
		kind = &"flat"
	var it := PlacementValidator.Item.new(id if id != "" else String(pl.piece), kind, pl.xform, box)
	it.faces_walkable = FACES_WALKABLE.has(pl.piece)
	if pl.foot.size() == 4:
		it.foot = pl.foot
	return it


## Items for the floor decals planned on `md`; `ground` = Callable(Vector3) -> {pos, normal}.
static func decal_items(md: MapDef, ground: Callable, accept: Callable = Callable()) -> Array:
	var def := load(WorldDecals.DEF_PATH) as WorldDecalsDef
	var out: Array = []
	var n := 0
	for p: WorldDecals.Placement in WorldDecals.plan(md, def):
		var hit: Dictionary = ground.call(p.pos)
		if hit.is_empty() or (accept.is_valid() and not accept.call(p, hit)):
			continue
		var it := WorldDecals.decal_item(p, hit, def, "decal_%s#%d@%s" % [p.cell, n, _at(hit.pos)])
		it.waiver = _waiver(it.id)
		out.append(it)
		n += 1
	return out


## Items for the cover boxes CoverDressing dresses (`map_root` = the map, in
## the tree): one per box, since its crates stand inside the box's own
## collision; the box's base must be grounded and supported like any prop.
static func cover_items(map_root: Node3D) -> Array:
	var out: Array = []
	var bounds := WorldProps.bounds_of(WorldProps.piece_meshes(CoverDressing.KIT_KEY))
	if not bounds.has(&"crate"):
		return out
	var n := 0
	for mi: MeshInstance3D in map_root.find_children("*", "MeshInstance3D", true, false):
		if not CoverDressing.is_cover(mi):
			continue
		var size := (mi.mesh as BoxMesh).size
		var f := CoverDressing.fill(size, bounds)
		if f.is_empty() or not f.all(func(x: Array) -> bool: return CoverDressing.stretch_ok(x[1])):
			continue
		var it := PlacementValidator.Item.new("cover_box#%d@%s" % [n, _at(mi.global_position)], &"cover",
			mi.global_transform, AABB(-size * 0.5, size))
		it.waiver = _waiver(it.id)
		out.append(it)
		n += 1
	return out


## Items for the objective dressing placed through PlacementKit at runtime:
## the Forward Beacon pads (two per Mid, ForwardBeaconView.place). Flat discs,
## so grounded + supported apply; they belong inside the Mid zone, so the props'
## keep-out zones do not.
static func objective_items(md: MapDef, space: PhysicsDirectSpaceState3D) -> Array:
	var out: Array = []
	var tol := rules().ground_tol_m
	for lane: LaneDef in md.lanes:
		for d: HardpointDef in lane.hardpoints:
			for sp: Array in ForwardBeaconView.spots(md, d):
				var xf := ForwardBeaconView.place(space, d.position, sp[1], tol)
				var it := PlacementValidator.Item.new("forward_beacon_%s_%d@%s" % [d.id, sp[0], _at(xf.origin)], &"flat",
					xf, ForwardBeaconView.pad_box())
				it.foot = ForwardBeaconView.pad_foot(xf, ForwardBeaconView.foot_radius())
				it.waiver = _waiver(it.id)
				out.append(it)
	return out


## Validates props + decals + objective dressing; returns [items, report].
static func run(md: MapDef, space: PhysicsDirectSpaceState3D, ground: Callable, map_root: Node3D = null) -> Array:
	var def := load(WorldProps.DEF_PATH) as WorldPropsDef
	var corridors := WorldProps.lane_corridors(md)
	var v := PlacementValidator.new(rules())
	v.keep_out = func(p: Vector3, r: float) -> String: return WorldProps.excluded(md, def, p, r, corridors)
	# the decals the game builds: the runtime filter applied (WorldDecals._ready)
	var items := prop_items(md, space) + decal_items(md, ground,
		WorldDecals.plausible_filter(space, load(WorldDecals.DEF_PATH) as WorldDecalsDef))
	if map_root != null:
		items += cover_items(map_root)
	var report: Array = v.validate(space, items)
	var objectives := objective_items(md, space)
	report.append_array(PlacementValidator.new(rules()).validate(space, objectives))
	return [items + objectives, report]


static func _waiver(id: String) -> String:
	for k: String in WAIVERS:
		if id.contains(k) and (not k.begins_with("@") or id.ends_with(k)):
			return WAIVERS[k]
	return ""


static func _at(p: Vector3) -> String:
	return "%.0f,%.0f,%.0f" % [p.x, p.y, p.z]
