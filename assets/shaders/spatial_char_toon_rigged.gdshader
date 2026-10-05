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
uniform float shadow_value = 0.62;
uniform float highlight_boost = 0.18;
uniform float band_lo = 0.05;
uniform float band_hi = 0.72;
uniform float band_softness = 0.004;
uniform float shadow_tint_mix = 0.35;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.35;
uniform float team_rim_mix : hint_range(0.0, 1.0) = 0.4;
uniform float emission_energy = 2.2;
uniform float chrome_glint = 0.5;
// Borderlands-style ink (owner direction 2026-10-05): saturation boost, inner
// contour ink at grazing angles, and hand-drawn hatching in the shadow band only.
uniform float saturation = 1.08;
uniform float inner_line = 0.24;
uniform vec3 ink_color : source_color = vec3(0.035, 0.04, 0.055);
uniform float hatch_density = 70.0;
uniform float hatch_strength = 0.55;
uniform float hatch_fade_m = 14.0;
// 0..1 white hit flash, 1..0 stealth / visibility fade (screen-door dither).
instance uniform float flash = 0.0;
instance uniform float fade = 1.0;

varying flat float v_ch;
varying vec3 v_obj;
varying vec3 v_onrm;
varying float v_hatch;

void vertex() {
	v_ch = floor(UV.x * 8.0);
	v_obj = VERTEX;
	v_onrm = NORMAL;
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
	float l = dot(alb, vec3(0.299, 0.587, 0.114));
	alb = max(mix(vec3(l), alb, saturation), vec3(0.0));
	// Inner contour ink where the surface turns away (creases, limb edges).
	float ndv = dot(NORMAL, VIEW);
	float ink = (ch == 2 || ch == 3) ? 0.0 : 1.0 - smoothstep(inner_line - 0.03, inner_line, ndv);
	alb = mix(alb, ink_color, ink);
	// Triplanar diagonal hatch (object space), faded with distance; applied in light().
	vec3 w = abs(normalize(v_onrm));
	vec3 q = v_obj * hatch_density;
	float hx = abs(fract(q.y + q.z) - 0.5);
	float hy = abs(fract(q.x + q.z) - 0.5);
	float hz = abs(fract(q.x + q.y) - 0.5);
	float h = (hx * w.x + hy * w.y + hz * w.z) / max(w.x + w.y + w.z, 1e-4);
	float dist = length(VERTEX);
	v_hatch = (1.0 - smoothstep(0.12, 0.2, h)) * (1.0 - smoothstep(hatch_fade_m * 0.6, hatch_fade_m, dist));
	ALBEDO = min(alb, vec3(0.88));
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
	// Two clear tones (shadow / lit) plus a narrow highlight band.
	vec3 sh = mix(vec3(shadow_value), shadow_tint * shadow_value * 1.25, shadow_tint_mix);
	sh = mix(sh, vec3(shadow_value + 0.1, shadow_value + 0.03, shadow_value - 0.02), soft);
	sh *= 1.0 - v_hatch * hatch_strength * (1.0 - soft * 0.5);
	vec3 shade = mix(sh, vec3(1.0), b1) + vec3(highlight_boost) * b2;
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
