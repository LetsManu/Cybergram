// Sudden Death ring wall (W16-SDWATER): a translucent, glowing cylinder in the
// team-neutral danger colour, drawn toon-style: hard-edged cel bands, ink rails
// at the top and bottom, stepped (never smooth) shimmer. The OUTER face is the
// visible wall; the INNER face is faint so the wall never blocks the view of the
// fight. `shimmer` 0..1 scales the animation (comfort effects intensity); 0
// (also reduce-motion) = a static wall. The wall also fades out right next to
// the camera so walking up to it cannot white out the screen.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform vec3 ink_color : source_color = vec3(0.035, 0.04, 0.055);
uniform float energy = 1.6;
uniform float circumference = 200.0;
uniform float shimmer : hint_range(0.0, 1.0) = 1.0;
uniform float time_s = 0.0;
uniform float outer_alpha = 0.34;
uniform float inner_alpha = 0.10;
uniform float cell_m = 6.0;
uniform float height_m = 18.0;

void fragment() {
	float h = UV.y * height_m;
	// Hex-ish cel panels: stepped cells with ink seams.
	float cols = max(floor(circumference / cell_m), 3.0);
	float scroll = shimmer * time_s * 0.35;
	float cu = fract(UV.x * cols);
	float cv = fract(h / cell_m + scroll);
	float seam_w = 0.06;
	float seam = 1.0 - step(seam_w, cu) * step(cu, 1.0 - seam_w) * step(seam_w, cv) * step(cv, 1.0 - seam_w);
	// Stepped pulse travelling around the ring; amplitude follows `shimmer`.
	float ph = floor((UV.x * cols + time_s * 1.2) * 0.5);
	float pulse = 0.5 + 0.5 * sin(ph * 2.399 + floor(time_s * 3.0) * 0.7);
	float glow = 1.0 + shimmer * 0.45 * step(0.6, pulse);
	// Ink rails at the foot and the crown, a bright core line just inside them.
	float rail = step(h, 0.35) + step(height_m - 0.35, h);
	float core = step(0.35, h) * step(h, 0.7) + step(height_m - 0.7, h) * step(h, height_m - 0.35);
	// Vertical fade: strongest at the foot, thinning up the wall.
	float up = 1.0 - smoothstep(0.0, 1.0, UV.y) * 0.55;
	float a_face = FRONT_FACING ? outer_alpha : inner_alpha;
	vec3 body = color.rgb * energy * glow;
	vec3 col = body;
	col = mix(col, ink_color, clamp(seam, 0.0, 1.0) * 0.55);
	col = mix(col, ink_color, clamp(rail, 0.0, 1.0));
	col = mix(col, vec3(1.0) * energy, clamp(core, 0.0, 1.0) * 0.8);
	float a = a_face * up;
	a = mix(a, 0.85, clamp(rail + core, 0.0, 1.0) * (FRONT_FACING ? 1.0 : 0.5));
	a = mix(a, a * 0.4, clamp(seam, 0.0, 1.0));
	// Near-camera fade (view-space depth of the fragment).
	a *= smoothstep(1.5, 7.0, -VERTEX.z);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * color.a;
}
