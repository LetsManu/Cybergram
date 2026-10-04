// Stylised world panel (art bible §6.1 playable layer: calm colour blocks, detail
// at eye level). World-space triplanar grid: panel seams, an optional emissive
// trim line on vertical faces, a faint per-panel value shift and painted AO
// toward the ground. Cheap: no textures, one hash per fragment.
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

varying vec3 v_pos;
varying vec3 v_nrm;

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
	col = mix(col, seam_color, seam * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	if (trim_height > 0.0 && an.y < 0.7) {
		float t = 1.0 - smoothstep(0.0, 0.08, abs(v_pos.y - trim_height));
		EMISSION = trim_color * t * trim_energy;
		ALBEDO = mix(ALBEDO, trim_color * 0.4, t);
	}
}
