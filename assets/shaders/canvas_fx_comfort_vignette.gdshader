// Comfort vignette (W16-COMFORT): soft edge darkening, radial from the screen
// centre. `alpha` is the final edge opacity (strength * level), `inner` the
// radius (fraction of the half-diagonal) where darkening begins.
shader_type canvas_item;
uniform float alpha : hint_range(0.0, 1.0) = 0.0;
uniform float inner : hint_range(0.0, 1.0) = 0.45;
uniform vec3 tint : source_color = vec3(0.0);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p) / 1.4142;
	float k = smoothstep(inner, 1.0, r);
	COLOR = vec4(tint, k * k * alpha);
}
