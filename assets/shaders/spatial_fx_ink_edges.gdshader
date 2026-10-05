// Screen-space ink edge lines (W14-P2, High / Ultra only). A full-screen quad
// (vertex shader writes clip space directly) that reads the depth buffer: depth
// discontinuities (silhouettes) and creases (second derivative of the view-space
// position, i.e. normal changes) become thin ink lines that complement the hull
// outline on heroes. 3D-only pass, so HUD (canvas) is never touched. Sky and
// distant geometry fade out. Works in Forward+ and Compatibility (depth only;
// `compat_depth` selects the depth range).
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 ink_color : source_color = vec3(0.035, 0.04, 0.055);
uniform float strength : hint_range(0.0, 1.0) = 0.8;
uniform float width_px = 1.0;
uniform float depth_threshold = 0.06;
uniform float crease_threshold = 0.35;
uniform float fade_start_m = 40.0;
uniform float fade_end_m = 120.0;
uniform bool compat_depth = false;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, compat_depth ? d * 2.0 - 1.0 : d);
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = width_px / VIEWPORT_SIZE;
	float c = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float l = view_depth(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float r = view_depth(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float u = view_depth(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float d = view_depth(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float rel = max(max(abs(l - c), abs(r - c)), max(abs(u - c), abs(d - c))) / max(c, 0.1);
	float silhouette = smoothstep(depth_threshold, depth_threshold * 2.0, rel);
	// Crease: curvature of depth along each axis, relative to depth.
	float lap = max(abs(l + r - 2.0 * c), abs(u + d - 2.0 * c)) / max(c, 0.1);
	float crease = smoothstep(crease_threshold * 0.02, crease_threshold * 0.04, lap) * (1.0 - silhouette);
	float far_fade = 1.0 - smoothstep(fade_start_m, fade_end_m, c);
	float sky = step(c, 1000.0);
	float a = clamp(silhouette + crease * 0.6, 0.0, 1.0) * strength * far_fade * sky;
	ALBEDO = ink_color;
	ALPHA = a;
}
