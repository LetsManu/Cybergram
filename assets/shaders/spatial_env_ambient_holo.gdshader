// W18-LIFE: animated holo billboard panel (fictional in-world ads). The ad text
// is a Label3D in front of it; this draws the panel: frame, a procedural product
// glyph per ad (motif), scanlines, a slow colour sweep and an optional subtle
// flicker. Alpha-blended, never brighter than glow_gain allows.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color_a : source_color = vec3(0.2, 0.85, 0.8);
uniform vec3 color_b : source_color = vec3(0.55, 0.36, 1.0);
// 0 can, 1 crystal, 2 bowl, 3 wing, 4 shield, 5 ring.
uniform int motif = 0;
uniform float anim_time = 0.0;
// 0 = frozen (reduce motion).
uniform float anim_speed = 1.0;
// Brightness multiplier (CPU flicker x mood neon gain x comfort glow gain).
uniform float gain = 1.0;
uniform float alpha = 0.75;

float box(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }

float glyph(vec2 p, float t) {
	if (motif == 0) return box(p, vec2(0.13, 0.26)) - 0.04;                              // can
	if (motif == 1) return (abs(p.x) * 1.6 + abs(p.y)) - 0.3;                             // crystal
	if (motif == 2) return max(length(p - vec2(0.0, 0.08)) - 0.28, p.y - 0.06);          // bowl
	if (motif == 3) return abs(p.y + abs(p.x) * 0.6 - 0.05 + sin(t * 2.0) * 0.03) - 0.05; // wing
	if (motif == 4) return max(box(p, vec2(0.22, 0.22)), length(p + vec2(0.0, 0.3)) - 0.42); // shield
	return abs(length(p) - 0.22) - 0.05;                                                  // ring
}

void fragment() {
	float t = anim_time * anim_speed;
	vec2 uv = UV;
	vec3 base = mix(color_a, color_b, 0.5 + 0.5 * sin(uv.x * 2.5 + t * 0.6));
	// Glyph on the left third, text label covers the right.
	vec2 gp = (uv - vec2(0.2, 0.5)) * vec2(3.0, 1.0) * 1.15;
	gp.y *= 1.0 + 0.04 * sin(t * 1.3);
	float g = 1.0 - smoothstep(0.0, 0.02, glyph(gp, t));
	float frame = step(min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)), 0.025);
	float scan = 0.82 + 0.18 * sin((uv.y + t * 0.08) * 220.0);
	float sweep = smoothstep(0.92, 1.0, 1.0 - abs(fract(uv.x * 0.6 - t * 0.12) - 0.5) * 2.0) * 0.35;
	float fill = 0.4 + g * 0.6 + frame * 0.8 + sweep;
	ALBEDO = base * fill * scan * gain;
	ALPHA = clamp(alpha * (0.55 + 0.45 * max(g, frame)) * (0.6 + 0.4 * scan), 0.0, 1.0);
}
