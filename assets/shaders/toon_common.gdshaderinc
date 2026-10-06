// Shared cel lighting for every opaque lit surface (docs/shading-audit.md):
// the hero look (spatial_char_toon_rigged) and the world panels
// (spatial_env_panel) light through these functions with the same defaults
// (TOON_* below; tests/unit/models/shading_unified_test.gd keeps them equal).
// Emissive surfaces are unshaded (team neon, trims, signs); alpha surfaces are
// the FX / holo shaders (spatial_fx_*), also unshaded.

#define TOON_SHADOW_VALUE 0.62
#define TOON_SHADOW_TINT vec3(0.52, 0.52, 0.70)
#define TOON_SHADOW_TINT_MIX 0.35
#define TOON_HIGHLIGHT_BOOST 0.18
#define TOON_BAND_LO 0.05
#define TOON_BAND_HI 0.72
#define TOON_BAND_SOFTNESS 0.004
#define TOON_RIM_STRENGTH 0.35

// The shadow tone: grey value tinted toward `tint` by `tint_mix`.
vec3 toon_shadow(float value, vec3 tint, float tint_mix) {
	return mix(vec3(value), tint * value * 1.25, tint_mix);
}

// Two clear tones (shadow / lit) plus a narrow highlight band for a light
// amount `lit` (N.L x attenuation).
vec3 toon_shade(vec3 shadow, float lit, float band_lo, float band_hi, float softness, float highlight) {
	float b1 = smoothstep(band_lo - softness, band_lo + softness, lit);
	float b2 = smoothstep(band_hi - softness, band_hi + softness, lit);
	return mix(shadow, vec3(1.0), b1) + vec3(highlight) * b2;
}

// Hard rim on the lit side (0..1).
float toon_rim(vec3 n, vec3 view, float ndl) {
	float rim = 1.0 - clamp(dot(n, view), 0.0, 1.0);
	return smoothstep(0.6, 0.66, rim) * clamp(ndl + 0.4, 0.0, 1.0);
}
