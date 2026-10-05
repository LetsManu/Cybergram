shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// W21-G2 Armory beacon: a light column that fades out with height.
uniform vec4 tint : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float height = 45.0;
uniform float strength = 0.5;
varying float h01;
void vertex() {
	h01 = clamp((VERTEX.y + height * 0.5) / height, 0.0, 1.0);
}
void fragment() {
	float fade = pow(1.0 - h01, 1.6);
	ALBEDO = tint.rgb * strength * fade;
	ALPHA = 1.0;
}
