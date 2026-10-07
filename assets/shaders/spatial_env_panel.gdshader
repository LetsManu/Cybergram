// Stylised world panel (art bible §6.1 playable layer: calm colour blocks, detail
// at eye level). World-space triplanar grid: panel seams, an optional emissive
// trim line on vertical faces, a faint per-panel value shift and painted AO
// toward the ground.
//
// v2 (docs/assets/floor.md): upward-facing surfaces show the painted floor trim
// sheet (tools/art/world/floor_kit.py, 4 x 2 tiles of 512 px, modelled at 2 m):
//   * layout in world space, independent of the panel grid: tiles of
//     tile_target_m (2 m = 256 px/m) in running bond (rows offset by half a
//     tile, row pairs offset by a whole tile), plus occasional 2 x 2 feature
//     plates (4 m) - no regular grid from above;
//   * variant by a weighted hash per tile, random 90-degree rotation, some tiles
//     sunk (parallax shift + darker), value albedo tinted by base_color
//     (0.5 = base_color), normal map in the lighting, mask R cavity AO,
//     G edge highlight, B grime;
//   * parallax occlusion on the height map (tiles sit over real 5 cm joints, grates
//     and pits are recessed, bolts raised): 16 steps near, 8 at tile_pom_end,
//     off beyond it;
//   * fade back to the flat v1 look between tile_fade_start and tile_fade_end.
// Walls are unchanged.
//
// Cost (Forward+, desktop; lavapipe-verified):
//   walls, use_tiles = false: no textures, one hash (v1);
//   tiled floor beyond tile_pom_end: 3 samples (albedo, normal, mask) + 4 hashes;
//   tiled floor near: + 9-17 height samples (POM march + 1 refine).
// The POM loop reads a texture per step by design (bounded at 16, textureGrad);
// the tile branch is coherent per surface (normal, distance) and skips every
// sample on walls / far floors. Derivatives are taken before any branch.
//
// The maps are not set per material: WorldDecals.install_floor_tiles() makes them
// the shader's default textures at runtime, so every existing material picks them
// up. Unbound maps (mask alpha = 0, hint_default_transparent) give the v1 look.
shader_type spatial;
render_mode diffuse_lambert;
#include "res://assets/shaders/toon_common.gdshaderinc"


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
uniform sampler2D tile_height : hint_default_white, filter_linear_mipmap, repeat_disable;
// Blend of the painted tiles over the flat look (0 = v1).
uniform float tile_strength : hint_range(0.0, 1.0) = 1.0;
// 0 = every tile is the plain slab, 1 = the full weighted variant mix.
uniform float tile_variety : hint_range(0.0, 1.0) = 1.0;
uniform bool tile_rotate = true;
// Tile size (m); the tiles are modelled at 2 m.
uniform float tile_target_m = 2.0;
// Share of 2 x 2 tile blocks drawn as one 4 m feature plate.
uniform float tile_feature_chance : hint_range(0.0, 1.0) = 0.1;
// Share of tiles sunk below their neighbours, how deep (fraction of the depth
// range) and how much darker they read.
uniform float tile_sink_chance : hint_range(0.0, 1.0) = 0.3;
uniform float tile_sink_depth : hint_range(0.0, 0.5) = 0.06;
uniform float tile_sink_dark : hint_range(0.0, 0.5) = 0.08;
uniform float tile_normal_strength : hint_range(0.0, 3.0) = 1.4;
uniform float tile_ao : hint_range(0.0, 1.0) = 0.9;
uniform float tile_edge : hint_range(0.0, 1.0) = 0.55;
uniform float tile_grime : hint_range(0.0, 1.0) = 0.45;
uniform vec3 grime_color : source_color = vec3(0.06, 0.05, 0.07);
// Panel seams over tiled floors (the tiles carry their own joints).
uniform float tile_panel_seam : hint_range(0.0, 1.0) = 0.0;
// Parallax: depth (m) of the height map's full range, and where it switches off.
uniform float tile_pom_depth_m = 0.22;
// Parallax fades out at grazing view angles (view vector's up component), where
// a height-field march smears.
uniform float tile_pom_grazing = 0.4;
// Deepest point the march reaches (fraction of the range): grate and trench pits
// bottom out here instead of streaking at mid distance.
uniform float tile_pom_max_depth : hint_range(0.1, 1.0) = 0.5;
uniform float tile_pom_end = 25.0;
// Panels smaller than this (stairs, crates, cargo) keep the v1 look on their tops.
uniform float tile_min_panel = 1.25;
// View distance (m) where the tiles start / finish fading to the flat look.
uniform float tile_fade_start = 28.0;
uniform float tile_fade_end = 65.0;
// Cel lighting shared with the heroes (toon_common.gdshaderinc, docs/shading-audit.md).
uniform bool toon = true;
uniform float shadow_value = TOON_SHADOW_VALUE;
uniform vec3 shadow_tint : source_color = TOON_SHADOW_TINT;
uniform float shadow_tint_mix = TOON_SHADOW_TINT_MIX;
uniform float highlight_boost = TOON_HIGHLIGHT_BOOST;
uniform float band_lo = TOON_BAND_LO;
uniform float band_hi = TOON_BAND_HI;
uniform float band_softness = TOON_BAND_SOFTNESS;

