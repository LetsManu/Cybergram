class_name UplinkModel
extends Node3D
## The Mana Uplink as a 45 m neon mana spire (art bible §6.5): a giant crystal
## held in a chrome frame of rings, wrapped in rotating holographic rune bands,
## firing a team-coloured beam into the sky. States: Protected (smooth spin,
## steady beam), Exposed (rings stop and judder, rune bands glitch, beam turns
## jagged, crystal pulses hot), Integrity 75/50/25 (one rune band dies per
## stage, crystal dims and cracks), Destroyed (beam gone, crystal grey).
## Origin = Uplink floor; the crystal is centred on `core_y` (the gameplay core).

const K := PartBuilder.Kind
const HEIGHT_M: float = 45.0
const RING_Y: Array[float] = [3.2, 12.5, 19.0, 26.0, 33.0]

var team: int = 0
var core_y: float = 7.3
var exposed: bool = false
var destroyed: bool = false
var stage: int = 0  # 0..3 crack stages (75/50/25 %)

var _rings: Array[Node3D] = []
var _bands: Array[MeshInstance3D] = []
var _band_mats: Array[ShaderMaterial] = []
var _crystal_mat: ShaderMaterial
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _cracks: MeshInstance3D
var _t: float = 0.0
var _tris: int = 0

static var _frame_mesh: ArrayMesh
static var _ring_meshes: Array[ArrayMesh] = []
static var _crystal_mesh: ArrayMesh
static var _band_mesh: ArrayMesh
static var _beam_mesh: ArrayMesh
static var _crack_mesh: ArrayMesh


