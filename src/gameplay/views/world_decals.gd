class_name WorldDecals
extends Node3D
## Client-only floor dressing (docs/assets/floor.md): installs the painted floor
## trim sheet on spatial_env_panel.gdshader and places painted Decal nodes from
## the MapDef: lane arrows pointing toward the enemy side in each team's half and
## along the flank loops (design/art-bible.md §6.2, white, Accent tier), the team
## glyph in each HQ in the team colour, hazard chevrons in the HQ lane gates,
## cracks / scorch / oil around hardpoints, grime, crew tags and puddles along
## the lanes.
##
## Budget (art bible §10.6, <= 48 decals visible in any view): every decal is
## drawn only within WorldDecalsDef.visible_radius() of the camera (Decal distance
## fade). plan() accepts a decal only if, for every point of a check grid, the
## number of decals within visible_radius() + half the grid diagonal stays
## <= max_visible. Any camera position lies within half a grid diagonal of a grid
## point, so no camera position (at any height) can see more than max_visible.
## Candidates are taken in priority order (arrows, glyphs, chevrons, hardpoint
## wear, tags, grime / puddles), so the cap cuts dressing before signage.
##
## Placement is deterministic (WorldDecalsDef.placement_seed). Floor heights come
## from a ground probe (a physics ray by default; tests inject their own).

const SHADER_PATH := "res://assets/shaders/spatial_env_panel.gdshader"
const DEF_PATH := "res://assets/data/world/world_decals.tres"

## Decal roles (priority order of the cap).
enum Role { ARROW, FLANK_ARROW, GLYPH, CHEVRON, WEAR, TAG, GRIME }


## One planned decal (before grounding).
class Placement:
	## Atlas cell name (WorldDecalsDef.cells).
	var cell: String
	var role: int
	## Floor position (y = the MapDef's height; grounding replaces it).
	var pos: Vector3
	## Direction the image's top points to (XZ plane, normalised).
	var forward: Vector3
	## Footprint in metres (x = across, y = along forward).
	var size: Vector2
	var modulate: Color = Color.WHITE
	var emission: float = 0.0
	## MapDef team whose half / HQ this decal belongs to (-1 = neutral).
	var team: int = MapDef.TEAM_NEUTRAL

	func _init(c: String, r: int, p: Vector3, f: Vector3, s: Vector2) -> void:
		cell = c
		role = r
		pos = p
		forward = f
		size = s


var _map: MapDef
var _def: WorldDecalsDef
var _placed := 0

static var _textures := {}
static var _atlas_cache: Image
static var _atlas_cache_path := ""


## New node for `md` (def = null: the shipped WorldDecalsDef). Add it under the map
## root; it installs the floor tiles and places its decals one physics frame later.
static func create(md: MapDef, def: WorldDecalsDef = null) -> WorldDecals:
	var n := WorldDecals.new()
	n.name = "WorldDecals"
	n._map = md
	n._def = def if def != null else load(DEF_PATH) as WorldDecalsDef
	return n


func _ready() -> void:
	if _def == null or _map == null:
		return
	install_floor_tiles(_def)
	# Static bodies of a freshly added map enter the physics space on the next step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	build(plan(_map, _def), _physics_ground, plausible_filter(get_world_3d().direct_space_state, _def))


## Number of Decal nodes this node created.
func placed_count() -> int:
	return _placed


## Sets the floor trim sheet as the default textures of the env panel shader, so
## every material using it (the baked map materials included) shows the tiles.
## Returns false if a map is missing (the shader then keeps the flat v1 look).
static func install_floor_tiles(def: WorldDecalsDef) -> bool:
	var sh := load(SHADER_PATH) as Shader
	if sh == null:
		return false
	var maps := {"tile_albedo": def.floor_albedo_path, "tile_normal": def.floor_normal_path,
		"tile_mask": def.floor_mask_path}
	var texs := {}
	for k: String in maps:
		var p: String = maps[k]
		if p == "" or not ResourceLoader.exists(p):
			return false
		texs[k] = load(p) as Texture2D
		if texs[k] == null:
			return false
	# Optional: the height map (parallax). Missing = flat tiles (white default).
	if def.floor_height_path != "" and ResourceLoader.exists(def.floor_height_path):
		var h := load(def.floor_height_path) as Texture2D
		if h != null:
			texs["tile_height"] = h
	for k: String in texs:
		sh.set_default_texture_parameter(k, texs[k])
	return true


