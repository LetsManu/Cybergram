class_name SfxSynth
extends RefCounted
## W10-W5: code-synthesized sound archetypes (no audio files). Each archetype is
## a pure function name -> normalized PCM, seeded so output is deterministic.
## SfxBank synthesizes every archetype once at startup; weapons / skills reuse
## the cached stream and only vary pitch / gain (data in sfx_bank.tres).

const RATE := 22050
const PEAK := 0.9
## Archetype name -> [length_s, loops]. The names are the keys of SfxBankDef maps.
const ARCHETYPES := {
	&"gun_rifle": [0.15, false], &"gun_smg": [0.09, false], &"gun_heavy": [0.28, false],
	&"gun_zap": [0.14, false], &"gun_tack": [0.16, false], &"gun_glitch": [0.08, false],
	&"gun_thread": [0.18, false],
	&"explosion": [0.45, false], &"whoosh": [0.28, false], &"shield_up": [0.33, false],
	&"heal_chime": [0.35, false], &"hack_glitch": [0.3, false], &"shimmer": [0.4, false],
	&"trap_click": [0.09, false], &"ult_rise": [0.6, false], &"slam": [0.35, false],
	&"buff_up": [0.25, false], &"deploy": [0.22, false], &"beam_loop": [0.4, true],
	&"ui_buy": [0.18, false], &"ui_sell": [0.15, false], &"ui_levelup": [0.45, false],
	&"ui_fork": [0.3, false], &"ui_hover": [0.025, false], &"ui_click": [0.04, false],
	# W11-C1 feel sounds: reload start / finish, dry fire, own footstep.
	&"reload_start": [0.2, false], &"reload_done": [0.18, false],
	&"dry_fire": [0.07, false], &"footstep": [0.1, false],
	# W12-L2: champ-select lock-in (soft thud + two-note chime).
	&"ui_lock": [0.32, false],
}


