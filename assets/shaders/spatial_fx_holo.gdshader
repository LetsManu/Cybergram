// Hologram (art bible §10.4): unshaded, additive, fresnel edge, world-space
// scanlines, slow flicker and an optional glitch (block jitter + RGB split
// look via offset bands); alpha-blended so it reads on light and dark
// backgrounds alike. Used for Hex's panels, rune rings, holo labels and
// the Uplink rune bands. Emission tier per §4.6 (Accent in lanes).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.18, 0.525, 1.0);
uniform float energy = 0.9;
uniform float alpha = 0.7;
uniform float scan_density = 40.0;
uniform float scan_speed = 1.5;
uniform float flicker = 0.08;
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.0;
// 1 = panel UV pattern (code lines + face glyph frame), 0 = plain.
uniform float panel_pattern : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	if (glitch_amount > 0.0) {
		float blk = floor(VERTEX.y * 6.0 + floor(TIME * 12.0));
		VERTEX.x += (hash(blk) - 0.5) * 0.25 * glitch_amount * step(0.7, hash(blk + 3.1));
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float scan = 0.65 + 0.35 * step(0.5, fract(v_world.y * scan_density - TIME * scan_speed));
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float fl = 1.0 - flicker * step(0.93, hash(floor(TIME * 20.0)));
	float pat = 1.0;
	if (panel_pattern > 0.5) {
		vec2 uv = UV;
		float border = step(0.94, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);
		float row = floor(uv.y * 9.0);
		float line_len = 0.3 + 0.6 * hash(row + floor(TIME * 2.0));
		float code = step(0.35, fract(uv.y * 9.0)) * step(uv.x, line_len) * step(0.08, uv.x);
		pat = max(border, code * 0.8) + 0.35;
	}
	vec3 c = color;
	if (glitch_amount > 0.0) {
		float band = step(0.85, hash(floor(v_world.y * 8.0) + floor(TIME * 9.0)));
		c = mix(c, vec3(c.b, c.r, c.g), band * glitch_amount);
	}
	ALBEDO = c * energy * scan * fl * (0.9 + fres) * pat;
	ALPHA = clamp(alpha * scan * pat, 0.0, 1.0);
}
