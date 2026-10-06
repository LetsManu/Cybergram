// Toon master for the rigged glb heroes (design/art/hero-art-bible.md §1, §3).
// Flat vertex colours (COLOR) + a channel id in UV.x (floor(UV.x * 8)):
//   0 flat cel, 1 team accent, 2 emissive, 3 team emissive, 4 skin, 5 chrome.
// 3-tone cel ramp (shadow / mid / lit), lit-side rim tinted by the team, one
// shared material per team; per-instance hit flash and stealth fade are
// instance uniforms (no material duplication). Outline = next_pass hull.
// W14 texture set (use_maps = 1): baked hand-painted albedo, tangent normal map
// and a packed mask (R AO, G spec/glint, B emissive, A team); the channel id
// then lives in COLOR.a. Without maps the W13 flat vertex-colour path is used.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
#include "res://assets/shaders/toon_common.gdshaderinc"

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
uniform float hatch_density = 42.0;
uniform float hatch_strength = 0.32;
uniform float hatch_fade_m = 14.0;
// W14 texture set + hard metal specular band (one material per hero and team).
uniform float use_maps = 0.0;
uniform sampler2D albedo_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D mask_map : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float normal_strength = 0.9;
uniform float ao_strength = 0.35;
uniform float team_value_boost = 1.25;
uniform float spec_threshold = 0.9;
uniform float spec_strength = 0.45;
uniform float map_emission = 1.6;
// 0..1 white hit flash, 1..0 stealth / visibility fade (screen-door dither).
instance uniform float flash = 0.0;
instance uniform float fade = 1.0;

varying flat float v_ch;
varying vec3 v_obj;
varying vec3 v_onrm;
varying float v_hatch;
varying float v_spec;

void vertex() {
	v_ch = use_maps > 0.5 ? floor(COLOR.a * 8.0) : floor(UV.x * 8.0);
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
	float ao = 1.0;
	v_spec = 0.0;
	if (use_maps > 0.5) {
		vec3 tex = texture(albedo_map, UV).rgb;
		vec4 msk = texture(mask_map, UV);
		ao = mix(1.0, msk.r, ao_strength);
		v_spec = msk.g;
		// Team faces carry a neutral value map: keep its painted shading, take the hue.
		float val = dot(tex, vec3(0.333));
		vec3 team_alb = team_color * clamp(val * team_value_boost / max(dot(COLOR.rgb, vec3(0.333)), 0.2), 0.35, 1.3);
		alb = mix(tex, team_alb, msk.a);
		if (ch == 2 || ch == 3) {
			emit = alb * emission_energy;
			alb *= 0.4;
		} else {
			emit = alb * msk.b * map_emission;
		}
		alb *= ao;  // AO is also painted into the albedo; this only deepens crevices
		vec3 nm = texture(normal_map, UV).rgb;
		NORMAL_MAP = nm;
		NORMAL_MAP_DEPTH = normal_strength;
	} else {
		if (ch == 1 || ch == 3) {
			alb = team_color;
		}
		if (ch == 2 || ch == 3) {
			emit = alb * emission_energy;
			alb *= 0.4;
		}
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
	v_hatch = (1.0 - smoothstep(0.07, 0.11, h)) * (1.0 - smoothstep(hatch_fade_m * 0.6, hatch_fade_m, dist));
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
	int ch = int(v_ch + 0.5);
	float soft = ch == 4 ? 1.0 : 0.0;  // skin: warmer, lighter shadow
	// Two clear tones (shadow / lit) plus a narrow highlight band (toon_common).
	vec3 sh = toon_shadow(shadow_value, shadow_tint, shadow_tint_mix);
	sh = mix(sh, vec3(shadow_value + 0.1, shadow_value + 0.03, shadow_value - 0.02), soft);
	sh *= 1.0 - v_hatch * hatch_strength * (1.0 - soft * 0.5);
	vec3 shade = toon_shade(sh, lit, band_lo, band_hi, band_softness, highlight_boost);
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += ALBEDO * lc * shade * (LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION);
	float rim = toon_rim(NORMAL, VIEW, ndl);
	vec3 rim_col = mix(vec3(1.0), team_color, team_rim_mix);
	DIFFUSE_LIGHT += lc * rim_col * rim * rim_strength * (LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION);
	if (ch == 5) {
		vec3 h = normalize(LIGHT + VIEW);
		SPECULAR_LIGHT += lc * step(0.96, dot(NORMAL, h)) * 0.5 * b1;
	}
	// W14: crisp isotropic highlight band on metal (mask G), hard-stepped like the cel ramp.
	if (v_spec > 0.05) {
		vec3 hv = normalize(LIGHT + VIEW);
		float s = smoothstep(spec_threshold - 0.01, spec_threshold + 0.01, dot(NORMAL, hv));
		SPECULAR_LIGHT += lc * s * v_spec * spec_strength * b1 * (LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION);
	}
}
