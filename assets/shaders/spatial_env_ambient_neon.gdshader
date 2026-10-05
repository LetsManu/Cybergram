// W18-LIFE: neon sign mounts (tube outlines on facades). Instance colour =
// tube colour, INSTANCE_CUSTOM.x = flicker phase. The flicker curve mirrors
// AmbientComfort.flicker(): mostly steady, rare shallow dips, never a strobe;
// flicker = 0 (comfort: low effects intensity / reduce motion) is fully steady.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float anim_time = 0.0;
uniform float flicker = 0.0;
uniform float gain = 1.5;

varying float v_phase;

void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
}

float flick(float t, float phase, float amount) {
	if (amount <= 0.0) return 1.0;
	float slow = sin(t * 0.9 + phase * 7.0) * 0.5 + 0.5;
	float fast = sin(t * 23.0 + phase * 13.0) * sin(t * 37.0 + phase * 3.0);
	float gate = clamp((slow - 0.82) / 0.18, 0.0, 1.0);
	return 1.0 - amount * gate * (0.5 + 0.5 * abs(fast));
}

void fragment() {
	ALBEDO = COLOR.rgb * gain * flick(anim_time, v_phase, flicker);
}
