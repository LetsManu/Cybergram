class_name ToonFx
extends RefCounted
## Shared toon FX materials for the ability presenter and the FX director
## (W14-P2): cel-banded, ink-contoured, hard-edged. Cached per (colour, alpha, energy).

const CEL_SHADER := "res://assets/shaders/spatial_fx_toon_cel.gdshader"
static var _cache: Dictionary = {}


## Cel material. `alpha` < 1 makes a see-through shell that keeps an ink contour.
static func cel(c: Color, alpha: float = 1.0, energy: float = 1.2) -> ShaderMaterial:
	var k := "%s|%.2f|%.2f" % [c.to_html(false), alpha, energy]
	if _cache.has(k):
		return _cache[k]
	var m := ShaderMaterial.new()
	m.shader = load(CEL_SHADER)
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("energy", energy)
	if alpha < 0.99:
		m.render_priority = 1
	_cache[k] = m
	return m


## Ink smear behind a bright line: a slightly fatter back-face box (cull_front) so
## only a dark contour shows around it. Add as a child of the line mesh.
static func ink_smear(parent: Node3D, w: float) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(w * 1.9, w * 1.9, 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Ink"
	mi.mesh = b
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("#090A0E")
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
