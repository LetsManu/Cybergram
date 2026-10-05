class_name AmbientAudio
extends Node
## W18-LIFE: distant city hum (client presentation only). Two procedurally
## synthesized seamless loops (no audio files) on the Effects bus, at low
## volume so they sit under gameplay sound:
##  * hum: low mains-like drone with a slow swell (all levels);
##  * wash: band-limited noise with slow swells, far traffic (Medium and up).
## Streams are synthesized once per process and cached.

const RATE := 22050
const LOOP_S := 4.0
const HUM_DB := -26.0
const WASH_DB := -31.0

static var _hum: AudioStreamWAV
static var _wash: AudioStreamWAV

var level: int = AmbientComfort.HIGH
var _hum_p: AudioStreamPlayer
var _wash_p: AudioStreamPlayer


func _ready() -> void:
	GameSettings.shared().apply_audio()  # creates the Effects bus when missing
	if _hum == null:
		_hum = make_loop(false)
		_wash = make_loop(true)
	_hum_p = _player(_hum, HUM_DB)
	_wash_p = _player(_wash, WASH_DB)
	set_level(level)


## Wash layer only from Medium up; the hum always plays.
func set_level(lvl: int) -> void:
	level = lvl
	if _wash_p != null:
		_wash_p.volume_db = WASH_DB if lvl >= AmbientComfort.MEDIUM else -80.0


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = GameSettings.BUS_EFFECTS
	p.volume_db = db
	p.autoplay = true
	add_child(p)
	return p


## Synthesizes one seamless mono 16-bit loop of LOOP_S seconds (`seconds`
## override for tests). Deterministic (fixed seeds). Every periodic part has a
## whole number of cycles in the loop, and the noise is cross-faded across the
## seam, so the loop point is inaudible.
static func make_loop(wash: bool, seconds: float = LOOP_S) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var fade := int(RATE * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331 if wash else 1337
	var noise := PackedFloat32Array()
	noise.resize(n + fade)
	var lp := 0.0
	var lp2 := 0.0
	for i in n + fade:
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * (0.08 if wash else 0.02)
		lp2 += (lp - lp2) * (0.3 if wash else 0.05)
		noise[i] = (lp - lp2 * 0.6) if wash else lp2 * 6.0
	var data := PackedByteArray()
	data.resize(n * 2)
	var peak := 0.0
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var nz := noise[i]
		if i < fade:
			var k := i / float(fade)
			nz = noise[n + i] * (1.0 - k) + noise[i] * k
		var t := i / float(RATE)
		var swell := 0.75 + 0.25 * sin(TAU * t / seconds)
		var v := 0.0
		if wash:
			v = nz * (0.6 + 0.4 * sin(TAU * t * 2.0 / seconds + 1.0)) * swell
		else:
			v = (sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 110.0 * t) * 0.22 + sin(TAU * 165.0 * t) * 0.08) * swell + nz * 0.4
		buf[i] = v
		peak = maxf(peak, absf(v))
	var g := 0.6 / maxf(peak, 0.0001)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s