## Synthesizes one archetype; empty stream for an unknown name.
static func make(name: StringName) -> AudioStreamWAV:
	if not ARCHETYPES.has(name):
		return AudioStreamWAV.new()
	var spec: Array = ARCHETYPES[name]
	var n := int(RATE * float(spec[0]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(name))
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	match name:
		&"gun_rifle": _gun(pcm, rng, 55.0, 0.5, 90.0, 22.0, 0.7)
		&"gun_smg": _gun(pcm, rng, 90.0, 0.65, 150.0, 40.0, 0.5)
		&"gun_heavy": _gun(pcm, rng, 22.0, 0.35, 60.0, 9.0, 0.9)
		&"gun_tack": _gun(pcm, rng, 30.0, 0.8, 70.0, 14.0, 1.1)
		&"gun_zap": _zap(pcm, 1800.0, 260.0, 26.0)
		&"gun_glitch": _glitch(pcm, rng, 14.0, 30.0)
		&"gun_thread": _pluck(pcm, 420.0, 18.0)
		&"explosion": _boom(pcm, rng, 0.35, 7.0, 70.0)
		&"slam": _boom(pcm, rng, 0.2, 10.0, 48.0)
		&"whoosh": _whoosh(pcm, rng)
		&"shield_up": _sweep(pcm, 220.0, 880.0, 0.35, 7.0)
		&"heal_chime": _chime(pcm, [880.0, 1320.0, 1760.0], 0.07, 8.0)
		&"buff_up": _chime(pcm, [440.0, 660.0], 0.06, 12.0)
		&"ui_buy": _chime(pcm, [1175.0, 1568.0], 0.06, 14.0)
		&"ui_sell": _chime(pcm, [1175.0, 880.0], 0.05, 16.0)
		&"ui_levelup": _chime(pcm, [523.0, 659.0, 784.0, 1046.0], 0.07, 6.0)
		&"ui_fork": _chime(pcm, [740.0, 988.0], 0.09, 9.0)
		&"ui_hover": _blip(pcm, 2200.0, 160.0)
		&"ui_click": _blip(pcm, 1500.0, 90.0)
		&"hack_glitch": _glitch(pcm, rng, 6.0, 60.0)
		&"shimmer": _shimmer(pcm)
		&"trap_click": _click(pcm, rng)
		&"ult_rise": _sweep(pcm, 80.0, 900.0, 1.0, -3.0)
		&"deploy": _sweep(pcm, 300.0, 180.0, 0.2, 14.0)
		&"beam_loop": _beam(pcm)
		&"reload_start": _clacks(pcm, rng, [0.0, 0.1], 420.0, 38.0)
		&"reload_done": _clacks(pcm, rng, [0.0, 0.07], 780.0, 55.0)
		&"dry_fire": _dry(pcm, rng)
		&"footstep": _thud(pcm, rng)
		&"ui_lock": _lock(pcm, rng)
	return _finish(pcm, bool(spec[1]))


## Normalizes to PEAK, fades the last ~2 ms (not loops: a loop must wrap), wraps in a WAV.
static func _finish(pcm: PackedFloat32Array, loops: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for v in pcm:
		peak = maxf(peak, absf(v))
	var g := PEAK / peak
	var n := pcm.size()
	var fade := 0 if loops else mini(n, 32)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var s := pcm[i] * g
		if i >= n - fade:
			s *= float(n - i) / float(fade)
		bytes.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loops:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


## Noise crack (decay `ck`) over a pitch-dropping thump (`f0` Hz, decay `td`).
static func _gun(pcm: PackedFloat32Array, rng: RandomNumberGenerator, ck: float, crack_amt: float,
		f0: float, td: float, thump_amt: float) -> void:
	var lp := 0.0
	var env_c := 1.0
	var kc := exp(-ck / RATE)
	var kt := exp(-td / RATE)
	var env_t := 1.0
	for i in pcm.size():
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.5)
		env_c *= kc
		env_t *= kt
		pcm[i] = lp * env_c * crack_amt + sin(TAU * (f0 - f0 * 0.5 * minf(t * 8.0, 1.0)) * t) * env_t * thump_amt


static func _zap(pcm: PackedFloat32Array, f0: float, f1: float, decay: float) -> void:
	var ph := 0.0
	var n := pcm.size()
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(f0, f1, minf(t * 9.0, 1.0))
		ph += TAU * f / RATE
		var sq := signf(sin(ph)) * 0.35 + sin(ph * 2.0) * 0.3
		pcm[i] = sq * exp(-t * decay) * minf(t / 0.002, 1.0)


## Bit-crushed noise bursts that stutter (Glitchcaster shot / hack cast).
static func _glitch(pcm: PackedFloat32Array, rng: RandomNumberGenerator, stutter_hz: float, decay: float) -> void:
	var hold := 0.0
	var ph := 0.0
	for i in pcm.size():
		var t := float(i) / RATE
		if i % 24 == 0:
			hold = floorf((rng.randf() * 2.0 - 1.0) * 4.0) / 4.0
		ph += TAU * (300.0 + 220.0 * floorf(fmod(t * stutter_hz, 4.0))) / RATE
		var gate := 1.0 if fmod(t * stutter_hz, 1.0) < 0.6 else 0.15
		pcm[i] = (hold * 0.5 + signf(sin(ph)) * 0.3) * gate * exp(-t * decay * 0.3)


## Karplus-Strong-like decaying detuned pair (Threadcaster twang).
static func _pluck(pcm: PackedFloat32Array, hz: float, decay: float) -> void:
	for i in pcm.size():
		var t := float(i) / RATE
		var env := exp(-t * decay) * minf(t / 0.001, 1.0)
		pcm[i] = (sin(TAU * hz * t) + 0.5 * sin(TAU * hz * 2.01 * t) + 0.25 * sin(TAU * hz * 3.02 * t)) * env


static func _boom(pcm: PackedFloat32Array, rng: RandomNumberGenerator, noise_amt: float, decay: float, f0: float) -> void:
	var lp := 0.0
	var env := 1.0
	var k := exp(-decay / RATE)
	for i in pcm.size():
		var t := float(i) / RATE
		env *= k
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.12 + 0.3 * env)
		pcm[i] = lp * env * noise_amt * 2.5 + sin(TAU * f0 * (1.0 - 0.6 * minf(t * 2.0, 1.0)) * t) * env * 0.7


