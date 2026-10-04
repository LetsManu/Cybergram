class_name FxDirector
extends Node3D
## Client-only combat VFX (chunk G1; presentation, no gameplay state). Created by
## TracerFx on clients (never on the headless server) and driven by the
## ClientWorld signals shot_received / hit_confirmed / kill_received:
##   shot        -> muzzle flash quad + short OmniLight at the muzzle, impact
##                  sparks + glow where the pellet stopped
##   hit confirm -> brief additive flash over the hit hero's meshes
##   kill        -> death burst (ring, sparks, light) at the victim
##   respawn     -> a hero view turning visible again gets a rising ring + motes
## Everything is pooled (no allocation per shot) and scaled by GfxQuality.

const FLASH_SHADER := "res://assets/shaders/spatial_env_flash.gdshader"
const FLASH_POOL: int = 40
const PARTICLE_POOL: int = 14
const HIT_FLASH_S: float = 0.09
const SAME_SHOOTER_GAP_MS: int = 40
const REMOTE_MUZZLE_H: float = 1.45
## Impacts farther than this from the muzzle are max-range misses: no sparks.
const IMPACT_MAX_RANGE_M: float = 140.0
const COLOR_OWN := Color(1.0, 0.82, 0.35)
const COLOR_ALLY := Color(0.45, 0.72, 1.0)
const COLOR_ENEMY := Color(1.0, 0.42, 0.2)

## The ClientWorld (duck-typed: signals + `rig`, `session`, `remote_views()`).
var client: Node

var _lvl: int = GfxQuality.HIGH
var _k: float = 1.0
var _flashes: Array[MeshInstance3D] = []
var _flash_age: PackedFloat32Array = PackedFloat32Array()
var _flash_life: PackedFloat32Array = PackedFloat32Array()
var _flash_size: PackedFloat32Array = PackedFloat32Array()
var _next_flash: int = 0
var _lights: Array[OmniLight3D] = []
var _light_age: PackedFloat32Array = PackedFloat32Array()
var _light_life: PackedFloat32Array = PackedFloat32Array()
var _light_energy: PackedFloat32Array = PackedFloat32Array()
var _next_light: int = 0
var _parts: Array[CPUParticles3D] = []
var _next_part: int = 0
var _last_shot_ms: Dictionary = {}
var _hit_flash: Dictionary = {}  # HeroView -> seconds left
var _was_visible: Dictionary = {}  # net id -> bool
var _poll_t: float = 0.0
var _overlay: StandardMaterial3D


func _ready() -> void:
	if GfxQuality.is_headless():
		set_process(false)
		return
	_lvl = GfxQuality.level()
	_k = GfxQuality.particle_scale(_lvl)
	var shader := load(FLASH_SHADER) as Shader
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for i in FLASH_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var m := ShaderMaterial.new()
		m.shader = shader
		mi.material_override = m
		mi.top_level = true
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		add_child(mi)
		_flashes.append(mi)
	_flash_age.resize(FLASH_POOL)
	_flash_life.resize(FLASH_POOL)
	_flash_size.resize(FLASH_POOL)
	_flash_age.fill(INF)
	var n_lights := GfxQuality.muzzle_lights(_lvl)
	for i in n_lights:
		var l := OmniLight3D.new()
		l.top_level = true
		l.visible = false
		l.shadow_enabled = false
		add_child(l)
		_lights.append(l)
	_light_age.resize(n_lights)
	_light_life.resize(n_lights)
	_light_energy.resize(n_lights)
	_light_age.fill(INF)
	var sph := SphereMesh.new()
	sph.radius = 0.035
	sph.height = 0.07
	sph.radial_segments = 4
	sph.rings = 2
	for i in PARTICLE_POOL:
		var p := CPUParticles3D.new()
		p.top_level = true
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 0.95
		p.mesh = sph
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.vertex_color_use_as_albedo = true
		p.material_override = pm
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		p.scale_amount_curve = curve
		add_child(p)
		_parts.append(p)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(0.55, 0.16, 0.12)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if client != null:
		if client.has_signal("shot_received"):
			client.connect("shot_received", _on_shot)
		if client.has_signal("hit_confirmed"):
			client.connect("hit_confirmed", _on_hit)
		if client.has_signal("kill_received"):
			client.connect("kill_received", _on_kill)


