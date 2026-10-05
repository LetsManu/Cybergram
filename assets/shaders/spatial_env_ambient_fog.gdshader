// W18-LIFE: drifting fog banks between the skyline towers (big soft cards).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.6, 0.5, 0.75);
uniform float density = 0.35;
uniform float anim_time = 0.0;
uniform float drift = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * vec2(4.0, 1.5) + vec2(anim_time * 0.01 * drift, 0.0);
	float n = noise(p) * 0.6 + noise(p * 2.3 + 7.0) * 0.4;
	float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x) * smoothstep(0.0, 0.4, UV.y) * smoothstep(1.0, 0.55, UV.y);
	ALBEDO = color;
	ALPHA = clamp(n * edge * density, 0.0, 1.0);
}
