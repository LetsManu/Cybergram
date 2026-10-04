// Additive billboard flash (muzzle star / impact glow / death ring). `progress`
// 0..1 drives the fade; `ring` 1 draws an expanding ring instead of a soft star.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float energy = 1.5;
uniform float progress = 0.0;
uniform float ring : hint_range(0.0, 1.0) = 0.0;
uniform float spikes = 4.0;

void vertex() {
	// Camera-facing quad; the node scale gives the size.
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec4 center = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	POSITION = PROJECTION_MATRIX * (center + vec4(VERTEX.x * sx, VERTEX.y * sy, 0.0, 0.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a;
	if (ring > 0.5) {
		float rr = progress * 0.85 + 0.1;
		a = smoothstep(0.14, 0.0, abs(r - rr));
	} else {
		float ang = atan(p.y, p.x);
		float star = 0.55 + 0.45 * pow(abs(cos(ang * spikes * 0.5)), 6.0);
		a = smoothstep(1.0, 0.0, r / star);
		a = a * a;
	}
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(a * (1.0 - progress) * color.a, 0.0, 1.0);
}
