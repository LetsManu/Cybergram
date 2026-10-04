class_name ClientSfx
extends Node
## Client-only combat sounds (presentation; no gameplay state). Placeholder
## audio synthesized in code at startup, so no audio files are needed until
## the audio director's real assets land:
##   own shot        -> 2D gunshot (louder)
##   other shots     -> 3D gunshot at the shooter (positional, quieter)
##   hit confirm     -> short tick (higher for headshots)
##   kill by you     -> two-note chime
## Driven by ClientWorld's shot_received / hit_confirmed / kill_received.

const RATE := 22050
const OWN_SHOT_DB := -6.0
const REMOTE_SHOT_DB := -2.0
const HIT_DB := -8.0
const KILL_DB := -6.0
const REMOTE_MAX_DISTANCE_M := 90.0
const POOL_2D := 6
const POOL_3D := 10
## Shotgun pellets arrive as several SHOT events in one tick: play one sound.
const SAME_SHOOTER_GAP_MS := 40

var client: Node
var gunshot: AudioStreamWAV
var hit_tick: AudioStreamWAV
var head_tick: AudioStreamWAV
var kill_chime: AudioStreamWAV

var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next_2d: int = 0
var _next_3d: int = 0
var _last_shot_ms: Dictionary = {}  # shooter net id -> msec


func _ready() -> void:
	GameSettings.shared().apply_audio()  # creates the Effects / UI buses
	gunshot = synth_gunshot()
	hit_tick = synth_tone(1700.0, 0.05)
	head_tick = synth_tone(2600.0, 0.06)
	kill_chime = synth_chime()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = GameSettings.BUS_EFFECTS
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = GameSettings.BUS_EFFECTS
		p.max_distance = REMOTE_MAX_DISTANCE_M
		p.unit_size = 8.0
		add_child(p)
		_pool_3d.append(p)
	if client != null:
		client.shot_received.connect(_on_shot)
		client.hit_confirmed.connect(_on_hit)
		client.kill_received.connect(_on_kill)


func _on_shot(e: GameEvent) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_shot_ms.get(e.source_net_id, -1000)) < SAME_SHOOTER_GAP_MS:
		return
	_last_shot_ms[e.source_net_id] = now
	if e.source_net_id == client.session.own_net_id:
		play_2d(gunshot, OWN_SHOT_DB, randf_range(0.95, 1.05))
		return
	var at: Variant = client.call("hero_view_position", e.source_net_id)
	if at != null:
		play_3d(gunshot, at, REMOTE_SHOT_DB, randf_range(0.9, 1.1))


func _on_hit(e: GameEvent) -> void:
	var head := (e.flags & GameEvent.FLAG_HEADSHOT) != 0
	play_2d(head_tick if head else hit_tick, HIT_DB, 1.0)


func _on_kill(e: GameEvent) -> void:
	if e.source_net_id == client.session.own_net_id:
		play_2d(kill_chime, KILL_DB, 1.0)


func play_2d(stream: AudioStream, db: float, pitch: float) -> AudioStreamPlayer:
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return p


func play_3d(stream: AudioStream, at: Vector3, db: float, pitch: float) -> AudioStreamPlayer3D:
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = stream
	p.global_position = at
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return p


## Noise crack with a fast decay over a low thump (0.22 s).
static func synth_gunshot() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.55)  # soften the hiss a little
		var crack := lp * exp(-t * 38.0)
		var thump := sin(TAU * (95.0 - 40.0 * t) * t) * exp(-t * 18.0)
		pcm[i] = clampf(crack * 0.75 + thump * 0.6, -1.0, 1.0)
	return _to_wav(pcm)


## Short sine blip with a click-free attack.
static func synth_tone(hz: float, length_s: float) -> AudioStreamWAV:
	var n := int(RATE * length_s)
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.004, 1.0) * exp(-t * 60.0)
		pcm[i] = sin(TAU * hz * t) * env * 0.8
	return _to_wav(pcm)


## Two rising notes (kill confirm).
static func synth_chime() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var pcm := PackedFloat32Array()
	pcm.resize(n)
	for i in n:
		var t := float(i) / RATE
		var hz := 660.0 if t < 0.11 else 990.0
		var tt := t if t < 0.11 else t - 0.11
		var env := minf(tt / 0.005, 1.0) * exp(-tt * 14.0)
		pcm[i] = (sin(TAU * hz * t) * 0.6 + sin(TAU * hz * 2.0 * t) * 0.15) * env
	return _to_wav(pcm)


static func _to_wav(pcm: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(pcm.size() * 2)
	for i in pcm.size():
		bytes.encode_s16(i * 2, int(clampf(pcm[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
