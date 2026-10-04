class_name AbilityPresenter
extends Node3D
## Client greybox VFX for skills (E10; art bible §8.2 telegraph language):
## one node per replicated SnapshotData.FxState (AbilityWorld.FX_*).
## - Team colour rims (Concord azure, Syndicate ember); raw mana = violet core.
## - Hostile areas: serrated border ticks + ≤25% fill; allied areas: smooth
##   thin border + ≤12% fill (own effects use the allied style).
## - Projectiles: white core, team rim; enemy ones 20% thicker.
## Presentation only: built from snapshots, never feeds back into the sim.

const VIOLET := Color("#8E5CFF")
const HEAL := Color("#46E07A")
const _TICKS: int = 18

var client: ClientWorld
var _nodes: Dictionary = {}  # fx id -> [Node3D, kind]


func apply_snapshot(s: SnapshotData) -> void:
	var seen := {}
	for f in s.fx:
		seen[f.id] = true
		var rec: Array = _nodes.get(f.id, [])
		if rec.is_empty() or rec[1] != f.kind:
			if not rec.is_empty():
				(rec[0] as Node3D).queue_free()
			rec = [_build(f), f.kind]
			_nodes[f.id] = rec
		_update(rec[0], f)
	for id in _nodes.keys():
		if not seen.has(id):
			(_nodes[id][0] as Node3D).queue_free()
			_nodes.erase(id)


func count() -> int:
	return _nodes.size()


func _hostile(team: int) -> bool:
	return client != null and team != client.own_team()


func _team_color(team: int) -> Color:
	return WardlingView.COLOR_CONCORD if team == MapDef.TEAM_CONCORD else WardlingView.COLOR_SYNDICATE


func _build(f: SnapshotData.FxState) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var c := _team_color(f.team)
	var hostile := _hostile(f.team)
	match f.kind:
		AbilityWorld.FX_WALL:
			var size := f.position2
			# G1: holo-scanline barrier (art bible §10.4); the replicated `param`
			# still drives the fade, through the shader's `alpha`.
			var wall_mat := ModelMaterials.holo(c.lightened(0.25), 1.3, false, 0.0).duplicate() as ShaderMaterial
			var slab := _mesh(root, _box(Vector3(size.x, size.y, maxf(size.z, 0.2))), wall_mat)
			slab.name = "Slab"
			slab.position.y = size.y * 0.5
			for x in [-0.5, 0.5]:
				var post := _mesh(root, _box(Vector3(0.18, size.y + 0.2, 0.5)), _mat(Color.WHITE, 0.9, true))
				post.position = Vector3(x * size.x, size.y * 0.5, 0.0)
			var top := _mesh(root, _box(Vector3(size.x, 0.1, 0.45)), _mat(c, 0.95, true))
			top.position.y = size.y
		AbilityWorld.FX_BEACON:
			var pole := _mesh(root, _cyl(0.12, 1.6), _mat(VIOLET, 0.95, true))
			pole.position.y = 0.8
			var gem := _mesh(root, _sphere(0.28), ModelMaterials.crystal(VIOLET, 2.0, 3.0, 0.5))
			gem.position.y = 1.75
			_area(root, f.position2.x, HEAL.lerp(c, 0.4), hostile)
		AbilityWorld.FX_BASTION:
			_area(root, f.position2.x, c.lightened(0.3), hostile)
		AbilityWorld.FX_CIRCLE, AbilityWorld.FX_BURST:
			_area(root, f.position2.x, c if f.kind == AbilityWorld.FX_CIRCLE else Color.WHITE.lerp(c, 0.5), hostile)
			if f.kind == AbilityWorld.FX_BURST:
				# G1: bright inner shock ring + dome flash on top of the area ring.
				var br := maxf(f.position2.x, 0.5)
				var shock := TorusMesh.new()
				shock.inner_radius = br * 0.7
				shock.outer_radius = br * 0.74
				shock.rings = 48
				_mesh(root, shock, _mat(Color.WHITE, 0.9, true)).position.y = 0.15
				var dome := SphereMesh.new()
				dome.radius = br * 0.6
				dome.height = dome.radius
				dome.is_hemisphere = true
				_mesh(root, dome, _mat(Color.WHITE.lerp(c, 0.4), 0.18, true))
			if f.kind == AbilityWorld.FX_CIRCLE:
				# Ultimate / cast telegraph: vertical light column (art bible §8.2).
				var col := _mesh(root, _cyl(0.25, 14.0), ModelMaterials.holo(c.lightened(0.4), 1.6, false, 0.0))
				col.position.y = 7.0
				var halo := _mesh(root, _cyl(0.7, 14.0), _mat(c, 0.12, true))
				halo.position.y = 7.0
		AbilityWorld.FX_THREAD, AbilityWorld.FX_TRAIL, AbilityWorld.FX_ARROW:
			var w := 0.06 if f.kind != AbilityWorld.FX_ARROW else 0.5
			if hostile:
				w *= 1.2
			var line := _mesh(root, _box(Vector3(w, w if f.kind != AbilityWorld.FX_ARROW else 0.03, 1.0)),
				_mat(Color.WHITE.lerp(VIOLET if f.kind != AbilityWorld.FX_ARROW else c, 0.45), 0.85, true))
			line.name = "Line"
			if f.kind == AbilityWorld.FX_ARROW:
				var head := _mesh(root, _box(Vector3(1.2, 0.03, 0.6)), _mat(c, 0.7, true))
				head.name = "Head"
	return root


