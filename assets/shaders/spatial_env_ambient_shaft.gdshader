// W18-LIFE: fake light shafts (dusk / overcast god rays, night searchlights).
// Open cone mesh, additive, soft at the silhouette and fading toward the ground.
// Night searchlights sweep slowly (sweep = 0 with reduce motion).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.86, 0.7);
uniform float gain = 0.25;
uniform float anim_time = 0.0;
uniform float sweep = 0.0;

void vertex() {
	// Tilt the cone around its apex (top) by a slow per-instance sweep.
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float a = sin(anim_time * 0.15 * sweep + ph) * 0.35 * sweep;
	float h = VERTEX.y - 0.5;  // apex at +0.5
	VERTEX.x += h * sin(a);
}

void fragment() {
	float rim = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fade_down = smoothstep(1.0, 0.15, UV.y);  // UV.y 0 top -> 1 bottom
	float a = rim * rim * fade_down * gain;
	ALBEDO = color * a;
}
