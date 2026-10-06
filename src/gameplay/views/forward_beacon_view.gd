class_name ForwardBeaconView
extends Node3D
## One team's Forward Beacon spawn pad at a Mid hardpoint (docs/assets/
## forward_beacon.md; match-flow-and-map.md §3.5; art bible §6.4). Presentation
## only: it reads the replicated HardpointState (owner, beacon, beacon_attune).
## Each Mid has two pads, one per side (ProgressionSystem.beacon_spot); a pad
## lights only while its side holds the Mid.
##
## Stages (stage_of, pure; ClientSfx uses the same function for the sounds):
##   DORMANT       the side does not hold the Mid: lenses dark, no hard-light
##   ATTUNING      held, attuning: lenses light one by one, the mast builds up,
##                 the halo arc fills
##   READY         spawnable: mast, banner and halo at full strength
##   UNDER_ATTACK  held and attuned but contested (not spawnable): the
##                 hard-light dims and blinks, the banner glitches

enum Stage { DORMANT, ATTUNING, READY, UNDER_ATTACK }

const KEY: StringName = &"forward_beacon"
const SHADER := "res://assets/shaders/spatial_fx_beacon_holo.gdshader"
const LAMPS: int = 6
## Pad radius (tools/art/world/forward_beacon.py R) and its height.
const PAD_RADIUS_M: float = 1.6
const PAD_HEIGHT_M: float = 0.12
## place(): how far (m) and in which steps the pad may move off the spawn spot
## to find level floor (the Spindle's spot sits on the Holdstone dais edge).
const PLACE_REACH_M: float = 2.0
const PLACE_STEP_M: float = 0.25

var side: int = MapDef.TEAM_CONCORD
var stage: int = Stage.DORMANT
var attune: float = 0.0
var def: ForwardBeaconDef
var _model: Node3D
var _mast: MeshInstance3D
var _banner: MeshInstance3D
var _halo: MeshInstance3D
var _mats: Array[ShaderMaterial] = []
var _light: OmniLight3D
var _motes: CPUParticles3D
var _strength_now := 0.0
var _strength_target := 0.0


## The stage of `side`'s pad for a replicated Mid state (pure).
static func stage_of(owner: int, pad_side: int, beacon: int) -> int:
	if owner != pad_side:
		return Stage.DORMANT
	match beacon:
		ProgressionSystem.Beacon.ATTUNING:
			return Stage.ATTUNING
		ProgressionSystem.Beacon.READY:
			return Stage.READY
		ProgressionSystem.Beacon.UNDER_ATTACK:
			return Stage.UNDER_ATTACK
	return Stage.DORMANT


## Lit lenses at `s` with attunement `frac` (pure).
static func lamps_lit(s: int, frac: float) -> int:
	match s:
		Stage.ATTUNING:
			return clampi(floori(frac * LAMPS + 0.001), 0, LAMPS)
		Stage.READY, Stage.UNDER_ATTACK:
			return LAMPS
	return 0


static func available() -> bool:
	return WorldModel.exists(KEY)


