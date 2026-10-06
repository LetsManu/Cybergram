// Ward Generator shield (docs/assets/ward_generator.md): an unshaded team dome
// with a hex lattice, a bright Fresnel rim and a slow upward pulse. `strength`
// 0..1 fades the whole shield (HardpointView animates it on raise / collapse);
// `hit` flashes the lattice when the shield takes fire. Alpha tier: additive,
// never writes depth (heroes stay visible through it).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.18, 0.525, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float hit : hint_range(0.0, 1.0) = 0.0;
uniform float cells = 18.0;
uniform float rim_power = 2.6;
uniform float base_alpha = 0.06;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

// Distance to the nearest hex cell edge (0 at an edge).
float hex_edge(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
}

void fragment() {
	vec3 n = normalize(v_obj);
	// cylindrical wrap around the dome: angle x height
	vec2 uv = vec2(atan(n.z, n.x) / 6.2831853 * cells * 1.6, n.y * cells * 0.5);
	float e = hex_edge(uv);
	float line = 1.0 - smoothstep(0.0, 0.06, e);
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
	float pulse = 0.5 + 0.5 * sin(TIME * 2.0 - n.y * 9.0);
	float a = base_alpha + line * (0.16 + 0.12 * pulse + hit * 0.6) + fres * 0.55;
	ALBEDO = color * (1.0 + hit * 0.8) + vec3(fres * 0.25);
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
