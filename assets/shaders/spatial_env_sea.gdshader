// Leyfall mana sea (art bible §6.1): a violet glowing plane far below the causeway
// with slow bands of light. Set-piece tier (<= 1.5), unshaded.
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec3 deep_color : source_color = vec3(0.12, 0.05, 0.3);
uniform vec3 glow_color : source_color = vec3(0.56, 0.36, 1.0);
uniform float energy = 1.0;
varying vec3 v_pos;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float w = sin(v_pos.x * 0.05 + TIME * 0.2) * sin(v_pos.z * 0.04 - TIME * 0.15);
	float band = smoothstep(0.2, 1.0, 0.5 + 0.5 * w);
	ALBEDO = mix(deep_color, glow_color, band * 0.6) * energy;
}