# ---------------------------------------------------------------- planning

## Every decal for `md`, in priority order, after the per-view cap (pure: no scene).
static func plan(md: MapDef, def: WorldDecalsDef) -> Array[Placement]:
	var rng := RandomNumberGenerator.new()
	rng.seed = def.placement_seed
	var cands: Array[Placement] = []
	var dressing: Array[Placement] = []
	var tags: Array[Placement] = []
	var wear: Array[Placement] = []
	var glyphs: Array[Placement] = []
	var flank: Array[Placement] = []
	var zones := _no_arrow_zones(md, def)
	for li in md.lanes.size():
		var path := lane_path(md, li, def)
		var mid_s := _mid_param(md, li, path)
		var cum := _cumulative(path)
		var total: float = cum[cum.size() - 1]
		# Lane arrows on the centre line.
		var k := 0
		var s := def.arrow_spacing_m * 0.5
		while s < total:
			var p := _at(path, cum, s)
			var t := _tangent(path, cum, s)
			var toward_b := s < mid_s
			var fwd := t if toward_b else -t
			if not _in_zones(p, zones):
				var cell := "arrow_double" if def.arrow_double_every > 0 and k % def.arrow_double_every == def.arrow_double_every - 1 else "arrow"
				var a := Placement.new(cell, Role.ARROW, p, fwd, Vector2.ONE * def.arrow_size_m)
				a.emission = def.arrow_emission
				a.team = MapDef.TEAM_CONCORD if toward_b else MapDef.TEAM_SYNDICATE
				cands.append(a)
				k += 1
			s += def.arrow_spacing_m
		# Grime along both edges, tags and puddles on the lane.
		s = def.grime_spacing_m * 0.5
		var side := 1.0
		while s < total:
			var p := _at(path, cum, s)
			var t := _tangent(path, cum, s)
			var lat := t.cross(Vector3.UP).normalized()
			if rng.randf() < def.grime_chance:
				var g := Placement.new("grime_a" if rng.randf() < 0.5 else "grime_b", Role.GRIME,
					p + lat * side * (def.lane_edge_offset_m + rng.randf_range(-0.6, 0.6)), _rand_dir(rng),
					_rand_size(rng, def.grime_size_m))
				dressing.append(g)
			side = -side
			s += def.grime_spacing_m
		s = def.tag_spacing_m * 0.5
		while s < total:
			var p := _at(path, cum, s)
			var lat := _tangent(path, cum, s).cross(Vector3.UP).normalized()
			var cell: String = ["tag_a", "tag_b", "tag_c"][rng.randi_range(0, 2)]
			var sd := 1.0 if rng.randf() < 0.5 else -1.0
			tags.append(Placement.new(cell, Role.TAG, p + lat * sd * (def.lane_edge_offset_m - 1.5),
				_rand_dir(rng), Vector2(def.tag_size_m * 1.6, def.tag_size_m)))
			s += def.tag_spacing_m
		s = def.puddle_spacing_m * 0.5
		while s < total:
			if rng.randf() < def.puddle_chance:
				var p := _at(path, cum, s)
				var lat := _tangent(path, cum, s).cross(Vector3.UP).normalized()
				dressing.append(Placement.new("puddle" if rng.randf() < 0.6 else "oil", Role.GRIME,
					p + lat * rng.randf_range(-def.lane_edge_offset_m + 1.0, def.lane_edge_offset_m - 1.0),
					_rand_dir(rng), _rand_size(rng, def.puddle_size_m)))
			s += def.puddle_spacing_m
		# Flank loops: arrows from the Outer door toward the Mid door.
		for fl: FlankLoopDef in md.lanes[li].flank_loops:
			var wp := fl.waypoints
			if wp.size() < 2:
				continue
			var fc := _cumulative(wp)
			var ft: float = fc[fc.size() - 1]
			var fs := def.flank_arrow_spacing_m * 0.5
			while fs < ft:
				var fa := Placement.new("arrow", Role.FLANK_ARROW, _at(wp, fc, fs), _tangent(wp, fc, fs),
					Vector2.ONE * def.flank_arrow_size_m)
				fa.emission = def.arrow_emission
				flank.append(fa)
				fs += def.flank_arrow_spacing_m
		# Hardpoint wear: cracks, scorch, oil in an annulus around each pad.
		for hp: HardpointDef in md.lanes[li].hardpoints:
			var r1 := hp.zone_radius + def.arrow_zone_margin_m
			var counts := {"crack": def.hardpoint_cracks, "scorch": def.hardpoint_scorch, "oil": def.hardpoint_oil}
			for kind: String in counts:
				for _i in int(counts[kind]):
					var ang := rng.randf() * TAU
					var r := rng.randf_range(def.wear_r0_m, maxf(def.wear_r0_m, r1))
					var cell := kind
					if kind == "crack":
						cell = ["crack_a", "crack_b", "crack_c"][rng.randi_range(0, 2)]
					wear.append(Placement.new(cell, Role.WEAR, hp.position + Vector3(cos(ang), 0, sin(ang)) * r,
						_rand_dir(rng), _rand_size(rng, def.wear_size_m)))
	# HQ: team glyph and gate chevrons.
	for hq: HqDef in md.hqs:
		var concord := hq.team == MapDef.TEAM_CONCORD
		var to_lane := (hq.lane_gate - hq.uplink) * Vector3(1, 0, 1)
		to_lane = to_lane.normalized() if to_lane.length() > 0.1 else Vector3.FORWARD
		var gl := Placement.new("glyph_concord" if concord else "glyph_syndicate", Role.GLYPH,
			hq.sanctum.lerp(hq.uplink, def.glyph_t), to_lane, Vector2.ONE * def.glyph_size_m)
		gl.modulate = def.concord_color if concord else def.syndicate_color
		gl.emission = def.glyph_emission
		gl.team = hq.team
		glyphs.append(gl)
		var gates := hq.lane_gates if not hq.lane_gates.is_empty() else PackedVector3Array([hq.lane_gate])
		for g: Vector3 in gates:
			var ch := Placement.new("chevrons", Role.CHEVRON, g - to_lane * def.chevron_inset_m, to_lane,
				Vector2.ONE * def.chevron_size_m)
			ch.team = hq.team
			glyphs.append(ch)
	var ordered: Array[Placement] = []
	ordered.append_array(cands)
	ordered.append_array(flank)
	ordered.append_array(glyphs)
	ordered.append_array(wear)
	ordered.append_array(tags)
	ordered.append_array(dressing)
	return apply_cap(ordered, def)


