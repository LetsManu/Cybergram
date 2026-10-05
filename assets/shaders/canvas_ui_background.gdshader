// Menu / launcher background (design/ux/ui-kit.md §5): night ink gradient, a
// distant skyline silhouette with a violet horizon glow, and a perspective
// floor grid drifting toward the viewer. Pure math, one full-screen quad,
// no textures. `speed` = 0 freezes it (reduce motion).
// Author: UI kit (W12-K1). Target: desktop, Forward+ and Compatibility; budget
// ~40 ALU per pixel, no texture samples, no variants.
shader_type canvas_item;

group_uniforms colours;
uniform vec4 bg_top : source_color = vec4(0.02, 0.024, 0.05, 1.0);
uniform vec4 bg_bottom : source_color = vec4(0.04, 0.05, 0.1, 1.0);
uniform vec4 glow : source_color = vec4(0.556, 0.36, 1.0, 1.0);
uniform vec4 glow2 : source_color = vec4(0.85, 0.7, 0.42, 1.0);
uniform vec4 grid : source_color = vec4(0.556, 0.36, 1.0, 1.0);
group_uniforms layout;
// Grid drift in cells per second (0 = static).
uniform float speed : hint_range(0.0, 1.0) = 0.05;
// Horizon height as a fraction of the screen from the top.
uniform float horizon : hint_range(0.2, 0.9) = 0.58;
// Width / height of the rect (set by UiKit.background()).
uniform float aspect : hint_range(0.5, 4.0) = 1.7778;
group_uniforms;

// Window cell size of the far skyline (UV units).
const vec2 WINDOW_CELL = vec2(0.009, 0.012);

float h1(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	vec3 col = mix(bg_top.rgb, bg_bottom.rgb, uv.y);
	// Horizon glow (violet core, faint brass edge).
	float d = uv.y - horizon;
	col += glow.rgb * 0.22 * exp(-abs(d) * 14.0);
	col += glow2.rgb * 0.05 * exp(-abs(d + 0.06) * 30.0);
	// Skyline: blocky towers above the horizon (two layers, parallax-free).
	float x = uv.x * aspect;
	for (int layer = 0; layer < 2; layer++) {
		float w = layer == 0 ? 0.045 : 0.08;
		float cell = floor(x / w + float(layer) * 7.3);
		float bh = (layer == 0 ? 0.07 : 0.13) * (0.35 + h1(cell + float(layer) * 31.0));
		float top = horizon - bh;
		float inb = step(top, uv.y) * step(uv.y, horizon);
		vec3 tower = layer == 0 ? vec3(0.06, 0.06, 0.13) : vec3(0.035, 0.035, 0.08);
		col = mix(col, tower, inb * (layer == 0 ? 0.85 : 1.0));
		// Lit windows on the far layer only (layer 0), sparse: 14% of cells.
		vec2 wv = vec2(fract(x / WINDOW_CELL.x), fract((uv.y - top) / WINDOW_CELL.y));
		float win = step(0.35, wv.x) * step(wv.x, 0.7) * step(0.4, wv.y) * step(wv.y, 0.75);
		float lit = step(0.86, h1(floor(x / WINDOW_CELL.x) * 3.1 + floor(uv.y / WINDOW_CELL.y) * 17.0));
		col += glow.rgb * 0.35 * win * lit * inb * (1.0 - float(layer));
	}
	// Perspective floor grid below the horizon: z = depth of the floor row
	// seen at this pixel (1 / distance below the horizon).
	{
		float below = step(0.0, d);
		float z = 0.08 / max(d, 0.001);
		float gx = (uv.x - 0.5) * aspect * z;
		float gz = z + t * 6.0;
		float lx = abs(fract(gx * 2.0) - 0.5);
		float lz = abs(fract(gz * 0.5) - 0.5);
		float fw = fwidth(gx * 2.0) * 1.2;
		float fz = fwidth(gz * 0.5) * 1.2;
		float line = max(1.0 - smoothstep(0.0, fw, lx), 1.0 - smoothstep(0.0, fz, lz));
		float fade = clamp(d * 3.5, 0.0, 1.0) * (1.0 - clamp(z / 30.0, 0.0, 1.0));
		col += grid.rgb * line * 0.32 * fade * below;
	}
	// Vignette.
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.9;
	COLOR = vec4(col, 1.0);
}
