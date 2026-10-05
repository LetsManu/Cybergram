class_name MapVisuals
extends Node
## Runtime visual layer of the Shardline Causeway (chunk G1; presentation only).
## Sits in the map scene (added by tools/maps/build_shardline_causeway.gd) and:
##  * on the headless server, strips the baked Env / Sun / lights and builds
##    nothing (the server creates no visuals);
##  * on clients, scales the baked environment to GfxQuality.level() and builds
##    the dressing: Leyfall mana sea, skyline silhouettes on floating shards,
##    floating crystals, distant spires, hardpoint holo rings + banners and lane
##    light strips on the rails.
## The dressing is plain MeshInstance3D / MultiMeshInstance3D nodes: no
## collision, on no physics layer, nothing in the navigation source group, so
## fire lines and the navmesh are untouched. Instances are batched into a few
## MultiMeshes (draw-call budget: about 12 for the whole dressing).

const SEA_SHADER := "res://assets/shaders/spatial_env_sea.gdshader"
const SKYLINE_SHADER := "res://assets/shaders/spatial_env_skyline.gdshader"

const LANE_LEN: float = 420.0
## Dressing stays at least this far (lateral, metres) from the lane axis.
const SKYLINE_MIN_X: float = 75.0
const SKYLINE_MAX_X: float = 330.0
const SEA_Y: float = -90.0

const SIGN_TEAL := Color("#34D8C4")
const AZURE := Color("#2E86FF")
const EMBER := Color("#FF5A1F")
const LEYFALL := Color("#8E5CFF")

## Per-map dressing extents (the 3-lane Shardline Front spans x -95..95, so its
## builder pushes the skyline out and spreads the spires; slice defaults above).
@export var skyline_min_x: float = SKYLINE_MIN_X
@export var skyline_max_x: float = SKYLINE_MAX_X
@export var spire_spread: float = 1.0

var _spin: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
## W14-P2 post layers (null below High).
var _rim: DirectionalLight3D
var _ink: MeshInstance3D


func _ready() -> void:
	if GfxQuality.is_headless():
		_strip_for_server()
		return
	apply_quality()
	_build_dressing(GfxQuality.level())
	# --- W18-LIFE ---
	AmbientWorld.create_for(self, get_parent())  # null on server / headless
	# --- end W18-LIFE ---


func _process(delta: float) -> void:
	for n in _spin:
		n.rotate_y(delta * 0.6)
	if _rim != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:  # back light: travels towards the camera, slightly downward
			var dir := (cam.global_transform.basis.z - Vector3(0.0, 0.35, 0.0)).normalized()
			_rim.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), cam.global_position)


## Re-applies the current graphics tier to the map's environment, sun and the
## viewport AA (callable again when the setting changes).
func apply_quality() -> void:
	var root := get_parent()
	var we := root.get_node_or_null("Env") as WorldEnvironment
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	var lvl := GfxQuality.level()
	GfxQuality.apply(lvl, we.environment if we != null else null, sun, get_viewport())
	for n in [_rim, _ink]:
		if n != null:
			n.queue_free()
	_rim = null
	_ink = null
	if GfxQuality.rim_light_enabled(lvl):
		_rim = GfxQuality.make_rim_light()
		add_child(_rim)
	if GfxQuality.ink_edges_enabled(lvl):
		_ink = GfxQuality.make_ink_edges(lvl)
		add_child(_ink)


func _strip_for_server() -> void:
	var root := get_parent()
	for n in root.find_children("*", "Light3D", true, false):
		n.queue_free()
	var we := root.get_node_or_null("Env")
	if we != null:
		we.queue_free()


# ------------------------------------------------------------ dressing

func _build_dressing(lvl: int) -> void:
	var dress := Node3D.new()
	dress.name = "Dressing"
	add_child(dress)
	var k := GfxQuality.particle_scale(lvl)
	_rng.seed = 90210
	_sea(dress)
	_skyline(dress, int(110.0 * k))
	_crystals(dress, int(36.0 * k))
	_spires(dress)
	_rail_strips(dress)
	if lvl >= GfxQuality.MEDIUM:
		_hardpoint_dressing(dress)


func _flat_mat(c: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, 1.0)
	return m


func _mm(parent: Node, mesh: Mesh, mat: Material, xforms: Array[Transform3D], cast_shadow: bool = false) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-800, -200, -900), Vector3(1600, 600, 1700))
	parent.add_child(mi)


func _sea(parent: Node) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600.0, 1800.0)
	var m := ShaderMaterial.new()
	m.shader = load(SEA_SHADER)
	var mi := MeshInstance3D.new()
	mi.name = "LeyfallSea"
	mi.mesh = plane
	mi.material_override = m
	mi.position = Vector3(0.0, SEA_Y, -LANE_LEN * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Dark block towers on inverted-cone shards, both sides of the causeway.
func _skyline(parent: Node, count: int) -> void:
	var towers: Array[Transform3D] = []
	var shards: Array[Transform3D] = []
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * _rng.randf_range(skyline_min_x, skyline_max_x)
		var l := _rng.randf_range(-120.0, LANE_LEN + 120.0)
		var w := _rng.randf_range(10.0, 26.0)
		var h := _rng.randf_range(35.0, 150.0) * (1.0 + (absf(x) - skyline_min_x) / 400.0)
		var base := _rng.randf_range(-30.0, -4.0)
		var yaw := _rng.randf_range(0.0, PI)
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(w, h, w * _rng.randf_range(0.7, 1.3)))
		towers.append(Transform3D(b, Vector3(x, base + h * 0.5, -l)))
		var sw := w * 1.4
		var sh := _rng.randf_range(25.0, 60.0)
		shards.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sw, sh, sw)), Vector3(x, base - sh * 0.5, -l)))
	var box := BoxMesh.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load(SKYLINE_SHADER)
	_mm(parent, box, sky_mat, towers)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 0.0
	cone.height = 1.0
	cone.radial_segments = 7
	cone.rings = 1
	_mm(parent, cone, _flat_mat(Color(0.2, 0.15, 0.34)), shards)


