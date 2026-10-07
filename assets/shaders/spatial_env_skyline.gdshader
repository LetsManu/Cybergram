// Distant skyline silhouette (art bible §6.1 skyline layer): night_ink-ish body with
// a window grid of faint neon (sign_teal / sign_pink), pushed back by depth fog.
// Unshaded: no lights, no shadows, set-piece tier only.
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec3 body_color : source_color = vec3(0.16, 0.14, 0.3);
// Look-dev (LookProfile): body colour toward the tower tops (= body_color: flat, the old look).
uniform vec3 top_color : source_color = vec3(0.16, 0.14, 0.3);
uniform float top_height = 140.0;
uniform vec3 window_a : source_color = vec3(0.204, 0.847, 0.769);
uniform vec3 window_b : source_color = vec3(0.886, 0.333, 0.71);
uniform float window_energy = 0.9;
uniform float window_density = 0.25;
varying vec3 v_pos;
varying vec3 v_nrm;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = mix(body_color, top_color, smoothstep(-20.0, top_height, v_pos.y));
	if (abs(v_nrm.y) < 0.5) {
		vec2 uv = abs(v_nrm.x) > abs(v_nrm.z) ? v_pos.zy : v_pos.xy;
		vec2 c = floor(uv / vec2(3.0, 4.0));
		vec2 f = fract(uv / vec2(3.0, 4.0));
		float win = step(0.3, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.7);
		float on = step(1.0 - window_density, h(c));
		vec3 wc = h(c + 7.0) > 0.5 ? window_a : window_b;
		col += wc * win * on * window_energy;
	}
	ALBEDO = col;
}