func _update(n: Node3D, f: SnapshotData.FxState) -> void:
	match f.kind:
		AbilityWorld.FX_WALL:
			n.position = f.position
			n.rotation = Vector3(0.0, f.yaw, 0.0)
			var slab := n.get_node_or_null("Slab") as MeshInstance3D
			if slab != null:
				(slab.material_override as ShaderMaterial).set_shader_parameter("alpha", 0.3 + 0.5 * f.param)
		AbilityWorld.FX_THREAD, AbilityWorld.FX_TRAIL, AbilityWorld.FX_ARROW:
			var a := f.position2 if f.kind == AbilityWorld.FX_THREAD else f.position
			var b := f.position if f.kind == AbilityWorld.FX_THREAD else f.position2
			if f.kind == AbilityWorld.FX_ARROW:
				a.y += 0.08
				b.y += 0.08
			var mid := (a + b) * 0.5
			var len := maxf(a.distance_to(b), 0.3)
			n.position = mid
			if len > 0.31:
				n.look_at_from_position(mid, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
			var line := n.get_node_or_null("Line") as Node3D
			if line != null:
				line.scale = Vector3(1.0, 1.0, len)
			var head := n.get_node_or_null("Head") as Node3D
			if head != null:
				head.position = Vector3(0.0, 0.0, -len * 0.5)
		AbilityWorld.FX_BURST:
			n.position = f.position + Vector3(0.0, 0.05, 0.0)
			var k := clampf(1.0 - f.ticks_left / 18.0, 0.2, 1.0)
			n.scale = Vector3(k, 1.0, k)
		_:
			n.position = f.position + Vector3(0.0, 0.05, 0.0)


## Ground area: ring + fill (+ serrated outward ticks when hostile).
func _area(root: Node3D, radius: float, c: Color, hostile: bool) -> void:
	var r := maxf(radius, 0.5)
	var ring := TorusMesh.new()
	ring.inner_radius = r - (0.12 if hostile else 0.07)
	ring.outer_radius = r
	ring.rings = 48
	_mesh(root, ring, _mat(c, 0.95, true))
	var fill := _mesh(root, _cyl(r, 0.02), _mat(c, 0.22 if hostile else 0.1, false))
	fill.position.y = 0.01
	if hostile:
		for i in _TICKS:
			var a := TAU * i / _TICKS
			var t := _mesh(root, _box(Vector3(0.12, 0.08, 0.5)), _mat(c, 0.95, true))
			t.position = Vector3(cos(a), 0.0, sin(a)) * (r + 0.2)
			t.rotation.y = -a + PI / 2.0


func _mesh(parent: Node3D, m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 32
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


static func _mat(c: Color, alpha: float, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m