func setup(pad_side: int, d: ForwardBeaconDef = null) -> void:
	side = pad_side
	def = d if d != null else ForwardBeaconDef.shared()
	name = "ForwardBeacon_%d" % side
	_model = WorldModel.instantiate(KEY, side)
	_model.name = "Model"
	add_child(_model)
	var c := ModelPalette.team_color(side)
	var cyl := CylinderMesh.new()
	cyl.top_radius = def.mast_radius_m
	cyl.bottom_radius = def.mast_radius_m * 1.6
	cyl.height = def.mast_height_m
	cyl.radial_segments = 10
	cyl.rings = 1
	_mast = _holo_mesh("Mast", cyl, 0, c)
	_mast.position.y = 0.12 + def.mast_height_m * 0.5
	var bar := BoxMesh.new()
	bar.size = Vector3(def.banner_size_m.x + 0.3, 0.06, 0.06)
	var arm := _holo_mesh("Crossbar", bar, 0, c)
	arm.position = Vector3(0, 0.12 + def.mast_height_m - 0.25, 0)
	var q := QuadMesh.new()
	q.size = def.banner_size_m
	q.subdivide_depth = 8
	_banner = _holo_mesh("Banner", q, 1, c)
	_banner.position = Vector3(0, 0.12 + def.mast_height_m - 0.3 - def.banner_size_m.y * 0.5, 0.0)
	var hq := QuadMesh.new()
	hq.size = Vector2.ONE * def.halo_radius_m * 2.0
	_halo = _holo_mesh("Halo", hq, 2, c)
	_halo.rotation.x = -PI * 0.5
	_halo.position.y = 0.14
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = c
	_light.omni_range = def.light_range_m
	_light.shadow_enabled = false
	_light.position.y = 1.2
	_light.light_energy = 0.0
	add_child(_light)
	_motes = CPUParticles3D.new()
	_motes.name = "Motes"
	_motes.emitting = false
	_motes.one_shot = true
	_motes.amount = 36
	_motes.lifetime = 1.6
	_motes.explosiveness = 0.7
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_motes.emission_ring_axis = Vector3.UP
	_motes.emission_ring_radius = def.halo_radius_m * 0.85
	_motes.emission_ring_inner_radius = def.halo_radius_m * 0.6
	_motes.emission_ring_height = 0.05
	_motes.direction = Vector3.UP
	_motes.spread = 8.0
	_motes.gravity = Vector3.ZERO
	_motes.initial_velocity_min = 2.0
	_motes.initial_velocity_max = 4.5
	_motes.scale_amount_min = 0.05
	_motes.scale_amount_max = 0.1
	_motes.color = c.lightened(0.35)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var mq := QuadMesh.new()
	mq.size = Vector2.ONE
	mq.material = pm
	_motes.mesh = mq
	_motes.position.y = 0.2
	add_child(_motes)
	_show(Stage.DORMANT, 0.0)
	_strength_now = _strength_target
	_push_strength()


## Applies a replicated Mid state; returns true when the stage changed.
func apply_state(owner: int, beacon: int, frac: float) -> bool:
	var s := stage_of(owner, side, beacon)
	var f := frac if s == Stage.ATTUNING else (1.0 if s != Stage.DORMANT else 0.0)
	if s == stage and is_equal_approx(f, attune):
		return false
	var prev := stage
	_show(s, f)
	if s == Stage.READY and prev != Stage.READY and prev != Stage.UNDER_ATTACK:
		_motes.restart()
		_motes.emitting = true
	return s != prev


## The pad's spawn spots for the Mid `d` on `md`: [side, spot] per HQ, spot =
## where that side's heroes appear (ProgressionSystem.beacon_spot).
static func spots(md: MapDef, d: HardpointDef) -> Array:
	var out: Array = []
	if d.tier != HardpointDef.Tier.MID:
		return out
	for hq: HqDef in md.hqs:
		out.append([hq.team, ProgressionSystem.beacon_spot(d.position, hq.sanctum, d.zone_radius)])
	return out


## The pad's local bounds and its ground contact (the disc's 4 rim points).
static func pad_box() -> AABB:
	return AABB(Vector3(-PAD_RADIUS_M, 0.0, -PAD_RADIUS_M), Vector3(PAD_RADIUS_M * 2.0, PAD_HEIGHT_M, PAD_RADIUS_M * 2.0))


