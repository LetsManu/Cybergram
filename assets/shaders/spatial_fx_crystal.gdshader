// Mana material (art bible §4.1 mana rule, §7.2): white-hot core band + a
// coloured fresnel rim (team colour or crystal family hue), with emission
// clamped to a tier cap (§4.6: Signal tier 1.2-4.0, Accent <= 1.0).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, shadows_disabled;

uniform vec3 hue : source_color = vec3(0.56, 0.36, 1.0);
uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float energy = 1.6;
uniform float energy_cap = 4.0;
uniform float core_mix : hint_range(0.0, 1.0) = 0.45;
uniform float pulse_speed = 0.0;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.2;
// 1 = Burnout / destroyed: dark grey, no glow.
uniform float dead : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float facet = 0.5 + 0.5 * sin((NORMAL.x * 7.0 + NORMAL.y * 5.0) * 1.3);
	vec3 col = mix(mix(hue, core_color, core_mix), hue, fres);
	col *= 0.85 + 0.15 * facet;
	float p = 1.0 - pulse_depth * (0.5 + 0.5 * sin(TIME * pulse_speed * 6.2832));
	float e = min(energy * p, energy_cap);
	ALBEDO = mix(col * 0.35, vec3(0.16, 0.16, 0.18), dead);
	EMISSION = col * e * (1.0 - dead);
}
