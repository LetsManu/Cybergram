// Inverted-hull outline (art bible §10.2), used as next_pass of the toon
// master. Hull vertices are pushed along the smoothed outline direction that
// the procedural builders bake into TANGENT.xyz, by a constant screen-space
// width (px at the current viewport), faded with distance.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque, fog_disabled;

uniform vec3 outline_color : source_color = vec3(0.06, 0.08, 0.16);
uniform float width_px = 1.5;
// Beyond this distance the width shrinks so far crowds do not turn to ink.
uniform float full_width_until_m = 25.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 dir_view = (MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz;
	vec2 dir_clip = (PROJECTION_MATRIX * vec4(dir_view, 0.0)).xy;
	float len = length(dir_clip);
	if (len > 1e-5) {
		float fade = clamp(full_width_until_m / max(clip.w, 0.01), 0.5, 1.0);
		vec2 off = dir_clip / len * width_px * fade * 2.0 / VIEWPORT_SIZE;
		clip.xy += off * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color;
}
