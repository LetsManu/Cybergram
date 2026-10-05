// Toon master for the rigged glb heroes (design/art/hero-art-bible.md §1, §3).
// Flat vertex colours (COLOR) + a channel id in UV.x (floor(UV.x * 8)):
//   0 flat cel, 1 team accent, 2 emissive, 3 team emissive, 4 skin, 5 chrome.
// 3-tone cel ramp (shadow / mid / lit), lit-side rim tinted by the team, one
// shared material per team; per-instance hit flash and stealth fade are
// instance uniforms (no material duplication). Outline = next_pass hull.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform vec3 team_color : source_color = vec3(0.18, 0.525, 1.0);
uniform vec3 shadow_tint : source_color = vec3(0.52, 0.52, 0.70);
uniform float shadow_value = 0.55;
uniform float mid_value = 0.85;
uniform float band_lo = 0.02;
uniform float band_hi = 0.45;
uniform float band_softness = 0.02;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform float team_rim_mix : hint_range(0.0, 1.0) = 0.4;
uniform float emission_energy = 2.2;
uniform float chrome_glint = 0.5;
// 0..1 white hit flash, 1..0 stealth / visibility fade (screen-door dither).
instance uniform float flash = 0.0;
instance uniform float fade = 1.0;

varying flat float v_ch;

void vertex() {
	v_ch = floor(UV.x * 8.0);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	if (fade < 0.999 && fade <= bayer4(FRAGCOORD.xy)) {
		discard;
	}
	int ch = int(v_ch + 0.5);
	vec3 alb = COLOR.rgb;
	vec3 emit = vec3(0.0);
	if (ch == 1 || ch == 3) {
		alb = team_color;
	}
	if (ch == 2 || ch == 3) {
		emit = alb * emission_energy;
		alb *= 0.4;
	}
	ALBEDO = min(alb, vec3(0.78));
	// Chrome: hard sky band from the view normal.
	if (ch == 5) {
		float up = NORMAL.y * 0.8 + NORMAL.x * 0.2;
		emit += alb * step(0.4, up) * chrome_glint * 0.5;
	}
	EMISSION = emit + vec3(flash);
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = ndl * ATTENUATION;
	float b1 = smoothstep(band_lo - band_softness, band_lo + band_softness, lit);
	float b2 = smoothstep(band_hi - band_softness, band_hi + band_softness, lit);
	int ch = int(v_ch + 0.5);
	float soft = ch == 4 ? 1.0 : 0.0;  // skin: warmer, lighter shadow
	vec3 sh = mix(shadow_tint * shadow_value, vec3(shadow_value + 0.12, shadow_value + 0.04, shadow_value), soft);
	vec3 shade = mix(sh, vec3(mid_value), b1);
	shade = mix(shade, vec3(1.0), b2);
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += ALBEDO * lc * shade * (LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION);
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	rim = smoothstep(0.6, 0.66, rim) * clamp(ndl + 0.4, 0.0, 1.0);
	vec3 rim_col = mix(vec3(1.0), team_color, team_rim_mix);
	DIFFUSE_LIGHT += lc * rim_col * rim * rim_strength * (LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION);
	if (ch == 5) {
		vec3 h = normalize(LIGHT + VIEW);
		SPECULAR_LIGHT += lc * step(0.96, dot(NORMAL, h)) * 0.5 * b1;
	}
}