group_uniforms look;
// Look-dev params (LookProfile, docs/lookdev.md). Defaults = the pre-look-dev panel.
// Wall / floor albedo value and wall saturation (pale pastel walls -> deeper blocks).
uniform float wall_value = 1.0;
uniform float wall_saturation = 1.0;
uniform float floor_value = 1.0;
// Large-scale world-space albedo breakup on walls (value, +-).
uniform float albedo_noise : hint_range(0.0, 0.3) = 0.0;
// Light wear line along wall face borders (BoxMesh UV cells), ~2 px wide, near only.
uniform float edge_wear : hint_range(0.0, 1.0) = 0.0;
// Painted contact AO at the foot of walls: value at the ground, and grime tint mix.
uniform float contact_ao_min : hint_range(0.2, 1.0) = 0.72;
uniform float contact_grime : hint_range(0.0, 1.0) = 0.0;
// Cel specular band (thresholded Blinn) on walls / floors, threshold and tint.
uniform float spec_wall : hint_range(0.0, 2.0) = 0.0;
uniform float spec_floor : hint_range(0.0, 2.0) = 0.0;
uniform float spec_threshold : hint_range(0.0, 1.0) = 0.9;
uniform vec3 spec_tint : source_color = vec3(1.0);
// Environment (sky / reflection probe) specular on floors and their roughness (wet < 0.4).
uniform float floor_env_specular : hint_range(0.0, 1.0) = 0.0;
uniform float floor_roughness : hint_range(0.0, 1.0) = 0.8;

varying vec3 v_pos;
varying vec3 v_nrm;
// 1 on upward faces (floors), 0 on walls: picks the spec band in light().
varying float v_floor;

// Sheet layout (floor_kit.py): 4 x 2 slots, 4 px inset against mip bleeding.
const vec2 SHEET = vec2(4.0, 2.0);
const float PAD = 4.0 / 512.0;
const float HALF_PI = 1.5707963;
const int POM_MAX_STEPS = 16;
const int POM_MIN_STEPS = 8;
// Cumulative variant weights: plain, inset, tread, cracked, grate, drain, trench, hazard.
// Calm playable layer (design §6.1): mostly slabs and panels, few pits.
const float CUM[8] = { 0.34, 0.54, 0.66, 0.78, 0.84, 0.88, 0.95, 1.0 };
// Slots that make good 4 m feature plates: inset panel, tread plate, trench
// (a 4 m drain fills the first-person view).
const float FEATURE[3] = { 1.0, 2.0, 6.0 };

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 atlas_uv(float slot, vec2 q) {
	vec2 org = vec2(mod(slot, 4.0), floor(slot / 4.0));
	return (org + PAD + clamp(q, 0.0, 1.0) * (1.0 - 2.0 * PAD)) / SHEET;
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_floor = step(0.7, v_nrm.y);
}