# ------------------------------------------------------------ primitives

## One pooled additive billboard (`ring` = expanding ring, else a soft star).
func flash(pos: Vector3, color: Color, size: float, life: float, ring: bool = false, energy: float = 1.6) -> void:
	if _flashes.is_empty():
		return
	var i := _next_flash
	_next_flash = (_next_flash + 1) % FLASH_POOL
	var mi := _flashes[i]
	mi.global_position = pos
	mi.scale = Vector3(size, size, 1.0)
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("ring", 1.0 if ring else 0.0)
	m.set_shader_parameter("progress", 0.0)
	mi.visible = true
	_flash_age[i] = 0.0
	_flash_life[i] = life
	_flash_size[i] = size


## One pooled short OmniLight (a no-op on the Low tier, which pools none).
func pulse_light(pos: Vector3, color: Color, energy: float, range_m: float, life: float) -> void:
	if _lights.is_empty():
		return
	var i := _next_light
	_next_light = (_next_light + 1) % _lights.size()
	var l := _lights[i]
	l.global_position = pos
	l.light_color = color
	l.omni_range = range_m
	l.light_energy = energy
	l.visible = true
	_light_age[i] = 0.0
	_light_life[i] = life
	_light_energy[i] = energy


## One pooled spark burst. `dir` is the emission direction, `spread` degrees.
func burst(pos: Vector3, dir: Vector3, color: Color, amount: int, speed: float, life: float,
		spread: float = 60.0, gravity: float = 9.0) -> void:
	if _parts.is_empty():
		return
	var p := _parts[_next_part]
	_next_part = (_next_part + 1) % PARTICLE_POOL
	p.emitting = false
	p.global_position = pos
	p.amount = maxi(3, int(round(float(amount) * _k)))
	p.lifetime = life
	p.direction = dir.normalized() if dir.length() > 0.001 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	p.color = color
	p.restart()
	p.emitting = true


# ------------------------------------------------------------ events

func _own_id() -> int:
	var s: Variant = client.get("session") if client != null else null
	return int((s as Object).get("own_net_id")) if s != null else -1


func _muzzle_of(shooter: int) -> Variant:
	if client == null:
		return null
	if shooter == _own_id():
		var rig: Variant = client.get("rig")
		if rig != null:
			var wm: Variant = (rig as Object).get("weapon_model")
			if wm != null:
				var m: Variant = (wm as Object).call("socket", &"fx_muzzle")
				if m != null:
					return (m as Node3D).global_position
			var cam: Variant = (rig as Object).get("camera")
			if cam != null:
				return (cam as Node3D).global_position
		return null
	var at: Variant = client.call("hero_view_position", shooter)
	return at


func _shot_color(shooter: int) -> Color:
	if shooter == _own_id():
		return COLOR_OWN
	var v: Variant = (client.call("remote_views") as Dictionary).get(shooter)
	if v != null and int((v as Object).get("team")) == int(client.call("own_team")):
		return COLOR_ALLY
	return COLOR_ENEMY


func _on_shot(e: GameEvent) -> void:
	var now := Time.get_ticks_msec()
	var muzzle: Variant = _muzzle_of(e.source_net_id)
	var color := _shot_color(e.source_net_id)
	var own := e.source_net_id == _own_id()
	if muzzle != null and now - int(_last_shot_ms.get(e.source_net_id, -1000)) >= SAME_SHOOTER_GAP_MS:
		_last_shot_ms[e.source_net_id] = now
		var mp: Vector3 = muzzle
		flash(mp, color.lerp(Color.WHITE, 0.35), 0.28 if own else 0.9, 0.06, false, 2.2)
		pulse_light(mp, color, 2.5 if own else 1.8, 7.0, 0.07)
	var from: Vector3 = muzzle if muzzle != null else e.position + Vector3.UP
	var dist := from.distance_to(e.position)
	if dist > IMPACT_MAX_RANGE_M:
		return
	var back := (from - e.position).normalized()
	flash(e.position, color, 0.55, 0.12, false, 1.8)
	burst(e.position, back, color.lerp(Color.WHITE, 0.4), 8, 5.0, 0.35, 55.0)