## Keeps placements in order while no check-grid point would see more than
## def.max_visible of them (see the class doc for why this bounds every view).
static func apply_cap(cands: Array[Placement], def: WorldDecalsDef) -> Array[Placement]:
	var g := maxf(def.cap_grid_m, 0.5)
	var reach := def.visible_radius() + g * sqrt(2.0) * 0.5
	var counts := {}
	var out: Array[Placement] = []
	for c in cands:
		var pts := _grid_points_near(c.pos, reach, g)
		var ok := true
		for key: Vector2i in pts:
			if int(counts.get(key, 0)) >= def.max_visible:
				ok = false
				break
		if not ok:
			continue
		for key: Vector2i in pts:
			counts[key] = int(counts.get(key, 0)) + 1
		out.append(c)
	return out


static func _grid_points_near(p: Vector3, reach: float, g: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := floori((p.x - reach) / g)
	var x1 := ceili((p.x + reach) / g)
	var z0 := floori((p.z - reach) / g)
	var z1 := ceili((p.z + reach) / g)
	var r2 := reach * reach
	for ix in range(x0, x1 + 1):
		var dx := ix * g - p.x
		for iz in range(z0, z1 + 1):
			var dz := iz * g - p.z
			if dx * dx + dz * dz <= r2:
				out.append(Vector2i(ix, iz))
	return out


## Lane path from team A's gate to team B's gate through the lane's hardpoints
## (an L-shaped approach where the gate is beside the lane).
static func lane_path(md: MapDef, li: int, def: WorldDecalsDef) -> PackedVector3Array:
	var hps := md.lanes[li].hardpoints
	var pts := PackedVector3Array()
	var a := md.hq(MapDef.TEAM_CONCORD)
	var b := md.hq(MapDef.TEAM_SYNDICATE)
	if hps.is_empty():
		return pts
	if a != null:
		_approach(pts, a.gate_for_lane(li), hps[0].position, def.approach_turn_m, false)
	for hp: HardpointDef in hps:
		_push(pts, hp.position)
	if b != null:
		_approach(pts, b.gate_for_lane(li), hps[hps.size() - 1].position, def.approach_turn_m, true)
	return pts


static func _approach(pts: PackedVector3Array, gate: Vector3, hp: Vector3, turn: float, reverse: bool) -> void:
	var dz := signf(hp.z - gate.z) * minf(turn, absf(hp.z - gate.z))
	var seg := [gate, Vector3(gate.x, gate.y, gate.z + dz), Vector3(hp.x, hp.y, gate.z + dz)]
	if reverse:
		seg.reverse()
	for p: Vector3 in seg:
		_push(pts, p)


static func _push(pts: PackedVector3Array, p: Vector3) -> void:
	if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.5:
		pts.append(p)


static func _cumulative(pts: PackedVector3Array) -> PackedFloat32Array:
	var c := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		c.append(c[i - 1] + (pts[i] - pts[i - 1]).length())
	return c


static func _seg(cum: PackedFloat32Array, s: float) -> int:
	for i in range(1, cum.size()):
		if s <= cum[i]:
			return i
	return cum.size() - 1


static func _at(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	var i := _seg(cum, s)
	var l := cum[i] - cum[i - 1]
	return pts[i - 1].lerp(pts[i], (s - cum[i - 1]) / l if l > 0.0 else 0.0)


static func _tangent(pts: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	var i := _seg(cum, s)
	var t := (pts[i] - pts[i - 1]) * Vector3(1, 0, 1)
	return t.normalized() if t.length() > 0.001 else Vector3.FORWARD


## Path parameter of the lane's Mid hardpoint (the halves meet there).
static func _mid_param(md: MapDef, li: int, path: PackedVector3Array) -> float:
	var hps := md.lanes[li].hardpoints
	var mid: Vector3 = hps[hps.size() / 2].position
	var cum := _cumulative(path)
	var best := 0.0
	var best_d := INF
	for i in path.size():
		var d := path[i].distance_to(mid)
		if d < best_d:
			best_d = d
			best = cum[i]
	return best


static func _no_arrow_zones(md: MapDef, def: WorldDecalsDef) -> Array:
	var z: Array = [[md.mid_plaza_center, md.mid_plaza_radius + def.arrow_zone_margin_m]]
	for lane in md.lanes:
		for hp: HardpointDef in lane.hardpoints:
			z.append([hp.position, hp.zone_radius + def.arrow_zone_margin_m])
	return z


static func _in_zones(p: Vector3, zones: Array) -> bool:
	for z: Array in zones:
		var c: Vector3 = z[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(z[1]):
			return true
	return false


static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var a := rng.randf() * TAU
	return Vector3(sin(a), 0, cos(a))


static func _rand_size(rng: RandomNumberGenerator, range_m: Vector2) -> Vector2:
	var s := rng.randf_range(range_m.x, range_m.y)
	return Vector2(s, s * rng.randf_range(0.8, 1.2))


# ---------------------------------------------------------------- building

## Creates one Decal per placement whose floor `ground` finds. `ground(pos)` returns
## {"pos": Vector3, "normal": Vector3} or {} (no floor: the decal is skipped).
func build(placements: Array[Placement], ground: Callable, accept: Callable = Callable()) -> void:
	for p in placements:
		var hit: Dictionary = ground.call(p.pos)
		if hit.is_empty():
			continue
		if accept.is_valid() and not accept.call(p, hit):
			continue
		var d := make_decal(p, hit.pos, hit.normal, _def)
		if d == null:
			continue
		add_child(d)
		_placed += 1


## The Decal node for `p` on the floor point `at` with floor normal `up`.
static func make_decal(p: Placement, at: Vector3, up: Vector3, def: WorldDecalsDef) -> Decal:
	var tex := atlas_texture(def, p.cell)
	if tex == null:
		return null
	var d := Decal.new()
	d.name = "Decal_%s" % p.cell
	d.size = Vector3(p.size.x, def.box_height_m, p.size.y)
	d.transform = make_decal_transform(p, at, up)
	d.texture_albedo = tex
	d.modulate = p.modulate
	d.albedo_mix = 1.0
	if p.emission > 0.0:
		d.texture_emission = tex
		d.emission_energy = p.emission
	d.normal_fade = def.normal_fade
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.cull_mask = GfxQuality.decal_cull_mask()  # never on heroes / Wardlings
	d.distance_fade_enabled = true
	d.distance_fade_begin = def.fade_begin
	d.distance_fade_length = def.fade_length
	d.set_meta(&"cell", p.cell)
	d.set_meta(&"role", p.role)
	d.set_meta(&"team", p.team)
	return d


## Callable(p, hit) -> bool: true when the decal on that floor hit passes
## PlacementValidator (docs/placement.md: no ledge or drop inside its box).
static func plausible_filter(space: PhysicsDirectSpaceState3D, def: WorldDecalsDef) -> Callable:
	var v := PlacementValidator.new(MapPlacementAudit.rules())
	return func(p: Placement, hit: Dictionary) -> bool:
		return v.check_item(space, decal_item(p, hit, def)).is_empty()


## The PlacementValidator item of decal `p` on the floor hit {pos, normal}.
static func decal_item(p: Placement, hit: Dictionary, def: WorldDecalsDef, id: String = "") -> PlacementValidator.Item:
	var box := AABB(Vector3(-p.size.x, -def.box_height_m, -p.size.y) * 0.5, Vector3(p.size.x, def.box_height_m, p.size.y))
	var it := PlacementValidator.Item.new(id if id != "" else "decal_" + p.cell, &"decal",
		make_decal_transform(p, hit.pos, hit.normal), box)
	it.normal_fade = def.normal_fade
	return it


## Transform of the decal for `p` on the floor point `at` with floor normal `up`
## (PlacementKit.align_up of the image's heading; the image's top maps to -Z).
static func make_decal_transform(p: Placement, at: Vector3, up: Vector3) -> Transform3D:
	var y := up.normalized() if up.length() > 0.1 else Vector3.UP
	var fwd := (p.forward - y * p.forward.dot(y)).normalized()
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	return Transform3D(PlacementKit.align_up(Basis(y.cross(-fwd).normalized(), y, -fwd), y), at)


## Texture of one atlas cell (cut from the atlas once, cached, mipmapped).
static func atlas_texture(def: WorldDecalsDef, cell: String) -> ImageTexture:
	var key := (def.atlas_path if def.atlas_override == null else "override%d" % def.atlas_override.get_instance_id()) \
		+ ":" + cell
	if _textures.has(key):
		return _textures[key]
	var atlas := atlas_image(def)
	var r := def.cell_rect(cell)
	if atlas == null or r.size == Vector2i.ZERO or not Rect2i(Vector2i.ZERO, atlas.get_size()).encloses(r):
		return null
	var img := atlas.get_region(r)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## The decal atlas as an Image (imported with the "image" importer, so it never
## takes VRAM itself; the engine packs the cell textures into its decal atlas).
static func atlas_image(def: WorldDecalsDef) -> Image:
	if def.atlas_override != null:
		return def.atlas_override
	if _atlas_cache != null and _atlas_cache_path == def.atlas_path:
		return _atlas_cache
	var res: Resource = load(def.atlas_path) if ResourceLoader.exists(def.atlas_path) else null
	var img: Image = res as Image
	if img == null and res is Texture2D:
		img = (res as Texture2D).get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img = img.duplicate() as Image
		img.decompress()
	if img.has_mipmaps():
		img = img.duplicate() as Image
		img.clear_mipmaps()
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
	_atlas_cache = img
	_atlas_cache_path = def.atlas_path
	return img


## Floor under `p` from the physics world: walkable hits (normal.y > 0.8) with
## >= 2 m of headroom, the one nearest the MapDef height wins (so lane arrows land
## on the lane, flank arrows in the tunnel under it, never on a roof or an arch).
func _physics_ground(p: Vector3) -> Dictionary:
	return physics_ground(get_world_3d().direct_space_state, p)


## The floor under `p` in `space` ({pos, normal} or {}): the floor-like hit
## (normal y > 0.8, 2 m of headroom) nearest to p.y, through up to 5 layers.
static func physics_ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> Dictionary:
	var from := p + Vector3.UP * 8.0
	var to := p - Vector3.UP * 8.0
	var exclude: Array[RID] = []
	var above := INF
	var best := {}
	var best_d := INF
	for _i in 5:
		var q := PhysicsRayQueryParameters3D.create(from, to, HeroBody.LAYER_WORLD, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var hp: Vector3 = hit.position
		var n: Vector3 = hit.normal
		if n.y > 0.8 and above - hp.y >= 2.0:
			var d := absf(hp.y - p.y)
			if d < best_d:
				best_d = d
				best = {"pos": hp, "normal": n}
		above = hp.y
		exclude.append(hit.rid)
	return best
