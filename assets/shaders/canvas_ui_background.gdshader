// Menu / lobby / launcher background (design/ux/mockups/v0.9): flat ground
// ink, two faint brass hairline arches behind the hero, a ground hairline and
// a warm radial spotlight. Layout is in the mockup's 1440x810 reference space
// scaled to the rect, so it follows any resolution. Pure math, one quad, no
// textures. `speed` drives a very slow spotlight breath; 0 (reduce motion)
// freezes it.
// Author: UI kit (W13-V9). Target: desktop, Forward+ and Compatibility;
// budget ~30 ALU per pixel, no texture samples, no variants.
shader_type canvas_item;

group_uniforms colours;
uniform vec4 ink : source_color = vec4(0.043, 0.063, 0.082, 1.0);
uniform vec4 brass : source_color = vec4(0.761, 0.635, 0.404, 1.0);
// Arch / ground hairline opacity (mockup: stroke-opacity .07).
uniform float line_alpha : hint_range(0.0, 0.5) = 0.07;
// Spotlight centre opacity (mockup: .14).
uniform float spot_alpha : hint_range(0.0, 0.6) = 0.14;
group_uniforms layout;
// Spotlight breath speed (0 = static).
uniform float speed : hint_range(0.0, 1.0) = 0.05;
// Rect size in px (set by UiKit.background()).
uniform vec2 rect_size = vec2(1440.0, 810.0);
// Width / height of the rect (kept for older callers; unused when rect_size is set).
uniform float aspect : hint_range(0.5, 4.0) = 1.7778;
// Arch centre x, spotlight centre and radius, ground line y and right end,
// in 1440x810 reference px.
uniform float arch_x = 850.0;
uniform vec2 spot_center = vec2(850.0, 450.0);
uniform float spot_radius = 290.0;
uniform float ground_y = 772.0;
uniform float ground_end = 1160.0;
// 0 = no arches (plain spotlight).
uniform float arches : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

// Coverage of a 1 px line at distance `d` (reference px) with `px` = one
// screen pixel in reference px.
float hair(float d, float px) {
	return 1.0 - smoothstep(px * 0.5, px * 1.5, abs(d));
}

// One arch: two verticals at arch_x +- half from `base` down, joined by a
// parabola rising `depth` (the mockup's quadratic curve).
float arch(vec2 p, float half_w, float base, float depth, float px) {
	float u = (p.x - arch_x) / half_w;
	float a = 0.0;
	if (abs(u) <= 1.0) {
		float y = base - depth * (1.0 - u * u);
		float slope = 2.0 * depth * u / half_w;
		a = hair((p.y - y) / sqrt(1.0 + slope * slope), px);
	}
	if (p.y >= base) {
		a = max(a, hair(p.x - (arch_x - half_w), px));
		a = max(a, hair(p.x - (arch_x + half_w), px));
	}
	return a;
}

void fragment() {
	float s = rect_size.y / 810.0;
	// Centre the 1440-wide reference horizontally when the rect is wider/narrower.
	float off = (rect_size.x / s - 1440.0) * 0.5;
	vec2 p = UV * rect_size / s - vec2(off, 0.0);
	float px = 1.0 / s;
	vec3 col = ink.rgb;
	float breath = 1.0 + 0.08 * sin(TIME * speed * 6.2831);
	float r = length(p - spot_center) / spot_radius;
	col += brass.rgb * spot_alpha * breath * (1.0 - smoothstep(0.0, 1.0, r)) * 0.9;
	float l = 0.0;
	if (arches > 0.5) {
		l = max(arch(p, 290.0, 402.0, 145.0, px), arch(p, 240.0, 422.0, 120.0, px));
		if (p.x <= ground_end) {
			l = max(l, hair(p.y - ground_y, px));
		}
	}
	col = mix(col, brass.rgb, l * line_alpha);
	COLOR = vec4(col, 1.0);
}