// Smooth value noise (world-space albedo breakup).
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
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
	float ao = an.y > 0.7 ? 1.0 : mix(contact_ao_min, 1.0, smoothstep(0.0, ao_height, v_pos.y));
	vec3 base = base_color;
	if (an.y > 0.7) {
		base *= floor_value;
	} else {
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		base = mix(vec3(lum), base, wall_saturation) * wall_value;
	}
	// Walls only: on floors the 9 m noise cells read as stains (the tiles carry their own variation).
	if (albedo_noise > 0.0 && an.y <= 0.7) {
		vec2 np = an.x > an.z ? v_pos.zy : v_pos.xy;
		float nz = vnoise(np * 0.11) * 0.65 + vnoise(np * 0.37 + 13.1) * 0.35;
		base *= 1.0 + (nz - 0.5) * 2.0 * albedo_noise;
	}
	vec3 col = (base + v) * ao;
	col = mix(col, grime_color, (1.0 - ao) / max(1.0 - contact_ao_min, 0.01) * contact_grime * 0.6);
	float seam_k = 0.85;
	// Tile space (1 unit = one 2 m tile); derivatives before any branch.
	vec2 u = v_pos.xz / max(tile_target_m, 0.1);
	vec2 u_dx = dFdx(u);
	vec2 u_dy = dFdy(u);
	if (use_tiles && v_nrm.y > 0.7 && panel_size >= tile_min_panel) {
		float dist = length(VERTEX);
		float fade = 1.0 - smoothstep(tile_fade_start, tile_fade_end, dist);
		if (fade > 0.0) {
			// Layout: row pairs offset by one tile; 2 x 2 feature plates; inside a
			// row pair, odd rows offset by half a tile (running bond).
			float pair = floor(u.y * 0.5);
			vec2 ub = vec2(u.x + mod(pair, 2.0), u.y);
			vec2 big = floor(ub * 0.5);
			float slot;
			vec2 id;
			vec2 local;
			float scale;
			if (hash21(big + vec2(7.7, 1.3)) < tile_feature_chance * tile_variety) {
				scale = 0.5;
				id = big + vec2(911.0, 37.0);
				local = fract(ub * 0.5);
				slot = FEATURE[int(min(hash21(big + vec2(2.9, 8.1)) * 3.0, 2.0))];
			} else {
				scale = 1.0;
				vec2 us = vec2(ub.x + mod(floor(u.y), 2.0) * 0.5, u.y);
				id = floor(us);
				local = fract(us);
				float pick = hash21(id + vec2(17.3, 5.1)) * tile_variety;
				slot = 0.0;
				for (int i = 0; i < 7; i++) {
					slot += step(CUM[i], pick);
				}
			}
			float turn = tile_rotate ? floor(hash21(id + vec2(3.7, 41.9)) * 4.0) : 0.0;
			float c = round(cos(turn * HALF_PI));
			float s = round(sin(turn * HALF_PI));
			mat2 rot = mat2(vec2(c, s), vec2(-s, c));
			vec2 q = rot * (local - 0.5) + 0.5;
			// Gradients of the continuous tile coordinate: no mip pop at the joints.
			vec2 gx = rot * u_dx * scale * (1.0 - 2.0 * PAD) / SHEET;
			vec2 gy = rot * u_dy * scale * (1.0 - 2.0 * PAD) / SHEET;
			float sink = step(1.0 - tile_sink_chance, hash21(id + vec2(51.1, 9.7))) * tile_sink_depth;
			// Parallax occlusion: march the view ray down through the height field.
			float pom = (1.0 - smoothstep(tile_pom_end * 0.8, tile_pom_end, dist)) * step(0.001, tile_pom_depth_m);
			if (pom > 0.0) {
				vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
				vec3 vw = normalize(cam - v_pos);
				float graze = smoothstep(tile_pom_grazing * 0.3, tile_pom_grazing, vw.y);
				// metres in the world -> tile-local units: * scale / tile_target_m
				vec2 dir = -(rot * vw.xz) / max(vw.y, 0.25) * tile_pom_depth_m * pom * graze * scale / max(tile_target_m, 0.1);
				int n = int(mix(float(POM_MAX_STEPS), float(POM_MIN_STEPS), clamp(dist / tile_pom_end, 0.0, 1.0)));
				float layer = tile_pom_max_depth / float(n);
				vec2 dq = dir * layer;
				vec2 qc = q;
				float depth = 0.0;
				float hd = clamp(1.0 - textureGrad(tile_height, atlas_uv(slot, qc), gx, gy).r + sink, 0.0, tile_pom_max_depth);
				vec2 q_prev = qc;
				float hd_prev = hd;
				float depth_prev = 0.0;
				for (int i = 0; i < POM_MAX_STEPS; i++) {
					if (i >= n || depth >= hd) {
						break;
					}
					q_prev = qc;
					hd_prev = hd;
					depth_prev = depth;
					qc += dq;
					depth += layer;
					hd = clamp(1.0 - textureGrad(tile_height, atlas_uv(slot, qc), gx, gy).r + sink, 0.0, tile_pom_max_depth);
				}
				// Linear refine between the last two steps.
				float after = hd - depth;
				float before = hd_prev - depth_prev;
				float t = abs(after - before) > 1e-5 ? clamp(after / (after - before), 0.0, 1.0) : 0.0;
				q = mix(qc, q_prev, t);
			}
			vec2 auv = atlas_uv(slot, q);
			vec4 m = textureGrad(tile_mask, auv, gx, gy);
			float w = fade * tile_strength * m.a;
			if (w > 0.001) {
				float a = textureGrad(tile_albedo, auv, gx, gy).r;
				vec2 nt = textureGrad(tile_normal, auv, gx, gy).rg * 2.0 - 1.0;
				// value shift per tile, not per panel (a tile may straddle two panels)
				float vt = (hash21(id + vec2(23.9, 61.3)) - 0.5) * panel_variation;
				vec3 tcol = (base_color + vt) * (a * 2.0);
				tcol *= mix(1.0, m.r, tile_ao);
				tcol = mix(tcol, grime_color, m.b * tile_grime);
				tcol += (vec3(1.0) - tcol) * m.g * tile_edge;
				tcol *= 1.0 - tile_sink_dark * step(0.001, sink);
				col = mix(col, tcol, w);
				seam_k = mix(0.85, tile_panel_seam, w);
				// Tangent space (image right, image up) -> tile frame (x, z down the
				// image) -> world by the inverse of the tile's rotation.
				vec2 nq = vec2(nt.x, -nt.y);
				vec2 nw = transpose(rot) * nq * tile_normal_strength * w;
				vec3 wn = normalize(v_nrm + vec3(nw.x, 0.0, nw.y));
				NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
			}
		}
	}
	col = mix(col, seam_color, seam * seam_k);
	// Walls only, and only on meshes with real UVs: a mesh without them (the
	// rolling lane floors) reads "on the border" everywhere, which painted
	// noise-shaped light blotches over the whole floor (look-dev review).
	vec2 uw = fwidth(UV * vec2(3.0, 2.0));
	if (edge_wear > 0.0 && an.y <= 0.7 && max(uw.x, uw.y) > 1e-6) {
		// BoxMesh lays its 6 faces out in a 3 x 2 UV grid: distance to the face border.
		vec2 fu = fract(UV * vec2(3.0, 2.0));
		vec2 de = min(fu, 1.0 - fu) / max(uw, vec2(1e-5));
		float e = 1.0 - smoothstep(1.0, 2.5, min(de.x, de.y));
		float near = 1.0 - smoothstep(15.0, 40.0, length(VERTEX));
		float brk = smoothstep(0.35, 0.6, vnoise(v_pos.xz * 1.7 + v_pos.y * 2.3));
		col += (vec3(1.0) - col) * e * near * edge_wear * mix(0.45, 1.0, brk);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.8, floor_roughness, v_floor);
	SPECULAR = 0.5 * floor_env_specular * v_floor;
	if (trim_height > 0.0 && an.y < 0.7) {
		float t = 1.0 - smoothstep(0.0, 0.08, abs(v_pos.y - trim_height));
		EMISSION = trim_color * t * trim_energy;
		ALBEDO = mix(ALBEDO, trim_color * 0.4, t);
	}
}


