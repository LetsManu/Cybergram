// W18-LIFE: additive light trails behind the flying cars (night look).
// Same route data and INSTANCE_CUSTOM layout as spatial_amb_mover; the mesh is a
// unit box stretched backwards along the route by trail_len.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://assets/shaders/env_ambient_path.gdshaderinc"

uniform float anim_time = 0.0;
uniform float trail_len = 26.0;
uniform float gain = 1.0;
uniform vec2 trail_size = vec2(1.0, 0.4);
uniform vec3 color_a : source_color = vec3(1.0, 0.3, 0.32);
uniform vec3 color_b : source_color = vec3(0.3, 0.75, 1.0);

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
	float a = (1.0 - v_k) * (1.0 - v_k) * gain;
	ALBEDO = mix(color_a, color_b, v_side) * a;
}
