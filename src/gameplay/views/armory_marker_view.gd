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
## Phase 6e: the hero-pipeline Armory stall (tools/art/world/armory_stall.py)
## stands at the back of the pad, its counter facing the Sanctum; the sign sits
## on its sign board. Visual only (no collision, navmesh unchanged).
const STALL_KEY: StringName = &"armory_stall"
const STALL_BACK_M: float = 2.5
const STALL_SIGN_Y: float = 4.55

var def: ArmoryMarkerDef
## Server radius the ring is drawn at (EconomyRulesDef.armory_radius_m, read in setup()).
var radius_m: float = 0.0
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
var _spend_shown: bool = false
var _sign_a: float = -1.0
var _sign_col: Color = Color.WHITE
## The stall model (null when not built).
var stall: Node3D


## Builds the meshes for `hq`'s Armory pad. The ring radius is the server's
## EconomyRulesDef.armory_radius_m (`econ_` null loads the game's rules .tres);
## `def_` null loads the default marker .tres.
func setup(hq: HqDef, c: ClientWorld, def_: ArmoryMarkerDef = null, econ_: EconomyRulesDef = null) -> void:
	def = def_ if def_ != null else load(ArmoryMarkerDef.DEFAULT_PATH) as ArmoryMarkerDef
	var econ := econ_ if econ_ != null else load(GameSession.ECONOMY_RULES) as EconomyRulesDef
	radius_m = econ.armory_radius_m
	team = hq.team
	client = c
	name = "ArmoryMarker%d" % team
	position = hq.armory
	_base = HardpointView.team_color(team).lerp(Color.WHITE, def.white_mix)
	var q := GameSettings.shared().graphics_quality if GameSettings.shared() != null else GameSettings.Quality.HIGH
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius_m - def.ring_width_m, 0.05)
	torus.outer_radius = radius_m
	torus.rings = def.ring_segments if q >= GameSettings.Quality.MEDIUM else def.ring_segments_low
	torus.ring_segments = 4
	_ring_mat = _unshaded(Color(_base, def.ring_alpha))
	torus.material = _ring_mat
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = torus
	ring.scale = Vector3(1.0, def.ring_squash_y, 1.0)  # flat band: the torus tube is squashed to the floor
	ring.position.y = def.ring_lift_m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	if q >= GameSettings.Quality.MEDIUM and def.disc_alpha > 0.0:
		var disc := CylinderMesh.new()
		disc.top_radius = radius_m
		disc.bottom_radius = radius_m
		disc.height = 0.01
		disc.radial_segments = def.ring_segments
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
		col.radial_segments = def.beacon_segments
		col.cap_top = false
		col.cap_bottom = false
		_beacon_mat = ShaderMaterial.new()
		_beacon_mat.shader = load(BEACON_SHADER) as Shader
		_beacon_mat.set_shader_parameter("tint", HardpointView.team_color(team))
		_beacon_mat.set_shader_parameter("height", def.beacon_height_m)
		_beacon_mat.set_shader_parameter("strength", def.beacon_alpha)
		col.material = _beacon_mat
		var b := MeshInstance3D.new()
		b.name = "Beacon"
		b.mesh = col
		b.position.y = def.beacon_height_m * 0.5
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
	var to_sanctum := (hq.sanctum - hq.armory) * Vector3(1, 0, 1)
	if WorldModel.exists(STALL_KEY):
		stall = WorldModel.instantiate(STALL_KEY, team)
		stall.name = "Stall"
		var face := to_sanctum.normalized() if to_sanctum.length() > 0.1 else Vector3.FORWARD
		stall.position = -face * STALL_BACK_M
		stall.rotation.y = atan2(-face.x, -face.z)  # model front is -Z
		add_child(stall)
	HudStrings.ensure_loaded()  # the world is built before the HUD loads its strings
	_sign = HardpointView.make_world_label()
	_sign.name = "Sign"
	_sign.text = tr("HUD_ARMORY_SIGN")
	_sign.font_size = def.sign_font_size
	_sign.pixel_size = def.sign_pixel_size
	_sign.position.y = def.sign_height_m
	if stall != null:
		_sign.position = stall.position + stall.basis * Vector3(0.0, STALL_SIGN_Y, -1.35)
	_sign_col = _base.lightened(0.2)
	_sign.modulate = _sign_col
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
	var k := pulse_factor(_t, spend, gs != null and gs.reduce_motion, def.pulse_hz, def.pulse_depth)
	# Only touch the materials when the (quantised) pulse actually moved.
	if absf(k - pulse_k) > 0.01 or spend != _spend_shown:
		pulse_k = k
		_spend_shown = spend
		_ring_mat.albedo_color = Color(_base * k, def.ring_alpha)
		if _disc_mat != null:
			_disc_mat.albedo_color = Color(_base, def.disc_alpha * (1.5 - 0.5 * k) if spend else def.disc_alpha)
		if _beacon_mat != null:
			_beacon_mat.set_shader_parameter("strength", def.beacon_alpha * k)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and _sign != null:
		var a := snappedf(sign_alpha(Vector2(cam.global_position.x - global_position.x, cam.global_position.z - global_position.z).length(),
			def.sign_hide_within_m, def.sign_far_m), 0.02)
		if a != _sign_a:
			_sign_a = a
			_sign.visible = a > 0.01
			_sign.modulate = Color(_sign_col, a)
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
