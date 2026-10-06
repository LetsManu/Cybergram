// Stylised world panel (art bible §6.1 playable layer: calm colour blocks, detail
// at eye level). World-space triplanar grid: panel seams, an optional emissive
// trim line on vertical faces, a faint per-panel value shift and painted AO
// toward the ground.
//
// v2 (docs/assets/floor.md): upward-facing surfaces sample the painted floor trim
// sheet (tools/art/world/floor_kit.py, 4 x 2 tiles of 512 px): one tile per panel,
// the variant picked by a weighted hash of the panel cell, a random 90-degree
// rotation, value-based albedo tinted by base_color (0.5 = base_color), the tile
// normal map in the lighting, mask R AO / G edge highlight / B grime. The tiles
// fade back to the flat v1 look between tile_fade_start and tile_fade_end (mips,
// aliasing). Walls are unchanged.
// Cost: walls and use_tiles = false: no textures, one hash (v1). Tiled floors:
// 3 texture samples (textureGrad, anisotropic) + 2 extra hashes per fragment.
// The maps are not set per material: WorldDecals.install_floor_tiles() sets them as
// the shader's default textures at runtime, so every existing material picks them
// up. Unbound maps (mask alpha = 0, hint_default_transparent) give exactly the v1 look.
// Target: Forward+ (desktop, lavapipe-verified); budget <= 3 samples per fragment.
// The tile branch is deliberate: it is coherent per surface (normal, panel size,
// distance) and skips all three samples on walls and far floors. Derivatives are
// taken before it (undefined inside divergent flow); the samples use textureGrad.
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.55);
uniform vec3 seam_color : source_color = vec3(0.12, 0.13, 0.2);
uniform vec3 trim_color : source_color = vec3(0.2, 0.5, 1.0);
uniform float panel_size = 4.0;
uniform float seam_width = 0.025;
uniform float panel_variation = 0.07;
// Emissive accent line height on vertical faces (0 = none). Accent tier: stays under the 1.1 bloom threshold.
uniform float trim_height = 0.0;
uniform float trim_energy = 0.9;
uniform float ao_height = 2.5;

group_uniforms floor_tiles;
// Low quality switch: false = the v1 flat panel floor (no texture samples).
uniform bool use_tiles = true;
uniform sampler2D tile_albedo : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D tile_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D tile_mask : hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_disable;
// Blend of the painted tiles over the flat look (0 = v1).
uniform float tile_strength : hint_range(0.0, 1.0) = 1.0;
// 0 = every panel is the plain slab, 1 = the full weighted variant mix.
uniform float tile_variety : hint_range(0.0, 1.0) = 1.0;
uniform bool tile_rotate = true;
uniform float tile_normal_strength : hint_range(0.0, 2.0) = 0.8;
uniform float tile_ao : hint_range(0.0, 1.0) = 0.7;
uniform float tile_edge : hint_range(0.0, 1.0) = 0.4;
uniform float tile_grime : hint_range(0.0, 1.0) = 0.45;
uniform vec3 grime_color : source_color = vec3(0.06, 0.05, 0.07);
// Panels smaller than this (stairs, crates, cargo) keep the v1 look on their tops.
uniform float tile_min_panel = 1.25;
// View distance (m) where the tiles start / finish fading to the flat look.
uniform float tile_fade_start = 28.0;
uniform float tile_fade_end = 65.0;

varying vec3 v_pos;
varying vec3 v_nrm;

// Sheet layout (floor_kit.py): 4 x 2 slots, 4 px inset against mip bleeding.
const vec2 SHEET = vec2(4.0, 2.0);
const float PAD = 4.0 / 512.0;
// Cumulative variant weights: plain, inset, tread, cracked, grate, drain, trench, hazard.
const float HALF_PI = 1.5707963;
const float CUM[8] = { 0.27, 0.45, 0.59, 0.73, 0.81, 0.88, 0.95, 1.0 };

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(v_nrm);
	vec2 uv;
	if (an.y > 0.7) {
		uv = v_pos.xz;
	} else if (an.x > an.z) {
		uv = v_pos.zy;
	} else {
		uv = v_pos.xy;
	}
	vec2 cell = uv / panel_size;
	vec2 f = fract(cell);
	vec2 d = min(f, 1.0 - f) * panel_size;
	float seam = 1.0 - smoothstep(seam_width, seam_width + 0.03, min(d.x, d.y));
	float v = (hash21(floor(cell)) - 0.5) * panel_variation;
	// Painted AO / grime toward the ground on vertical faces.
	float ao = an.y > 0.7 ? 1.0 : mix(0.72, 1.0, smoothstep(0.0, ao_height, v_pos.y));
	vec3 col = (base_color + v) * ao;
	float seam_k = 0.85;
	vec2 cell_dx = dFdx(cell);
	vec2 cell_dy = dFdy(cell);
	if (use_tiles && v_nrm.y > 0.7 && panel_size >= tile_min_panel) {
		float fade = 1.0 - smoothstep(tile_fade_start, tile_fade_end, length(VERTEX));
		if (fade > 0.0) {
			vec2 id = floor(cell);
			float pick = hash21(id + vec2(17.3, 5.1)) * tile_variety;
			int slot = 0;
			for (int i = 0; i < 7; i++) {
				if (pick > CUM[i]) {
					slot = i + 1;
				}
			}
			float turn = tile_rotate ? floor(hash21(id + vec2(3.7, 41.9)) * 4.0) : 0.0;
			float c = round(cos(turn * HALF_PI));
			float s = round(sin(turn * HALF_PI));
			mat2 rot = mat2(vec2(c, s), vec2(-s, c));
			vec2 q = rot * (f - 0.5) + 0.5;
			vec2 org = vec2(float(slot % 4), float(slot / 4));
			vec2 auv = (org + PAD + q * (1.0 - 2.0 * PAD)) / SHEET;
			// Gradients of the continuous cell coordinate: no mip pop at the panel seams.
			vec2 gx = rot * cell_dx * (1.0 - 2.0 * PAD) / SHEET;
			vec2 gy = rot * cell_dy * (1.0 - 2.0 * PAD) / SHEET;
			vec4 m = textureGrad(tile_mask, auv, gx, gy);
			float w = fade * tile_strength * m.a;
			if (w > 0.001) {
				float a = textureGrad(tile_albedo, auv, gx, gy).r;
				vec2 nt = textureGrad(tile_normal, auv, gx, gy).rg * 2.0 - 1.0;
				vec3 tcol = (base_color + v) * (a * 2.0);
				tcol *= mix(1.0, m.r, tile_ao);
				tcol = mix(tcol, grime_color, m.b * tile_grime);
				tcol += (vec3(1.0) - tcol) * m.g * tile_edge;
				col = mix(col, tcol, w);
				seam_k = mix(0.85, 0.55, w);  // the tiles carry their own chamfer
				// Tangent space (image right, image up) -> panel frame (x, z down the image)
				// -> world by the inverse of the tile's rotation.
				vec2 nq = vec2(nt.x, -nt.y);
				vec2 nw = transpose(rot) * nq * tile_normal_strength * w;
				vec3 wn = normalize(v_nrm + vec3(nw.x, 0.0, nw.y));
				NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
			}
		}
	}
	col = mix(col, seam_color, seam * seam_k);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	if (trim_height > 0.0 && an.y < 0.7) {
		float t = 1.0 - smoothstep(0.0, 0.08, abs(v_pos.y - trim_height));
		EMISSION = trim_color * t * trim_energy;
		ALBEDO = mix(ALBEDO, trim_color * 0.4, t);
	}
}
