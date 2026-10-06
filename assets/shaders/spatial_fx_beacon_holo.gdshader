// Forward Beacon hard-light (docs/assets/forward_beacon.md; art bible §6.4):
// the projected banner-mast and the spawn halo on the ground. Unshaded,
// alpha-blended, world-space scanlines like spatial_fx_holo.
//   part 0  mast: a thin column, built bottom-up by `build` (attunement)
//   part 1  banner: team emblem (a down chevron over two bars) + frame, waves
//   part 2  halo: a ground ring; the arc fills with `build`, segments turn
// `strength` fades the whole effect; `strobe` (0..1) dims it and blinks it at
// `strobe_hz` (under attack: spawning disabled). Keep strobe_hz <= 3 (no more
// than three flashes a second, photosensitivity guideline).
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.18, 0.525, 1.0);
uniform int part = 0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float build : hint_range(0.0, 1.0) = 1.0;
uniform float strobe : hint_range(0.0, 1.0) = 0.0;
uniform float strobe_hz = 2.0;
uniform float energy = 1.4;
uniform float alpha = 0.55;
uniform float wave = 1.0;

varying vec3 v_world;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	if (part == 1 && wave > 0.0) {
		// the banner hangs from its top edge (UV.y 0) and sways below it
		float k = UV.y * UV.y;
		VERTEX.z += sin(TIME * 1.7 + UV.y * 3.0) * 0.12 * k * wave;
		VERTEX.x += sin(TIME * 1.1 + UV.y * 2.0) * 0.05 * k * wave;
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float banner(vec2 uv) {
	float frame = step(0.92, max(abs(uv.x - 0.5) * 2.0, abs(uv.y - 0.5) * 2.0 * 1.0));
	// down chevron (art bible: triangles = breach / forward push)
	vec2 p = vec2(abs(uv.x - 0.5), uv.y);
	float chev = step(abs(p.y - 0.28 - p.x * 0.9), 0.06) * step(p.x, 0.32);
	float bars = step(abs(uv.y - 0.66), 0.025) + step(abs(uv.y - 0.74), 0.025);
	bars *= step(abs(uv.x - 0.5), 0.3);
	// tattered hem: the bottom edge frays
	float hem = step(uv.y, 0.93 - 0.05 * hash(floor(uv.x * 14.0)));
	return clamp(max(frame, max(chev, bars)) + 0.22, 0.0, 1.0) * hem;
}

void fragment() {
	float scan = 0.7 + 0.3 * step(0.5, fract(v_world.y * 9.0 - TIME * 1.2));
	float fl = 1.0 - 0.1 * step(0.94, hash(floor(TIME * 18.0)));
	float pat = 1.0;
	float a = alpha;
	if (part == 0) {
		// built from the bottom up; a bright growth edge while attuning
		pat = step(UV.y, build) * (1.0 + 2.0 * step(build - 0.03, UV.y) * step(build, 0.999));
		float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
		pat *= 0.6 + fres;
	} else if (part == 1) {
		pat = banner(UV) * step(0.999, build);
	} else {
		// halo: UV.x = angle (0..1), UV.y = across the ring (0 inner, 1 outer)
		vec2 c = UV - vec2(0.5);
		float r = length(c) * 2.0;
		float ang = fract(atan(c.y, c.x) / 6.28318 + 0.5);
		float ring = smoothstep(0.78, 0.84, r) * (1.0 - smoothstep(0.96, 1.0, r));
		float inner = smoothstep(0.5, 0.53, r) * (1.0 - smoothstep(0.55, 0.58, r)) * 0.6;
		float seg = step(0.18, fract(ang * 12.0 - TIME * 0.15));
		float fill = step(ang, build);
		pat = (ring * seg * (0.25 + 0.75 * fill) + inner * fill);
		scan = 1.0;
	}
	float blink = 1.0;
	if (strobe > 0.0) {
		blink = mix(1.0, 0.35 + 0.65 * step(0.5, fract(TIME * strobe_hz)), strobe) * (1.0 - 0.45 * strobe);
	}
	float k = strength * blink * fl;
	ALBEDO = color * energy * scan * (0.6 + 0.4 * pat);
	ALPHA = clamp(a * pat * scan * k, 0.0, 1.0);
}
