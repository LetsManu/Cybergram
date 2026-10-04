class_name TracerFx
extends Node3D
## Client-only bullet tracers (presentation; no gameplay state). Each shot
## draws a thin glowing streak from the shooter's muzzle to where the pellet
## stopped, plus a small impact spark, both fading out over LIFETIME_S.
## Streaks are pooled MeshInstance3Ds; the oldest is reused when the pool is full.

const POOL_SIZE: int = 48
const LIFETIME_S: float = 0.14
const SPARK_LIFETIME_S: float = 0.12
const WIDTH: float = 0.035
const SPARK_SIZE: float = 0.12
## Skip the first few centimetres past the muzzle so the streak does not
## start as a fat blob right at the camera.
const OWN_START_SKIP_M: float = 0.3

var _streaks: Array[MeshInstance3D] = []
var _sparks: Array[MeshInstance3D] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _spark_age: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
## Combat VFX director (null on the headless server).
var fx: FxDirector


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, WIDTH, 1.0)
	var spark := SphereMesh.new()
	spark.radius = SPARK_SIZE * 0.5
	spark.height = SPARK_SIZE
	spark.radial_segments = 8
	spark.rings = 4
	for i in POOL_SIZE:
		_streaks.append(_make(box))
		_sparks.append(_make(spark))
	_age.resize(POOL_SIZE)
	_spark_age.resize(POOL_SIZE)
	_age.fill(INF)
	_spark_age.fill(INF)
	# G1: muzzle flash / impact / hit / death VFX, client only (the parent is the
	# ClientWorld; the headless server builds no visuals).
	if not GfxQuality.is_headless():
		fx = FxDirector.new()
		fx.name = "Fx"
		fx.client = get_parent()
		add_child(fx)


func _make(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Additive so streaks glow on both the pale floor and the dark sky.
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	mi.visible = false
	mi.top_level = true
	add_child(mi)
	return mi


## Draws one tracer. `own` marks the local player's shot (skips the first
## metres so it starts past the crosshair).
func spawn(from: Vector3, to: Vector3, color: Color, own: bool = false) -> void:
	var d := to - from
	var len := d.length()
	if own and len > OWN_START_SKIP_M * 2.0:
		from += d / len * OWN_START_SKIP_M
		d = to - from
		len = d.length()
	var i := _next
	_next = (_next + 1) % POOL_SIZE
	var s := _streaks[i]
	if len > 0.05:
		s.global_transform = Transform3D(Basis.looking_at(d / len, _up_for(d)), from + d * 0.5)
		s.scale = Vector3(1.0, 1.0, len)
		(s.material_override as StandardMaterial3D).albedo_color = color
		s.visible = true
		_age[i] = 0.0
	var k := _sparks[i]
	k.global_position = to
	(k.material_override as StandardMaterial3D).albedo_color = color
	k.visible = true
	_spark_age[i] = 0.0


## Number of streaks currently drawn (tests).
func active_count() -> int:
	var n := 0
	for s in _streaks:
		if s.visible:
			n += 1
	return n


func _up_for(d: Vector3) -> Vector3:
	return Vector3.RIGHT if absf(d.normalized().y) > 0.99 else Vector3.UP


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _age[i] < INF:
			_age[i] += delta
			var s := _streaks[i]
			if _age[i] >= LIFETIME_S:
				s.visible = false
				_age[i] = INF
			else:
				var m := s.material_override as StandardMaterial3D
				m.albedo_color.a = 1.0 - _age[i] / LIFETIME_S
		if _spark_age[i] < INF:
			_spark_age[i] += delta
			var k := _sparks[i]
			if _spark_age[i] >= SPARK_LIFETIME_S:
				k.visible = false
				_spark_age[i] = INF
			else:
				var km := k.material_override as StandardMaterial3D
				km.albedo_color.a = 1.0 - _spark_age[i] / SPARK_LIFETIME_S