## Floating violet crystals (mana, Signal-capable material from the model library).
func _crystals(parent: Node, count: int) -> void:
	var xf: Array[Transform3D] = []
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * _rng.randf_range(32.0, 140.0) * spire_spread
		var l := _rng.randf_range(-20.0, LANE_LEN + 20.0)
		var y := _rng.randf_range(14.0, 70.0)
		var s := _rng.randf_range(1.5, 5.5)
		var tilt := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3))
		xf.append(Transform3D(tilt.scaled(Vector3(s * 0.6, s * 1.8, s * 0.6)), Vector3(x, y, -l)))
	var gem := SphereMesh.new()
	gem.radial_segments = 5
	gem.rings = 2
	gem.radius = 0.5
	gem.height = 1.0
	_mm(parent, gem, ModelMaterials.crystal(LEYFALL, 1.5, 2.0, 0.25), xf)


## Tall lattice spires far behind each HQ and flanking the arena, with a glowing ring.
func _spires(parent: Node) -> void:
	var spec := [
		[Vector3(-120.0, -20.0, 60.0), AZURE], [Vector3(130.0, -20.0, 90.0), AZURE],
		[Vector3(-130.0, -20.0, -LANE_LEN - 80.0), EMBER], [Vector3(120.0, -20.0, -LANE_LEN - 100.0), EMBER],
		[Vector3(-170.0, -20.0, -LANE_LEN * 0.5), LEYFALL], [Vector3(180.0, -20.0, -LANE_LEN * 0.5 - 40.0), LEYFALL],
	]
	var body := CylinderMesh.new()
	body.top_radius = 2.0
	body.bottom_radius = 7.0
	body.height = 170.0
	body.radial_segments = 6
	body.rings = 1
	var ring := TorusMesh.new()
	ring.inner_radius = 6.0
	ring.outer_radius = 7.0
	ring.rings = 24
	ring.ring_segments = 4
	for s in spec:
		var p: Vector3 = s[0] * Vector3(spire_spread, 1.0, 1.0)
		var c: Color = s[1]
		var mi := MeshInstance3D.new()
		mi.mesh = body
		mi.material_override = _flat_mat(Color(0.17, 0.15, 0.3))
		mi.position = p + Vector3(0.0, body.height * 0.5, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var r := MeshInstance3D.new()
		r.mesh = ring
		r.material_override = _flat_mat(c, 1.3)
		r.position = p + Vector3(0.0, 120.0, 0.0)
		r.scale = Vector3(1.0, 0.5, 1.0)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(r)
		_spin.append(r)


## Thin emissive strips along every edge rail, tinted by lane half (Accent tier: no bloom).
func _rail_strips(parent: Node) -> void:
	var by_color := {AZURE: [] as Array[Transform3D], EMBER: [] as Array[Transform3D], LEYFALL: [] as Array[Transform3D]}
	var geo := get_parent().get_node_or_null("Geometry")
	if geo == null:
		return
	for n in geo.find_children("*Rail*", "StaticBody3D", true, false):
		var body := n as StaticBody3D
		var mi := body.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null or not (mi.mesh is BoxMesh):
			continue
		var size := (mi.mesh as BoxMesh).size
		var xf := body.global_transform
		var z := xf.origin.z
		var c: Color = AZURE if z > -190.0 else (EMBER if z < -230.0 else LEYFALL)
		var strip := Transform3D(xf.basis.scaled_local(Vector3(size.x + 0.04, 0.06, size.z + 0.04)),
			xf.origin + Vector3(0.0, size.y * 0.5 + 0.03, 0.0))
		(by_color[c] as Array[Transform3D]).append(strip)
	var box := BoxMesh.new()
	for c: Color in by_color:
		_mm(parent, box, _flat_mat(c, 1.0), by_color[c] as Array[Transform3D])


## Holo rings above each hardpoint and banner pairs at the pad edges (above 4 m, off the fire lines).
func _hardpoint_dressing(parent: Node) -> void:
	var anchors := get_parent().get_node_or_null("Anchors")
	if anchors == null:
		return
	for a in anchors.get_children():
		if not (a is HardpointAnchor):
			continue
		var ha := a as HardpointAnchor
		var z := ha.position.z
		var c: Color = AZURE if z > -190.0 else (EMBER if z < -230.0 else LEYFALL)
		var torus := TorusMesh.new()
		torus.inner_radius = 2.6
		torus.outer_radius = 3.0
		torus.rings = 32
		torus.ring_segments = 4
		var ring := MeshInstance3D.new()
		ring.name = "HoloRing_%s" % ha.hardpoint_id
		ring.mesh = torus
		ring.material_override = ModelMaterials.holo(c, 0.9, false, 0.0)
		ring.position = ha.position + Vector3(0.0, 11.0, 0.0)
		ring.scale = Vector3(1.0, 0.3, 1.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(ring)
		_spin.append(ring)
		var banner := QuadMesh.new()
		banner.size = Vector2(2.2, 7.0)
		for s in [-1.0, 1.0]:
			var b := MeshInstance3D.new()
			b.mesh = banner
			b.material_override = ModelMaterials.holo(c, 0.6, true, 0.0)
			b.position = ha.position + Vector3(s * (ha.zone_radius + 4.0), 8.5, 0.0)
			b.rotation.y = PI * 0.5
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(b)
