class_name GadgetFx
extends RefCounted
## Client greybox visuals for the gadget FX of TrapWorld (FX_SNARE .. FX_PULSE):
## Juniper Quill's traps and Killbox dome, Hex's Static Field and hack markers
## (design/gdd/heroes.md §4.3, §4.7). Presentation only, built from snapshots.
## - Enemy traps are visible only close up (snare/wire 8 m, mine 4 m) unless
##   Malfunctioning ("inert and fully visible") or the viewer is Hex, whose
##   Signal Sight shows gadgets through walls within 25 m.
## - Allied traps are always shown. Mustard = trapper, lime = hacker.

const MUSTARD := Color("#E0B030")
const LIME := Color("#A6FF3A")
const GREY := Color("#8A8F98")
const SEE_SNARE_M: float = 8.0
const SEE_MINE_M: float = 4.0
const HEX_SIGHT_M: float = 25.0


static func build(f: SnapshotData.FxState, team_color: Color, hostile: bool) -> Node3D:
	var root := Node3D.new()
	match f.kind:
		TrapWorld.FX_SNARE:
			_ring(root, 0.7, MUSTARD, 0.08)
			for i in 4:
				var a := TAU * i / 4.0
				var tooth := _box(root, Vector3(0.1, 0.35, 0.1), team_color.lightened(0.2))
				tooth.position = Vector3(cos(a), 0.17, sin(a)) * 0.55
				tooth.rotation.z = 0.35
		TrapWorld.FX_MINE:
			var disc := _mesh(root, _cyl(0.45, 0.12), _mat(MUSTARD.darkened(0.3), 0.95, true))
			disc.position.y = 0.06
			var cap := _mesh(root, _sphere(0.2), _mat(team_color.lightened(0.3), 1.0, true))
			cap.position.y = 0.14
		TrapWorld.FX_WIRE:
			for nm in ["PostA", "PostB"]:
				var post := _box(root, Vector3(0.14, 1.0, 0.14), MUSTARD)
				post.name = nm
			var beam := _box(root, Vector3(0.05, 0.05, 1.0), Color("#FF3B3B"))
			beam.name = "Beam"
		TrapWorld.FX_DOME:
			var r := maxf(f.position2.x, 1.0)
			var shell := _mesh(root, _sphere(r), _mat(Color("#FFE04A").lerp(team_color, 0.35), 0.1, true))
			(shell.mesh as SphereMesh).height = r  # hemisphere shell
			(shell.mesh as SphereMesh).is_hemisphere = true
			_ring(root, r, Color("#FFE04A"), 0.18)
			var emitter := _mesh(root, _cyl(0.4, 1.4), _mat(MUSTARD, 0.95, true))
			emitter.position.y = 0.7
		TrapWorld.FX_FIELD:
			var rf := maxf(f.position2.x, 1.0)
			_ring(root, rf, LIME, 0.12)
			var fill := _mesh(root, _cyl(rf, 0.02), _mat(LIME, 0.18, false))
			fill.position.y = 0.01
			for i in 6:
				var a2 := TAU * i / 6.0
				var pillar := _box(root, Vector3(0.12, 1.6, 0.12), LIME)
				pillar.position = Vector3(cos(a2), 0.8, sin(a2)) * rf * 0.92
		TrapWorld.FX_HACK:
			var cube := _box(root, Vector3(0.4, 0.4, 0.4), LIME)
			cube.name = "Cube"
			_ring(root, 0.6, LIME, 0.05).position.y = -0.4
		TrapWorld.FX_PULSE:
			_ring(root, maxf(f.position2.x, 1.0), LIME.lerp(team_color, 0.4) if hostile else LIME, 0.2)
	return root


static func update(n: Node3D, f: SnapshotData.FxState, client: ClientWorld, hostile: bool) -> void:
	var down := f.param > TrapWorld.DOWN_THRESHOLD
	match f.kind:
		TrapWorld.FX_WIRE:
			var a := f.position
			var b := f.position2
			n.position = Vector3.ZERO
			var pa := n.get_node_or_null("PostA") as Node3D
			var pb := n.get_node_or_null("PostB") as Node3D
			if pa != null:
				pa.position = a + Vector3(0.0, 0.5, 0.0)
			if pb != null:
				pb.position = b + Vector3(0.0, 0.5, 0.0)
				pb.visible = a.distance_to(b) > 0.1
			var beam := n.get_node_or_null("Beam") as Node3D
			if beam != null:
				var len := a.distance_to(b)
				beam.visible = len > 0.1
				if len > 0.1:
					var mid := (a + b) * 0.5 + Vector3(0.0, TrapWorld.WIRE_HEIGHT_M, 0.0)
					beam.position = mid
					beam.look_at_from_position(mid, b + Vector3(0.0, TrapWorld.WIRE_HEIGHT_M, 0.0), Vector3.UP)
					beam.scale = Vector3(1.0, 1.0, len)
		TrapWorld.FX_PULSE:
			n.position = f.position + Vector3(0.0, 0.05, 0.0)
			var k := clampf(1.0 - f.ticks_left / 18.0, 0.2, 1.0)
			n.scale = Vector3(k, 1.0, k)
		TrapWorld.FX_HACK:
			n.position = f.position
			n.rotation.y += 0.15
		_:
			n.position = f.position + Vector3(0.0, 0.03, 0.0)
	n.visible = _visible(f, client, hostile, down)


static func _visible(f: SnapshotData.FxState, client: ClientWorld, hostile: bool, down: bool) -> bool:
	if not hostile or down:
		return true
	var reach := 0.0
	match f.kind:
		TrapWorld.FX_SNARE, TrapWorld.FX_WIRE:
			reach = SEE_SNARE_M
		TrapWorld.FX_MINE:
			reach = SEE_MINE_M
		_:
			return true  # dome, field, hack markers, pulses: telegraphed to everyone
	if client != null and client.hero_def != null and client.hero_def.gadget_damage_mult > 1.0:
		reach = HEX_SIGHT_M  # Hex: Signal Sight
	if client == null or client.body == null:
		return true
	var me := client.body.state.position
	var d := minf(Vector2(me.x - f.position.x, me.z - f.position.z).length(),
		Vector2(me.x - f.position2.x, me.z - f.position2.z).length() if f.kind == TrapWorld.FX_WIRE else INF)
	return d <= reach


static func _ring(parent: Node3D, radius: float, c: Color, thickness: float) -> MeshInstance3D:
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(radius - thickness, 0.05)
	ring.outer_radius = radius
	ring.rings = 40
	return _mesh(parent, ring, _mat(c, 0.95, true))


static func _box(parent: Node3D, size: Vector3, c: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(parent, b, _mat(c, 0.95, true))


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


static func _mesh(parent: Node3D, m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


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