func _on_hit(e: GameEvent) -> void:
	var views: Variant = client.call("remote_views") if client != null else null
	if views == null:
		return
	var v: Variant = (views as Dictionary).get(e.target_net_id)
	if v == null:
		return
	var hv := v as Node3D
	for mi in hv.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _overlay
	_hit_flash[hv] = HIT_FLASH_S
	var head := (e.flags & GameEvent.FLAG_HEADSHOT) != 0
	flash(e.position, Color(1.0, 0.95, 0.7) if head else Color(1.0, 0.5, 0.3), 0.8 if head else 0.5, 0.1)


func _team_color_of(net_id: int) -> Color:
	var v: Variant = (client.call("remote_views") as Dictionary).get(net_id)
	if v == null:
		return Color(0.7, 0.55, 1.0)
	return Color("#2E86FF") if int((v as Object).get("team")) == int(client.call("own_team")) else Color("#FF5A1F")


func _on_kill(e: GameEvent) -> void:
	var c := _team_color_of(e.target_net_id)
	var p := e.position + Vector3(0.0, 0.9, 0.0)
	flash(p, c.lerp(Color.WHITE, 0.3), 5.0, 0.5, true, 1.8)
	flash(p, Color.WHITE, 2.2, 0.18, false, 2.0)
	burst(p, Vector3.UP, c.lerp(Color.WHITE, 0.25), 26, 7.0, 0.8, 120.0, 6.0)
	pulse_light(p, c, 3.0, 9.0, 0.35)


func _on_respawn(v: Node3D) -> void:
	var c := _team_color_of(int(v.get("_net_id"))) if v.get("_net_id") != null else Color(0.7, 0.55, 1.0)
	var p := v.global_position + Vector3(0.0, 0.1, 0.0)
	flash(p + Vector3(0.0, 0.8, 0.0), c.lerp(Color.WHITE, 0.3), 4.0, 0.6, true, 1.6)
	burst(p, Vector3.UP, c.lerp(Color.WHITE, 0.4), 18, 4.0, 0.9, 25.0, -1.5)
	pulse_light(p + Vector3(0.0, 1.0, 0.0), c, 2.0, 8.0, 0.4)


func _process(delta: float) -> void:
	for i in FLASH_POOL:
		if _flash_age[i] == INF:
			continue
		_flash_age[i] += delta
		var t := _flash_age[i] / _flash_life[i]
		var mi := _flashes[i]
		if t >= 1.0:
			mi.visible = false
			_flash_age[i] = INF
		else:
			(mi.material_override as ShaderMaterial).set_shader_parameter("progress", t)
	for i in _lights.size():
		if _light_age[i] == INF:
			continue
		_light_age[i] += delta
		var t := _light_age[i] / _light_life[i]
		if t >= 1.0:
			_lights[i].visible = false
			_light_age[i] = INF
		else:
			_lights[i].light_energy = _light_energy[i] * (1.0 - t)
	for hv: Node3D in _hit_flash.keys():
		if not is_instance_valid(hv):
			_hit_flash.erase(hv)
			continue
		var left: float = _hit_flash[hv] - delta
		if left <= 0.0:
			for mi in hv.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_overlay = null
			_hit_flash.erase(hv)
		else:
			_hit_flash[hv] = left
	_poll_t += delta
	if _poll_t >= 0.1 and client != null and client.has_method("remote_views"):
		_poll_t = 0.0
		_poll_respawns()


## A hero view that turns visible again after being hidden (dead) = a respawn.
func _poll_respawns() -> void:
	var views: Dictionary = client.call("remote_views")
	for id: int in views:
		var v := views[id] as Node3D
		if v == null:
			continue
		var vis := v.visible
		if _was_visible.get(id, vis) == false and vis:
			_on_respawn(v)
		_was_visible[id] = vis