func setup(team_: int, core_y_: float) -> void:
	team = team_
	core_y = core_y_
	name = "UplinkModel"
	_build_meshes()
	var tc := ModelPalette.team_color(team)
	# Phase 6: the frame and rings from the hero pipeline (tools/art/world/uplink.py)
	# when built; the procedural greybox frame otherwise. Rings are separate pieces
	# with their pivot at their centre, so the spin / judder below works on both.
	var baked := WorldModel.instantiate(&"uplink", team)
	if baked != null:
		baked.name = "Frame"
		add_child(baked)
		for i in RING_Y.size():
			var piece := WorldModel.piece(baked, StringName("ring_%d" % i))
			if piece != null:
				_rings.append(piece)
	else:
		var toon := ModelMaterials.toon(team)
		_add(self, _frame_mesh, toon)
		for i in RING_Y.size():
			var r := Node3D.new()
			r.position.y = RING_Y[i]
			add_child(r)
			_add(r, _ring_meshes[i], toon)
			_rings.append(r)
	_crystal_mat = ModelMaterials.crystal_unique(tc, 2.2, 4.0)
	_crystal_mat.set_shader_parameter("core_mix", 0.35)
	var cr := _add(self, _crystal_mesh, _crystal_mat)
	cr.position.y = core_y
	_cracks = _add(self, _crack_mesh, ModelMaterials.toon(ModelPalette.TEAM_NEUTRAL))
	_cracks.position.y = core_y
	_cracks.visible = false
	for i in 3:
		var m := ModelMaterials.holo(tc.lightened(0.2), 1.0, true).duplicate() as ShaderMaterial
		m.set_shader_parameter("alpha", 0.6)
		var b := _add(self, _band_mesh, m)
		b.position.y = core_y - 1.6 + i * 1.6
		b.scale = Vector3.ONE * (1.0 - 0.08 * i)
		_bands.append(b)
		_band_mats.append(m)
	_beam_mat = ModelMaterials.holo(tc.lightened(0.15), 1.0).duplicate() as ShaderMaterial
	_beam_mat.set_shader_parameter("alpha", 0.75)
	_beam = _add(self, _beam_mesh, _beam_mat)
	_beam.position.y = HEIGHT_M
	for mi in find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		_tris += (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	set_state(false, false, 1.0)


## True when the hero-pipeline frame (assets/models/world/uplink/) is in use.
func is_baked() -> bool:
	return find_child("Frame", false, false) != null


## Applies the replicated state (integrity_frac 0..1).
func set_state(exposed_: bool, destroyed_: bool, integrity_frac: float) -> void:
	exposed = exposed_
	destroyed = destroyed_
	stage = 0 if integrity_frac > 0.75 else (1 if integrity_frac > 0.5 else (2 if integrity_frac > 0.25 else 3))
	for i in _bands.size():
		_bands[i].visible = not destroyed and i < 3 - stage
		_band_mats[i].set_shader_parameter("glitch_amount", 0.85 if exposed else 0.0)
	_beam.visible = not destroyed
	_cracks.visible = stage > 0 or destroyed
	_cracks.scale = Vector3.ONE * (0.6 + 0.2 * stage)
	_crystal_mat.set_shader_parameter("dead", 1.0 if destroyed else 0.0)
	_crystal_mat.set_shader_parameter("energy", 2.2 - 0.35 * stage)
	_crystal_mat.set_shader_parameter("pulse_speed", 1.6 if exposed else 0.15)
	_crystal_mat.set_shader_parameter("pulse_depth", 0.45 if exposed else 0.1)
	_crystal_mat.set_shader_parameter("hue", ModelPalette.team_color(team).lerp(Color(1, 0.95, 0.85), 0.3) if exposed else ModelPalette.team_color(team))


func triangle_count() -> int:
	return _tris


func _process(delta: float) -> void:
	_t += delta
	if destroyed:
		return
	for i in _rings.size():
		var r := _rings[i]
		if exposed:
			# stopped, juddering
			r.rotation = Vector3(sin(_t * 31.0 + i) * 0.02, r.rotation.y, cos(_t * 27.0 + i) * 0.02)
		else:
			r.rotation = Vector3(0.0, _t * (0.25 + 0.08 * i) * (1.0 if i % 2 == 0 else -1.0), 0.0)
	for i in _bands.size():
		_bands[i].rotation.y = (0.0 if exposed else _t * (0.4 - 0.15 * i))
	if exposed:
		var j := 0.6 + 0.8 * absf(sin(_t * 23.0) * cos(_t * 7.0))
		_beam.scale = Vector3(j, 1.0, j)
	else:
		_beam.scale = Vector3.ONE


static func _build_meshes() -> void:
	if _frame_mesh != null:
		return
	var chrome := ModelPalette.CHROME_COOL
	var f := PartBuilder.new()
	# collar on the map's plinth + 6 pylons
	f.torus(3.3, 3.9, PartBuilder.xf(Vector3(0, 1.55, 0), Vector3.ZERO, Vector3(1, 0.4, 1)), chrome, K.CHROME, 0.0, 32, 6)
	f.torus(3.55, 3.65, PartBuilder.xf(Vector3(0, 1.75, 0)), Color.WHITE, K.NEON, 1.0, 32, 4)
	for k in 6:
		var a := TAU * k / 6.0
		f.box(Vector3(0.7, 3.0, 0.7), PartBuilder.xf(Vector3(cos(a) * 3.6, 3.0, sin(a) * 3.6), Vector3(0, -rad_to_deg(a), 0)), Color.WHITE, K.TRIM, 0.0, Vector2(0.6, 0.6))
	# three tall chrome legs converging toward the mast
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		var p0 := Vector3(cos(a) * 3.0, 1.5, sin(a) * 3.0)
		var p1 := Vector3(cos(a) * 0.9, 36.0, sin(a) * 0.9)
		var mid := (p0 + p1) * 0.5
		var d := (p1 - p0)
		var basis := Basis.looking_at(d.normalized(), Vector3(cos(a), 0, sin(a))) * Basis.from_euler(Vector3(-PI * 0.5, 0, 0))
		f.box(Vector3(1.0, d.length(), 1.3), Transform3D(basis, mid), chrome, K.CHROME, 0.0, Vector2(0.45, 0.45))
		f.box(Vector3(0.18, d.length() * 0.95, 1.36), Transform3D(basis, mid), Color.WHITE, K.NEON, 1.0, Vector2(0.45, 0.45))
		f.box(Vector3(1.3, 4.0, 1.6), Transform3D(Basis(), p0 + Vector3(0, 1.0, 0)), Color.WHITE, K.TRIM, 0.0, Vector2(0.7, 0.7))
	# crystal claw holders
	for k in 3:
		var a := TAU * k / 3.0
		f.box(Vector3(0.35, 2.8, 0.35), PartBuilder.xf(Vector3(cos(a) * 1.6, 7.3 - 2.6, sin(a) * 1.6), Vector3(sin(a) * 18.0, 0, -cos(a) * 18.0)), chrome, K.CHROME)
		f.box(Vector3(0.35, 2.4, 0.35), PartBuilder.xf(Vector3(cos(a) * 1.5, 7.3 + 2.6, sin(a) * 1.5), Vector3(-sin(a) * 18.0, 0, cos(a) * 18.0)), chrome, K.CHROME)
	# mast + emitter head at 45 m
	f.cyl(0.35, 0.7, 9.0, PartBuilder.xf(Vector3(0, 40.0, 0)), chrome, K.CHROME, 0.0, 10)
	f.cyl(1.4, 0.4, 1.2, PartBuilder.xf(Vector3(0, 44.4, 0)), Color.WHITE, K.TRIM, 0.0, 12)
	f.sphere(0.8, PartBuilder.xf(Vector3(0, 45.0, 0)), Color.WHITE, K.SIGNAL, 2.5, 12)
	_frame_mesh = f.commit()
	for i in RING_Y.size():
		var rb := PartBuilder.new()
		var r: float = [4.4, 3.1, 2.6, 2.0, 1.6][i]
		rb.torus(r - 0.45, r, PartBuilder.xf(Vector3.ZERO), chrome, K.CHROME, 0.0, 36, 6)
		rb.torus(r - 0.14, r - 0.1, PartBuilder.xf(Vector3(0, 0.12, 0)), Color.WHITE, K.NEON, 1.0, 36, 3)
		for k in 6:  # glyph teeth
			var a := TAU * k / 6.0
			rb.box(Vector3(0.3, 0.3, 0.12), PartBuilder.xf(Vector3(cos(a) * r, 0, sin(a) * r), Vector3(0, -rad_to_deg(a), 0)), Color.WHITE, K.TRIM)
		_ring_meshes.append(rb.commit())
	var cb := PartBuilder.new()
	cb.sphere(1.0, PartBuilder.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1.6, 2.4, 1.6)), Color.WHITE, K.FLAT, 0.0, 6)
	# second crystal heart up the mast, held where the legs converge
	cb.sphere(1.0, PartBuilder.xf(Vector3(0, 15.5, 0), Vector3(0, 30, 0), Vector3(1.0, 2.2, 1.0)), Color.WHITE, K.FLAT, 0.0, 6)
	for k in 3:
		var a := TAU * k / 3.0 + 0.3
		cb.sphere(0.5, PartBuilder.xf(Vector3(cos(a) * 1.6, 21.0 + k * 3.0, sin(a) * 1.6), Vector3(0, 0, 15), Vector3(0.6, 1.5, 0.6)), Color.WHITE, K.FLAT, 0.0, 6)
	cb.sphere(0.5, PartBuilder.xf(Vector3(0.9, 1.3, 0.3), Vector3(0, 0, -30), Vector3(0.6, 1.4, 0.6)), Color.WHITE, K.FLAT, 0.0, 6)
	cb.sphere(0.45, PartBuilder.xf(Vector3(-0.8, -1.2, -0.3), Vector3(0, 0, 150), Vector3(0.6, 1.3, 0.6)), Color.WHITE, K.FLAT, 0.0, 6)
	_crystal_mesh = cb.commit()
	var kb := PartBuilder.new()  # crack lines (dark seams), scaled per stage
	for k in 5:
		kb.box(Vector3(0.08, 1.6, 0.08), PartBuilder.xf(Vector3(cos(k * 1.3) * 1.25, -0.8 + k * 0.4, sin(k * 1.3) * 1.25), Vector3(0, -k * 74.0, 25 - k * 12)), Color("#15121A"))
	_crack_mesh = kb.commit()
	var bb := PartBuilder.new()
	bb.keep_uv = true
	bb.cyl(2.6, 2.6, 0.9, PartBuilder.xf(Vector3.ZERO), Color.WHITE, K.FLAT, 0.0, 24)
	_band_mesh = bb.commit()
	var beam := PartBuilder.new()
	beam.cyl(0.9, 1.2, 220.0, PartBuilder.xf(Vector3(0, 110.0, 0)), Color.WHITE, K.FLAT, 0.0, 10)
	_beam_mesh = beam.commit()


func _add(parent: Node3D, mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if not (mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.ends_with("toon.gdshader")):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
