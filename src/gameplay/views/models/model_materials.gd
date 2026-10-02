class_name ModelMaterials
extends RefCounted
## Shared materials for the procedural models (art bible §10.1-10.4). Every
## hero, weapon and Wardling of one team uses ONE toon material (+ outline
## next pass): zones are per-vertex, team values are uniforms. Caches are
## static, so 10 heroes and 100 Wardlings share a handful of materials.

const TOON_SHADER := "res://assets/shaders/spatial_char_toon.gdshader"
const OUTLINE_SHADER := "res://assets/shaders/spatial_fx_outline.gdshader"
const CRYSTAL_SHADER := "res://assets/shaders/spatial_fx_crystal.gdshader"
const HOLO_SHADER := "res://assets/shaders/spatial_fx_holo.gdshader"

## Outline widths (art bible §4.4): Concord thin/soft, Syndicate thick.
const OUTLINE_PX_CONCORD: float = 1.5
const OUTLINE_PX_SYNDICATE: float = 2.5
const OUTLINE_PX_VIEWMODEL: float = 1.0

static var _toon: Dictionary = {}
static var _crystal: Dictionary = {}
static var _holo: Dictionary = {}


## Toon master for `team` with its outline as next_pass. `viewmodel` = thin
## 1 px outline (§10.2). `enemy_outline` = outline in the team colour (the
## enemy read) instead of the darkened ink.
static func toon(team: int, viewmodel: bool = false, enemy_outline: bool = false) -> ShaderMaterial:
	var key := "%d|%s|%s" % [team, viewmodel, enemy_outline]
	if _toon.has(key):
		return _toon[key]
	var m := ShaderMaterial.new()
	m.shader = load(TOON_SHADER)
	var tint := ModelPalette.team_color(team)
	m.set_shader_parameter("team_tint", tint)
	match team:
		ModelPalette.TEAM_SYNDICATE:
			m.set_shader_parameter("trim_color", ModelPalette.SYNDICATE_IRON)
			m.set_shader_parameter("metal_color", ModelPalette.SYNDICATE_BRASS)
			m.set_shader_parameter("chrome_color", ModelPalette.CHROME_WARM)
			m.set_shader_parameter("shadow_tint", Color(0.55, 0.45, 0.62))
		ModelPalette.TEAM_CONCORD:
			m.set_shader_parameter("trim_color", ModelPalette.AZURE_LIGHT)
			m.set_shader_parameter("metal_color", ModelPalette.CONCORD_GOLD)
			m.set_shader_parameter("chrome_color", ModelPalette.CHROME_COOL)
			m.set_shader_parameter("shadow_tint", Color(0.5, 0.52, 0.74))
		_:
			m.set_shader_parameter("trim_color", Color("#9A97A6"))
			m.set_shader_parameter("metal_color", ModelPalette.CONCORD_GOLD)
			m.set_shader_parameter("chrome_color", ModelPalette.CHROME_COOL)
	var o := ShaderMaterial.new()
	o.shader = load(OUTLINE_SHADER)
	var ink := Color(0.05, 0.07, 0.16) if team != ModelPalette.TEAM_SYNDICATE else Color(0.09, 0.04, 0.03)
	o.set_shader_parameter("outline_color", tint if enemy_outline else ink)
	var px := OUTLINE_PX_SYNDICATE if team == ModelPalette.TEAM_SYNDICATE else OUTLINE_PX_CONCORD
	o.set_shader_parameter("width_px", OUTLINE_PX_VIEWMODEL if viewmodel else px)
	if viewmodel:
		o.set_shader_parameter("full_width_until_m", 1000.0)
	m.next_pass = o
	_toon[key] = m
	return m


## Mana / crystal material: white core + `hue` rim, emission capped.
static func crystal(hue: Color, energy: float, cap: float = 4.0, pulse: float = 0.0) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%.2f" % [hue.to_html(), energy, cap, pulse]
	if _crystal.has(key):
		return _crystal[key]
	var m := ShaderMaterial.new()
	m.shader = load(CRYSTAL_SHADER)
	m.set_shader_parameter("hue", hue)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("energy_cap", cap)
	m.set_shader_parameter("pulse_speed", pulse)
	_crystal[key] = m
	return m


## Fresh (unshared) crystal material, for per-instance states (Uplink damage).
static func crystal_unique(hue: Color, energy: float, cap: float = 4.0) -> ShaderMaterial:
	var m := crystal(hue, energy, cap).duplicate() as ShaderMaterial
	return m


## Hologram material (Accent tier by default). `panel` draws code lines.
static func holo(color: Color, energy: float = 0.9, panel: bool = false, glitch: float = 0.0) -> ShaderMaterial:
	var key := "%s|%.2f|%s|%.2f" % [color.to_html(), energy, panel, glitch]
	if _holo.has(key):
		return _holo[key]
	var m := ShaderMaterial.new()
	m.shader = load(HOLO_SHADER)
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("panel_pattern", 1.0 if panel else 0.0)
	m.set_shader_parameter("glitch_amount", glitch)
	_holo[key] = m
	return m


## Number of cached materials (perf diagnostics: should stay small).
static func cached_count() -> int:
	return _toon.size() + _crystal.size() + _holo.size()
