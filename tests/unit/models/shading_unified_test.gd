extends GdUnitTestSuite
## Shading unification (owner plan 2026-10-06, docs/shading-audit.md): the map
## panels and the heroes light through the shared cel ramp with the same values,
## and outlines rank gameplay-critical objects above dressing.

const TOON_INC := "res://assets/shaders/toon_common.gdshaderinc"
const HERO := "res://assets/shaders/spatial_char_toon_rigged.gdshader"
const PANEL := "res://assets/shaders/spatial_env_panel.gdshader"
const SHARED := ["shadow_value", "shadow_tint", "shadow_tint_mix", "highlight_boost", "band_lo", "band_hi", "band_softness"]


func test_hero_and_panel_shaders_use_the_shared_cel_ramp() -> void:
	for path in [HERO, PANEL]:
		var src := (load(path) as Shader).code
		assert_str(src).override_failure_message("%s does not include toon_common" % path).contains(TOON_INC)
		assert_str(src).override_failure_message("%s does not call toon_shade" % path).contains("toon_shade(")


func test_panel_cel_defaults_equal_the_hero_defaults() -> void:
	var hero := _defaults(HERO)
	var panel := _defaults(PANEL)
	for u: String in SHARED:
		assert_bool(hero.has(u) and panel.has(u)).override_failure_message("%s missing" % u).is_true()
		assert_str(str(panel.get(u))).override_failure_message("%s: panel %s, hero %s" % [u, panel.get(u), hero.get(u)]) \
			.is_equal(str(hero.get(u)))


## {uniform: default expression, TOON_* macros resolved, spaces removed} of a
## shader's source (the headless test renderer reports no defaults).
func _defaults(path: String) -> Dictionary:
	var macros := {}
	var inc := FileAccess.get_file_as_string(TOON_INC)
	var rm := RegEx.create_from_string("(?m)^#define\\s+(TOON_\\w+)\\s+(.+)$")
	for m in rm.search_all(inc):
		macros[m.get_string(1)] = m.get_string(2).strip_edges()
	var out := {}
	var ru := RegEx.create_from_string("(?m)^uniform\\s+\\w+\\s+(\\w+)\\s*(?::[^=;]*)?=\\s*([^;]+);")
	for m in ru.search_all(FileAccess.get_file_as_string(path)):
		var v := m.get_string(2).strip_edges()
		v = str(macros.get(v, v)).replace(" ", "")
		out[m.get_string(1)] = v
	return out


func test_panel_light_does_not_multiply_albedo_twice() -> void:
	# Godot multiplies DIFFUSE_LIGHT by the albedo after light(); doing it in
	# light() too darkened the map by albedo squared (found in this audit).
	var src := (load(PANEL) as Shader).code
	var light := src.substr(src.find("void light()"))
	assert_str(light).not_contains("ALBEDO")


func test_outline_ranks_objectives_over_dressing() -> void:
	assert_float(WorldModel.outline_scale(&"uplink")).is_greater(1.0)
	assert_float(WorldModel.outline_scale(&"armory_stall")).is_greater(1.0)
	assert_float(WorldModel.outline_scale(&"world_props")).is_less(1.0)
	assert_float(WorldModel.outline_scale(&"wardling_props")).is_equal(1.0)
	if WorldModel.exists(&"uplink") and WorldModel.exists(&"world_props"):
		var t := ModelPalette.TEAM_CONCORD
		var crit := float((WorldModel.material(&"uplink", t).next_pass as ShaderMaterial).get_shader_parameter("width_px"))
		var dress := float((WorldModel.material(&"world_props", t).next_pass as ShaderMaterial).get_shader_parameter("width_px"))
		assert_float(crit).is_greater(dress)
