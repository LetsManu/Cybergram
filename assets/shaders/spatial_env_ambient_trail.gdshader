// W18-LIFE: faint light trails behind the flying cars (night look).
// Deliberately NOT tracer-like: short (trail_len), dim (gain <= ~0.45), soft at
// both ends (no bright head), warm amber or desaturated lilac rather than a
// saturated streak. Same route data and INSTANCE_CUSTOM layout as
// spatial_env_ambient_mover; the mesh is a unit box stretched back along the route.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/env_ambient_path.gdshaderinc"

uniform float anim_time = 0.0;
uniform float trail_len = 10.0;
uniform float gain = 0.3;
uniform vec2 trail_size = vec2(1.2, 0.35);
uniform vec3 color_a : source_color = vec3(0.62, 0.42, 0.28);
uniform vec3 color_b : source_color = vec3(0.46, 0.42, 0.52);

varying float v_k;
varying float v_side;

void vertex() {
	float u = INSTANCE_CUSTOM.y + anim_time * INSTANCE_CUSTOM.z;
	v_k = clamp(VERTEX.z + 0.5, 0.0, 1.0);  // 0 at the car, 1 at the trail end
	v_side = step(0.5, fract(INSTANCE_CUSTOM.y * 17.0));
	// Arc length is not uniform in u, so walk back a fixed share of the loop.
	float du = trail_len * 0.0006 * sign(INSTANCE_CUSTOM.z);
	float uk = u - du * v_k;
	mat3 fr = amb_frame(INSTANCE_CUSTOM.x, uk);
	if (INSTANCE_CUSTOM.z < 0.0) { fr[0] = -fr[0]; }
	vec3 p = amb_path(INSTANCE_CUSTOM.x, uk) + fr[0] * INSTANCE_CUSTOM.w;
	VERTEX = p + fr[0] * VERTEX.x * trail_size.x + fr[1] * VERTEX.y * trail_size.y;
}

void fragment() {
	// Soft hump: zero at the car and at the tail, peak a third of the way back.
	float a = smoothstep(0.0, 0.35, v_k) * (1.0 - smoothstep(0.35, 1.0, v_k)) * gain;
	ALBEDO = mix(color_a, color_b, v_side) * a;
}
