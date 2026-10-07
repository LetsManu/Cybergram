class_name TracerFx
extends Node3D
## Client-only bullet tracers (presentation; no gameplay state). Each shot
## draws a thin glowing streak from the shooter's muzzle to where the pellet
## stopped, plus a small impact spark, both fading out over LIFETIME_S.
## Streaks are pooled MeshInstance3Ds; the oldest is reused when the pool is full.
## Armory v2 (weapons-and-mods.md §3.6.3 / §3.7.1, items-and-armory.md §3.5.4):
## the shooter's Ammo Type picks colour, width, length / linger and the impact
## shape (puncture, debris, flame, crackle ring, siphon mote, frost bloom), and
## the Ammo Mod thickens, lingers or brightens it. Colour is never the only
## channel: every type also differs in width, shape or impact. Data:
## ArmoryVisualsData.ammo_tell() / mod_tell().

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
## Per pool entry: streak lifetime, spark lifetime, spark drift (m/s; Siphon mote).
var _life: PackedFloat32Array = PackedFloat32Array()
var _spark_life: PackedFloat32Array = PackedFloat32Array()
var _spark_vel: PackedVector3Array = PackedVector3Array()
var _arcs: Array[MeshInstance3D] = []
var _impact_meshes: Dictionary = {}
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
	_impact_meshes[&"spark"] = spark
	_impact_meshes[&"puncture"] = _sphere(SPARK_SIZE * 0.3)
	_impact_meshes[&"mote"] = _sphere(SPARK_SIZE * 0.35)
	_impact_meshes[&"bloom"] = _sphere(SPARK_SIZE * 1.1)
	var ring := TorusMesh.new()
	ring.inner_radius = SPARK_SIZE * 0.8
	ring.outer_radius = SPARK_SIZE
	ring.rings = 12
	ring.ring_segments = 4
	_impact_meshes[&"ring"] = ring
	var flame := PrismMesh.new()
	flame.size = Vector3(SPARK_SIZE * 0.6, SPARK_SIZE * 1.8, SPARK_SIZE * 0.6)
	_impact_meshes[&"flame"] = flame
	var chunk := BoxMesh.new()
	chunk.size = Vector3.ONE * SPARK_SIZE * 0.7
	_impact_meshes[&"debris"] = chunk
	for i in POOL_SIZE:
		_streaks.append(_make(box))
		_sparks.append(_make(spark))
		_arcs.append(_make(box))
	_life.resize(POOL_SIZE)
	_life.fill(LIFETIME_S)
	_spark_life.resize(POOL_SIZE)
	_spark_life.fill(SPARK_LIFETIME_S)
	_spark_vel.resize(POOL_SIZE)
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


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


## Draws one tracer. `own` marks the local player's shot (skips the first
## metres so it starts past the crosshair). `ammo` / `mod` are the shooter's
## DamageMath ammo type and mod (0 = Standard / none: the plain team tracer).
func spawn(from: Vector3, to: Vector3, color: Color, own: bool = false, ammo: int = 0, mod: int = 0) -> void:
	var tell := ArmoryVisualsData.ammo_tell(ammo)
	var mt := ArmoryVisualsData.mod_tell(mod) if ammo > 0 else {}
	color = ArmoryVisualsData.ammo_color(ammo, color)
	var width := float(tell.get("width", 1.0)) * float(mt.get("width", 1.0))
	var life := LIFETIME_S * float(tell.get("length", 1.0)) + float(mt.get("linger_s", 0.0))
	if mt.has("glow"):
		color = color.lightened(0.25)
	var shape := StringName(tell.get("shape", "plain"))
	var impact := StringName(tell.get("impact", "spark"))
	var d := to - from
	var len := d.length()
	if own and len > OWN_START_SKIP_M * 2.0:
		from += d / len * OWN_START_SKIP_M
		d = to - from
		len = d.length()
	var i := _next
	_next = (_next + 1) % POOL_SIZE
	var s := _streaks[i]
	_life[i] = life
	var basis := Basis.IDENTITY
	if len > 0.05:
		basis = Basis.looking_at(d / len, _up_for(d))
		s.global_transform = Transform3D(basis, from + d * 0.5)
		s.scale = Vector3(width, width, len)
		(s.material_override as StandardMaterial3D).albedo_color = color
		s.visible = true
		_age[i] = 0.0
	# Shock: a second, offset streak reads as a forked arc; Cryo: a white core.
	var a := _arcs[i]
	a.visible = false
	if len > 0.05 and (shape == &"arc" or shape == &"frost"):
		var off := basis.x * (0.06 if shape == &"arc" else 0.0)
		a.global_transform = Transform3D(basis.rotated(d / len, 0.5 if shape == &"arc" else 0.0), from + d * 0.5 + off)
		a.scale = Vector3(0.5, 0.5, len * (0.8 if shape == &"arc" else 1.0))
		(a.material_override as StandardMaterial3D).albedo_color = Color.WHITE if shape == &"frost" else color.lightened(0.4)
		a.visible = true
	var k := _sparks[i]
	k.mesh = _impact_meshes.get(impact, _impact_meshes[&"spark"])
	k.global_position = to
	k.rotation = Vector3(PI * 0.5, 0.0, 0.0) if impact == &"ring" else Vector3.ZERO
	(k.material_override as StandardMaterial3D).albedo_color = color
	k.visible = true
	_spark_age[i] = 0.0
	_spark_life[i] = SPARK_LIFETIME_S * (2.5 if impact in [&"mote", &"bloom", &"flame"] else 1.0)
	# Siphon: the mote drifts back toward the shooter (§3.5.4 "mote drawn back").
	_spark_vel[i] = (from - to).normalized() * minf(len, 6.0) / _spark_life[i] if impact == &"mote" and len > 0.05 else Vector3.ZERO


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
			if _age[i] >= _life[i]:
				s.visible = false
				_arcs[i].visible = false
				_age[i] = INF
			else:
				var m := s.material_override as StandardMaterial3D
				m.albedo_color.a = 1.0 - _age[i] / _life[i]
				if _arcs[i].visible:
					(_arcs[i].material_override as StandardMaterial3D).albedo_color.a = m.albedo_color.a
		if _spark_age[i] < INF:
			_spark_age[i] += delta
			var k := _sparks[i]
			if _spark_age[i] >= _spark_life[i]:
				k.visible = false
				_spark_age[i] = INF
			else:
				k.global_position += _spark_vel[i] * delta
				var km := k.material_override as StandardMaterial3D
				km.albedo_color.a = 1.0 - _spark_age[i] / _spark_life[i]
