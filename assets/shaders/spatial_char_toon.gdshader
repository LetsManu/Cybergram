// Semi-cel toon master for heroes, weapons and Wardlings (art bible §10.1).
// Procedural models carry their material zones per vertex instead of a mask
// texture: COLOR.rgb = zone albedo, UV.x = zone kind, UV.y = emission energy.
// Kinds: 0 flat, 1 faction trim (value key), 2 chrome (matcap), 3 team neon
// (Accent tier, capped), 4 signature glow (capped), 5 faction metal,
// 6 team signal (mana core; Signal tier, may bloom), 7 skin.
// One material per team; team colour and faction values are uniforms, so a
// mesh is shared by both teams and relative-colour mode is a uniform swap.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 team_tint : source_color = vec3(0.18, 0.525, 1.0);
uniform vec3 trim_color : source_color = vec3(0.918, 0.953, 1.0);
uniform vec3 metal_color : source_color = vec3(0.91, 0.71, 0.28);
uniform vec3 chrome_color : source_color = vec3(0.79, 0.83, 0.886);
uniform vec3 shadow_tint : source_color = vec3(0.50, 0.50, 0.72);
// Accent tier cap (§4.6): neon trims glow but never reach the 1.1 bloom threshold.
uniform float accent_emission_cap = 1.0;
// Signal tier cap (§4.6) for mana cores.
uniform float signal_emission_cap = 4.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.32;
uniform float team_rim_strength : hint_range(0.0, 1.0) = 0.15;
// Terminator: hard band edge, 2-6% soft (authored softness, §10.1).
uniform float band_threshold = 0.08;
uniform float band_softness = 0.035;
// Slow-status / phase tint (0 = off).
uniform vec4 overlay_color : source_color = vec4(0.0);

varying flat float v_kind;
varying float v_energy;

void vertex() {
	v_kind = UV.x;
	v_energy = UV.y;
}

vec3 matcap3(vec3 n_view, vec3 base) {
	// 3-band stylised matcap from the view-space normal: dark lower band,
	// mid body, a hard bright sky band near the top rim.
	float up = n_view.y * 0.8 + n_view.x * 0.2;
	float b = up > 0.45 ? 1.25 : (up > -0.15 ? 0.78 : 0.38);
	float edge = 1.0 - clamp(n_view.z, 0.0, 1.0);
	return base * b + vec3(0.12) * step(0.72, edge);
}

void fragment() {
	int k = int(v_kind + 0.5);
	vec3 alb = COLOR.rgb;
	vec3 emit = vec3(0.0);
	float spec = 0.15;
	if (k == 1) {
		alb = trim_color * mix(vec3(1.0), COLOR.rgb, 0.12);
	} else if (k == 2) {
		vec3 mc = matcap3(NORMAL, chrome_color);
		alb = mc * 0.42;
		emit = mc * 0.32;
		spec = 1.0;
	} else if (k == 3) {
		alb = team_tint * 0.35;
		emit = team_tint * min(max(v_energy, 0.6), accent_emission_cap);
	} else if (k == 4) {
		emit = COLOR.rgb * min(max(v_energy, 0.4), accent_emission_cap);
	} else if (k == 5) {
		alb = metal_color;
		spec = 0.8;
	} else if (k == 6) {
		vec3 core = mix(team_tint, vec3(1.0), 0.45);
		alb = core * 0.4;
		emit = core * min(max(v_energy, 1.2), signal_emission_cap);
	}
	alb = mix(alb, overlay_color.rgb, overlay_color.a);
	// Fresnel team rim (0.15, optional per §10.1).
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	emit += team_tint * fres * team_rim_strength * 0.6;
	ALBEDO = min(alb, vec3(0.9));
	EMISSION = emit;
	SPECULAR = spec;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = ndl * ATTENUATION;
	float band = smoothstep(band_threshold - band_softness, band_threshold + band_softness, lit);
	vec3 shade = mix(shadow_tint, vec3(1.0), band);
	// Second, small hard highlight band (semi-cel).
	float hi = smoothstep(0.78, 0.8, lit) * 0.12;
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += ALBEDO * lc * (shade + hi) * (LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION);
	// Rim on the lit side (Valorant-style edge pop).
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	rim = smoothstep(0.62, 0.68, rim) * clamp(ndl + 0.35, 0.0, 1.0);
	DIFFUSE_LIGHT += lc * rim * rim_strength * band;
	// Thresholded Blinn spec, masked.
	vec3 h = normalize(LIGHT + VIEW);
	float s = step(0.97, dot(NORMAL, h)) * SPECULAR_AMOUNT;
	SPECULAR_LIGHT += lc * s * 0.35 * band;
}
