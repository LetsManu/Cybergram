// W18-LIFE: background movers (flying cars, cargo drones, birds, sky-train).
// Every instance rides a route baked into path_tex; the CPU only feeds
// anim_time (shared match clock), so there is no per-frame transform upload.
// INSTANCE_CUSTOM = (route row, phase 0..1, speed in loops/s, lateral offset m).
// Unshaded + engine fog: silhouettes with emissive lights that haze with distance.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://assets/shaders/env_ambient_path.gdshaderinc"

// 0 car, 1 drone, 2 bird, 3 train car.
uniform int kind = 0;
uniform float anim_time = 0.0;
// Train only: progress of the head car along the open track (u of car i = train_u - phase).
uniform float train_u = -1.0;
uniform float flap_speed = 1.0;
uniform vec3 body_color : source_color = vec3(0.08, 0.08, 0.13);
uniform vec3 light_front : source_color = vec3(1.0, 0.92, 0.78);
uniform vec3 light_rear : source_color = vec3(1.0, 0.18, 0.22);
uniform float light_gain = 1.6;
uniform float blink = 1.0;
// Mesh is a unit box; size scales it (metres).
uniform vec3 size = vec3(1.0);

varying vec3 v_local;
varying float v_phase;

void vertex() {
	v_local = VERTEX;
	v_phase = INSTANCE_CUSTOM.y;
	float u;
	if (kind == 3) {
		u = train_u - INSTANCE_CUSTOM.y;
	} else {
		u = INSTANCE_CUSTOM.y + anim_time * INSTANCE_CUSTOM.z;
	}
	vec3 lv = VERTEX * size;
	if (kind == 2) {
		lv.y += abs(VERTEX.x) * size.x * sin(anim_time * 7.0 * flap_speed + INSTANCE_CUSTOM.y * 40.0) * 0.3;
	}
	mat3 fr = amb_frame(INSTANCE_CUSTOM.x, u);
	if (kind != 3 && INSTANCE_CUSTOM.z < 0.0) { fr[0] = -fr[0]; fr[2] = -fr[2]; }  // reverse traffic faces its way
	vec3 p = amb_path(INSTANCE_CUSTOM.x, u) + fr[0] * INSTANCE_CUSTOM.w;
	VERTEX = p + fr * lv;
	if (kind == 3 && (u < 0.0 || u > 1.0)) {
		VERTEX = vec3(0.0, -5000.0, 0.0);  // car not on the track: degenerate
	}
}

void fragment() {
	vec3 c = body_color;
	if (kind == 0) {
		// Car: head lights on the front face, tail lights on the back face.
		if (v_local.z > 0.48) c = light_front * light_gain;
		else if (v_local.z < -0.48) c = light_rear * light_gain;
	} else if (kind == 1) {
		// Cargo drone: amber box, one slow green / red nav blink.
		c = mix(body_color, vec3(0.9, 0.62, 0.2), step(0.0, v_local.y));
		float b = step(0.5, fract(anim_time * 0.7 + v_phase * 3.0)) * blink;
		if (abs(v_local.x) > 0.45 && v_local.y > 0.2) c = mix(c, (v_local.x > 0.0 ? vec3(0.2, 1.0, 0.4) : vec3(1.0, 0.25, 0.2)) * light_gain, b);
	} else if (kind == 3) {
		// Train car: window strip along the sides.
		if (abs(v_local.y - 0.1) < 0.14 && abs(v_local.x) > 0.45) c = light_front * light_gain * 0.8;
	}
	ALBEDO = c;
}