## The 4 rim points of a disc of radius `r` (default: the pad), turned by `turn` rad.
static func pad_foot(xf: Transform3D, r: float = PAD_RADIUS_M * 0.98, turn: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in 4:
		var a := turn + i * PI * 0.5
		out.append(xf * Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out


## Ground footprint radius: the pad, or the halo when that is wider (it lies on
## the floor too and must not hang over a step).
static func foot_radius(d: ForwardBeaconDef = null) -> float:
	var bd := d if d != null else ForwardBeaconDef.shared()
	return maxf(PAD_RADIUS_M, bd.halo_radius_m) * 0.98


## Where the pad goes for `spot` (Mid centre `at`): on the floor under the spot,
## or, when the disc and its halo (foot_radius) would not lie level there, the nearest level place within
## PLACE_REACH_M (toward the centre first, then away from it). Faces the centre.
## Same check as PlacementValidator (PlacementKit.support_at, `tol`).
static func place(space: PhysicsDirectSpaceState3D, at: Vector3, spot: Vector3, tol: float = 0.06) -> Transform3D:
	var inward := Vector3(at.x - spot.x, 0.0, at.z - spot.z)
	inward = inward.normalized() if inward.length_squared() > 1e-6 else Vector3.FORWARD
	var basis := Basis.looking_at(inward, Vector3.UP)
	var first := Transform3D()
	var found := false
	var steps := int(PLACE_REACH_M / PLACE_STEP_M)
	for k in steps * 2 + 1:
		var d := ceilf(k / 2.0) * PLACE_STEP_M * (1.0 if k % 2 == 1 else -1.0)
		var p := spot + inward * d
		var g := PlacementKit.ground(space, p + Vector3.UP * 1.0, 0.5, 3.0)
		if g.is_empty():
			continue
		var xf := Transform3D(basis, g.pos)
		if not found:
			first = xf
			found = true
		var r := foot_radius()
		var pts := pad_foot(xf, r)
		pts.append_array(pad_foot(xf, r, PI * 0.25))
		pts.append(xf.origin)
		if PlacementKit.support_at(space, pts, tol) >= 1.0:
			return xf
	return first if found else Transform3D(basis, spot)


## A piece's MeshInstance3D (tests).
func piece(n: StringName) -> MeshInstance3D:
	return WorldModel.piece(_model, n)


## The hard-light strength the pad is fading toward (tests).
func strength_target() -> float:
	return _strength_target


## True while the mast / banner / halo are drawn.
func holo_visible() -> bool:
	return _mast.visible


func _holo_mesh(n: String, mesh: Mesh, part: int, c: Color) -> MeshInstance3D:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	m.set_shader_parameter("part", part)
	m.set_shader_parameter("color", c.lightened(0.15))
	m.set_shader_parameter("strobe_hz", def.strobe_hz)
	_mats.append(m)
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _show(s: int, frac: float) -> void:
	stage = s
	attune = frac
	var lit := lamps_lit(s, frac)
	for i in LAMPS:
		var mi := piece(StringName("lamp_%d" % (i + 1)))
		if mi != null:
			mi.visible = i < lit
	var core := piece(&"core")
	if core != null:
		core.visible = s != Stage.DORMANT
	var gs := GameSettings.shared()
	var reduced := gs != null and gs.reduce_motion
	var strobe := 1.0 if s == Stage.UNDER_ATTACK and not reduced else 0.0
	var dim := 1.0
	if s == Stage.UNDER_ATTACK and reduced:
		dim = 0.55  # reduce motion: steady and dimmer instead of blinking
	for m in _mats:
		m.set_shader_parameter("build", frac if s == Stage.ATTUNING else 1.0)
		m.set_shader_parameter("strobe", strobe)
		m.set_shader_parameter("wave", 0.0 if reduced else 1.0)
	match s:
		Stage.ATTUNING:
			_strength_target = def.attuning_strength
		Stage.READY:
			_strength_target = def.ready_strength
		Stage.UNDER_ATTACK:
			_strength_target = def.threat_strength * dim
		_:
			_strength_target = 0.0
	if _light != null:
		_push_strength()


func _push_strength() -> void:
	for m in _mats:
		m.set_shader_parameter("strength", _strength_now)
	var on := _strength_now > 0.001
	for mi in [_mast, _banner, _halo, get_node_or_null("Crossbar")]:
		if mi != null:
			(mi as Node3D).visible = on
	_light.light_energy = def.light_energy * _strength_now * (0.35 + 0.65 * attune)


func _process(delta: float) -> void:
	if _strength_now != _strength_target:
		_strength_now = move_toward(_strength_now, _strength_target, delta / def.fade_s)
		_push_strength()
