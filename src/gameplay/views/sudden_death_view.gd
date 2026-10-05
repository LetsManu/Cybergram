class_name SuddenDeathView
extends Node3D
## Client-side Sudden Death ring wall (W16-SDWATER; match-flow-and-map.md §3.1).
## A translucent glowing cylinder at the ring radius, in the team-neutral danger
## colour, ink/toon styled (assets/shaders/spatial_env_ring_wall.gdshader). It
## shrinks smoothly with the server's ring (same radius function, see
## SuddenDeathRing). Presentation only; the server owns the damage.
##
## Comfort: the shimmer animation scales with GameSettings.comfort_fx_intensity
## and is static with reduce_motion.
##
## Damage-direction hook for the HUD (ComfortOverlay): `SuddenDeathView.safe_point
## (client, own_pos)` returns the world point to point the damage indicator at
## while the local hero stands outside the ring, else null.

const SHADER := "res://assets/shaders/spatial_env_ring_wall.gdshader"
const WALL_HEIGHT_M: float = 18.0
const SEGMENTS: int = 96

## Model fed by ClientWorld from each snapshot.
var ring: SuddenDeathRing
## Injectable for tests; null = process-wide settings.
var settings: GameSettings
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _shown_r: float = -1.0
var _t: float = 0.0


func setup(ring_: SuddenDeathRing) -> void:
	ring = ring_
	name = "SuddenDeathView"
	visible = false
	if GfxQuality.is_headless():
		set_process(false)
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = SEGMENTS
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER) as Shader
	_mat.set_shader_parameter("color", Color(HudPalette.DANGER, 1.0))
	_mat.set_shader_parameter("height_m", WALL_HEIGHT_M)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cyl
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 500.0
	add_child(_mesh)


func _process(delta: float) -> void:
	if ring == null or _mesh == null:
		return
	visible = ring.active
	if not ring.active:
		_shown_r = -1.0
		return
	var r := ring.radius()
	# Ease toward the replicated radius (snapshots are discrete steps).
	_shown_r = r if _shown_r < 0.0 else lerpf(_shown_r, r, clampf(delta * 10.0, 0.0, 1.0))
	_t += delta
	global_position = ring.centre
	_mesh.position.y = WALL_HEIGHT_M * 0.5 - 1.0
	_mesh.scale = Vector3(_shown_r, WALL_HEIGHT_M, _shown_r)
	var gs := settings if settings != null else GameSettings.shared()
	_mat.set_shader_parameter("circumference", TAU * _shown_r)
	_mat.set_shader_parameter("shimmer", shimmer_amount(gs.comfort_fx_intensity, UiKit.reduce_motion()))
	_mat.set_shader_parameter("time_s", 0.0 if UiKit.reduce_motion() else _t)


## Shimmer 0..1: the comfort effects intensity, forced to 0 (static wall) by
## reduce-motion.
static func shimmer_amount(fx_intensity: float, reduce_motion: bool) -> float:
	return 0.0 if reduce_motion else clampf(fx_intensity, 0.0, 1.0)


## HUD hook: the point the damage indicator should face while the local hero is
## outside the ring (the ring centre at the hero's height), else null.
## `client` is the ClientWorld (duck-typed).
static func safe_point(client: Variant, own_pos: Vector3) -> Variant:
	if client == null:
		return null
	var r: SuddenDeathRing = client.get("sudden_death")
	return r.safe_point(own_pos) if r != null else null
