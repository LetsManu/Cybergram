// Toon billboard flash (W14-P2): muzzle star / impact star / death burst / ring.
// Hard-edged, ink-outlined, drawn in discrete frames (`steps` quantises the
// progress, so it pops and holds like a hand-drawn cel instead of fading
// smoothly). `progress` 0..1; `ring` 1 draws an expanding ring; `spikes` = star
// points; `reduce` 1 = reduce-motion: one static frame, no growth.
// The colour is the (team-tinted) body, a white-hot core sits inside it, and an
// ink contour wraps the whole shape. HDR energy lets the fill bloom on High+.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform vec3 ink_color : source_color = vec3(0.035, 0.04, 0.055);
uniform float energy = 1.5;
uniform float progress = 0.0;
uniform float ring : hint_range(0.0, 1.0) = 0.0;
uniform float spikes = 4.0;
uniform float steps = 4.0;
uniform float reduce : hint_range(0.0, 1.0) = 0.0;
uniform float ink_width = 0.09;

void vertex() {
	// Camera-facing quad; the node scale gives the size.
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec4 center = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	POSITION = PROJECTION_MATRIX * (center + vec4(VERTEX.x * sx, VERTEX.y * sy, 0.0, 0.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float t = reduce > 0.5 ? 0.3 : floor(progress * steps) / steps;  // discrete frames
	float grow = reduce > 0.5 ? 1.0 : mix(0.55, 1.0, sqrt(t + 0.0001));
	float fill;
	float core;
	if (ring > 0.5) {
		float rr = reduce > 0.5 ? 0.6 : t * 0.7 + 0.2;
		float w = 0.12 * (1.0 - t * 0.6);
		float dist = abs(r - rr);
		fill = 1.0 - step(w, dist);
		core = 1.0 - step(w * 0.45, dist);
		float edge = 1.0 - step(w + ink_width, dist);
		if (edge < 0.5) {
			discard;
		}
		float ink = edge * (1.0 - fill);
		ALBEDO = mix(color.rgb * energy, ink_color, ink);
		ALBEDO = mix(ALBEDO, vec3(1.0, 1.0, 1.0) * energy, core * (1.0 - ink) * 0.7);
		ALPHA = (1.0 - t * 0.5) * color.a;
	} else {
		float ang = atan(p.y, p.x);
		float star = 0.42 + 0.58 * pow(abs(cos(ang * spikes * 0.5)), 5.0);
		float rad = r / (star * grow);
		fill = 1.0 - step(0.82, rad);
		core = 1.0 - step(0.4, rad);
		float edge = 1.0 - step(0.82 + ink_width * 2.0, rad);
		if (edge < 0.5) {
			discard;
		}
		float ink = edge * (1.0 - fill);
		vec3 body = mix(color.rgb, vec3(1.0), 0.08) * (0.8 + 0.2 * energy);
		ALBEDO = mix(body, ink_color, ink);
		ALBEDO = mix(ALBEDO, vec3(1.0) * energy, core * (1.0 - ink));
		ALPHA = color.a * (t > 0.74 ? 0.0 : 1.0);  // hard cut on the last frame
		if (ALPHA < 0.01) {
			discard;
		}
	}
}