void light() {
	vec3 lc = LIGHT_COLOR / PI;
	float ndl = dot(NORMAL, LIGHT);
	if (toon) {
		vec3 shade = toon_shade(toon_shadow(shadow_value, shadow_tint, shadow_tint_mix), ndl * ATTENUATION,
			band_lo, band_hi, band_softness, highlight_boost);
		// Godot multiplies DIFFUSE_LIGHT by the albedo itself (docs/shading-audit.md).
		DIFFUSE_LIGHT += lc * shade * (LIGHT_IS_DIRECTIONAL ? 1.0 : ATTENUATION);
		// Cel specular band: one hard-edged highlight, no PBR (art bible §10.1).
		float ks = mix(spec_wall, spec_floor, v_floor);
		if (ks > 0.0) {
			vec3 h = normalize(LIGHT + VIEW);
			float nh = clamp(dot(NORMAL, h), 0.0, 1.0);
			float band = smoothstep(spec_threshold - 0.015, spec_threshold + 0.015, pow(nh, mix(24.0, 64.0, v_floor)));
			SPECULAR_LIGHT += LIGHT_COLOR * spec_tint * band * ks * ATTENUATION * step(0.0, ndl);
		}
	} else {
		DIFFUSE_LIGHT += lc * clamp(ndl, 0.0, 1.0) * ATTENUATION;
	}
}
