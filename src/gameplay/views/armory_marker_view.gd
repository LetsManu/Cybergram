class_name ArmoryMarkerView
extends Node3D
## Client-only world marker of the own team's Armory pad (W21-G2): a glowing
## team-coloured floor ring exactly as large as the server's `at_armory` radius,
## a light beacon visible over the HQ walls and an "ARMORY" sign readable in
## first person. Ring and beacon pulse softly while the hero has Lumen to spend
## (steady with GameSettings.reduce_motion). Quality LOW drops the disc and the
## beacon. Never created on the headless server; reads replicated state only.
##
## Created per own-team HQ by ClientWorld.setup_objectives (see the snippet in
## the W21-G2 report).

const BEACON_SHADER := "res://assets/shaders/armory_beacon.gdshader"

var def: ArmoryMarkerDef
## Server radius the ring is drawn at (EconomyRulesDef.armory_radius_m).
var radius_m: float = 6.0
var team: int = 0
var client: ClientWorld

var _ring_mat: StandardMaterial3D
var _disc_mat: StandardMaterial3D
var _beacon_mat: ShaderMaterial
var _sign: Label3D
var _base: Color = Color.WHITE
var _t: float = 0.0
var _cheapest: int = -1
## 0..1 pulse brightness factor of the last frame (tests).
var pulse_k: float = 1.0


## Builds the meshes for `hq`'s Armory pad. `def_` null loads the default .tres.
func setup(hq: HqDef, radius: float, c: ClientWorld, def_: ArmoryMarkerDef = null) -> void:
	def = def_ if def_ != null else load(ArmoryMarkerDef.DEFAULT_PATH) as ArmoryMarkerDef
	radius_m = radius
	team = hq.team
	client = c
	name = "ArmoryMarker%d" % team
	position = hq.armory
	_base = HardpointView.team_color(team).lerp(Color.WHITE, def.white_mix)
	var q := GameSettings.shared().graphics_quality if GameSettings.shared() != null else GameSettings.Quality.HIGH
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius_m - def.ring_width_m, 0.05)
	torus.outer_radius = radius_m
	torus.rings = 64 if q >= GameSettings.Quality.MEDIUM else 32
	torus.ring_segments = 4
	_ring_mat = _unshaded(Color(_base, def.ring_alpha))
	torus.material = _ring_mat
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.12, 1.0)  # flat band: the torus tube is squashed to the floor
	ring.position.y = def.ring_lift_m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	if q >= GameSettings.Quality.MEDIUM and def.disc_alpha > 0.0:
		var disc := CylinderMesh.new()
		disc.top_radius = radius_m
		disc.bottom_radius = radius_m
		disc.height = 0.01
		disc.radial_segments = 48
		_disc_mat = _unshaded(Color(_base, def.disc_alpha))
		disc.material = _disc_mat
		var d := MeshInstance3D.new()
		d.name = "Disc"
		d.mesh = disc
		d.position.y = def.ring_lift_m * 0.5
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
	if q >= GameSettings.Quality.MEDIUM:
		var col := CylinderMesh.new()
		col.top_radius = def.beacon_radius_m
		col.bottom_radius = def.beacon_radius_m
		col.height = def.beacon_height_m
		col.radial_segments = 12
		col.cap_top = false
		col.cap_bottom = false
		_beacon_mat = ShaderMaterial.new()
		_beacon_mat.shader = load(BEACON_SHADER) as Shader
		_beacon_mat.set_shader_parameter("tint", _base)
		_beacon_mat.set_shader_parameter("height", def.beacon_height_m)
		_beacon_mat.set_shader_parameter("strength", def.beacon_alpha)
		col.material = _beacon_mat
		var b := MeshInstance3D.new()
		b.name = "Beacon"
		b.mesh = col
		b.position.y = def.beacon_height_m * 0.5
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
	_sign = HardpointView.make_world_label()
	_sign.name = "Sign"
	_sign.text = tr("HUD_ARMORY_SIGN")
	_sign.font_size = def.sign_font_size
	_sign.position.y = def.sign_height_m
	_sign.modulate = _base.lightened(0.2)
	add_child(_sign)


## Radius the ring spans (outer edge), for tests.
func ring_outer_radius() -> float:
	var r := get_node_or_null("Ring") as MeshInstance3D
	return (r.mesh as TorusMesh).outer_radius if r != null else 0.0


## Pulse brightness factor: 1.0 steady; with `spend` a sine swing down by
## `depth` at `hz`. `reduced` (reduce motion) always returns 1.0.
static func pulse_factor(t: float, spend: bool, reduced: bool, hz: float, depth: float) -> float:
	if not spend or reduced:
		return 1.0
	return 1.0 - depth * (0.5 - 0.5 * cos(t * TAU * hz))


## Sign alpha for a camera `dist` metres from the pad centre.
static func sign_alpha(dist: float, hide_within: float, far: float) -> float:
	if dist <= hide_within:
		return 0.0
	return clampf(1.0 - (dist - far * 0.6) / (far * 0.4), 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	var gs := GameSettings.shared()
	var spend := _has_lumen_to_spend()
	pulse_k = pulse_factor(_t, spend, gs != null and gs.reduce_motion, def.pulse_hz, def.pulse_depth)
	_ring_mat.albedo_color = Color(_base * pulse_k, def.ring_alpha)
	if _disc_mat != null:
		_disc_mat.albedo_color = Color(_base, def.disc_alpha * (1.5 - 0.5 * pulse_k) if spend else def.disc_alpha)
	if _beacon_mat != null:
		_beacon_mat.set_shader_parameter("strength", def.beacon_alpha * pulse_k)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and _sign != null:
		var a := sign_alpha(Vector2(cam.global_position.x - global_position.x, cam.global_position.z - global_position.z).length(),
			def.sign_hide_within_m, def.sign_far_m)
		_sign.visible = a > 0.01
		_sign.modulate = Color(_base.lightened(0.2), a)
		_sign.outline_modulate = Color(0.0, 0.0, 0.0, a * 0.85)


## True when the own hero can pay for the cheapest catalog line (replicated Lumen).
func _has_lumen_to_spend() -> bool:
	if client == null or client.progress == null or client.catalog == null:
		return false
	if _cheapest < 0:
		for it in client.catalog.items:
			if it != null and it.tiers() > 0 and (_cheapest < 0 or it.price(1) < _cheapest):
				_cheapest = it.price(1)
		if _cheapest < 0:
			return false
	return client.progress.lumen >= _cheapest


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
