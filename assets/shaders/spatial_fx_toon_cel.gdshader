// Cel-style FX surface (W14-P2): unshaded, two or three hard colour bands from
// the view angle, a dark ink contour at grazing angles, optional stepped alpha.
// For domes, shock rings, orbs and drones in the ability presenter.
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 ink_color : source_color = vec3(0.035, 0.04, 0.055);
uniform float energy = 1.2;
uniform float alpha = 1.0;
uniform float bands = 3.0;
uniform float ink_width = 0.28;

void fragment() {
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float band = floor(ndv * bands + 0.5) / bands;  // hard steps
	vec3 body = color.rgb * energy * mix(0.7, 1.15, band);
	float ink = 1.0 - step(ink_width, ndv);
	ALBEDO = mix(body, ink_color, ink);
	ALPHA = mix(alpha * color.a, 0.95, ink);
}