static func _lock(pcm: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	_boom(pcm, rng, 0.08, 16.0, 110.0)
	var bell := PackedFloat32Array()
	bell.resize(pcm.size())
	_chime(bell, [784.0, 1175.0], 0.06, 9.0)
	for i in pcm.size():
		pcm[i] = pcm[i] * 0.7 + bell[i] * 0.6


static func _whoosh(pcm: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var lp := 0.0
	var n := pcm.size()
	for i in n:
		var x := float(i) / n
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.04 + 0.5 * x)
		pcm[i] = lp * sin(PI * x) * sin(PI * x)


## Sine sweep f0 -> f1 with a (possibly negative = growing) decay.
static func _sweep(pcm: PackedFloat32Array, f0: float, f1: float, len_s: float, decay: float) -> void:
	var ph := 0.0
	for i in pcm.size():
		var t := float(i) / RATE
		ph += TAU * lerpf(f0, f1, minf(t / len_s, 1.0)) / RATE
		pcm[i] = (sin(ph) + 0.3 * sin(ph * 2.0)) * minf(t / 0.01, 1.0) * exp(-t * decay)


## Arpeggio of decaying notes spaced `step_s` apart.
static func _chime(pcm: PackedFloat32Array, notes: Array, step_s: float, decay: float) -> void:
	for i in pcm.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var tt := t - step_s * k
			if tt >= 0.0:
				var hz: float = notes[k]
				v += (sin(TAU * hz * tt) + 0.2 * sin(TAU * hz * 2.0 * tt)) * minf(tt / 0.004, 1.0) * exp(-tt * decay)
		pcm[i] = v


static func _blip(pcm: PackedFloat32Array, hz: float, decay: float) -> void:
	for i in pcm.size():
		var t := float(i) / RATE
		pcm[i] = sin(TAU * hz * t) * minf(t / 0.002, 1.0) * exp(-t * decay)


static func _shimmer(pcm: PackedFloat32Array) -> void:
	var n := pcm.size()
	for i in n:
		var t := float(i) / RATE
		var x := float(i) / n
		var trem := 0.6 + 0.4 * sin(TAU * 18.0 * t)
		pcm[i] = (sin(TAU * 1400.0 * t) + sin(TAU * 1410.0 * t) + sin(TAU * 2100.0 * t) * 0.5) * trem * sin(PI * x)


static func _click(pcm: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for i in pcm.size():
		var t := float(i) / RATE
		var a := (rng.randf() * 2.0 - 1.0) * exp(-t * 500.0)
		var b := sin(TAU * 1800.0 * (t - 0.04)) * exp(-(t - 0.04) * 300.0) if t >= 0.04 else 0.0
		pcm[i] = a * 0.8 + b * 0.6


## Loopable heal-beam hum: integer-cycle partials so the loop point is seamless.
static func _beam(pcm: PackedFloat32Array) -> void:
	var n := pcm.size()
	for i in n:
		var x := float(i) / n
		pcm[i] = sin(TAU * 440.0 * 0.4 * x * 2.5) * 0.5 + sin(TAU * 880.0 * 0.4 * x) * (0.3 + 0.2 * sin(TAU * 4.0 * x)) + sin(TAU * 660.0 * 0.4 * x) * 0.2


## Mechanical clacks at `times` (s): a noise tick plus a short low-pitched knock.
static func _clacks(pcm: PackedFloat32Array, rng: RandomNumberGenerator, times: Array, hz: float, decay: float) -> void:
	for i in pcm.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in times:
			var u := t - float(k)
			if u >= 0.0:
				v += (rng.randf() * 2.0 - 1.0) * exp(-u * 400.0) * 0.5 + sin(TAU * hz * u) * exp(-u * decay) * 0.7
		pcm[i] = v


## Dry-fire hammer click: thin and short, higher than the reload clacks.
static func _dry(pcm: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for i in pcm.size():
		var t := float(i) / RATE
		pcm[i] = (rng.randf() * 2.0 - 1.0) * exp(-t * 700.0) * 0.5 + sin(TAU * 1250.0 * t) * exp(-t * 260.0) * 0.6


## Footstep: low thump with a scuff of noise.
static func _thud(pcm: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for i in pcm.size():
		var t := float(i) / RATE
		pcm[i] = sin(TAU * 78.0 * t) * exp(-t * 34.0) + (rng.randf() * 2.0 - 1.0) * exp(-t * 85.0) * 0.35
