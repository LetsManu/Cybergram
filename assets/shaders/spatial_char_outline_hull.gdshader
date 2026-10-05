// Inverted-hull outline for the rigged glb heroes (next_pass of the rigged
// toon master). Hull vertices are pushed along the skinned NORMAL by a constant
// screen-space width, shrunk with distance so far crowds do not turn to ink.
// Honours the same `fade` instance uniform as the toon pass (stealth).
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_opaque, fog_disabled;

uniform vec3 outline_color : source_color = vec3(0.078, 0.086, 0.11);
uniform float width_px = 1.8;
uniform float full_width_until_m = 20.0;
instance uniform float fade = 1.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 n_view = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 dir = (PROJECTION_MATRIX * vec4(n_view, 0.0)).xy;
	float len = length(dir);
	if (len > 1e-5) {
		float f = clamp(full_width_until_m / max(clip.w, 0.01), 0.45, 1.0);
		clip.xy += dir / len * width_px * f * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	if (fade < 0.999) {
		discard;
	}
	ALBEDO = outline_color;
}
