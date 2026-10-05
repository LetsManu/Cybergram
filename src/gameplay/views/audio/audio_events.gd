class_name AudioEvents
extends Node
## W21-A1: plays AudioEventDefs through bounded voice pools (presentation only).
##   play(id, relation, at)  one-shot; `relation` is AudioEventDef.OwnerFilter
##                           (OWN / ENEMY / ALLY) of whoever caused the sound;
##                           `at` = world position for 3D events.
##   start_loop / move_loop / stop_loop  looping 3D events keyed by any id.
## Per play: owner filter, cooldown, max-distance cull, distance priority,
## voice limit (AudioVoicePool: steal lowest-priority oldest), variant pick and
## volume / pitch jitter from the injected `rng` (deterministic in tests), and
## the night-mode offset. Emits `played` for listeners (MixDucker, music heat).

signal played(id: StringName, at: Variant, relation: int)

var bank: AudioEventBank
## Injected for deterministic variation (tests seed it).
var rng := RandomNumberGenerator.new()
## Settings for night mode (null = process-wide).
var settings: GameSettings
## Callable() -> Variant: listener world position (null = unknown: no distance rules).
var listener_fn: Callable
## Callable() -> int: monotonic msec (tests inject a fake clock).
var clock_fn: Callable = func() -> int: return Time.get_ticks_msec()

var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: AudioVoicePool
var _pool_3d: AudioVoicePool
var _loop_free: Array[AudioStreamPlayer3D] = []
var _loops: Dictionary = {}  # key -> AudioStreamPlayer3D
var _last_ms: Dictionary = {}  # id -> msec of the last start
var _last_variant: Dictionary = {}  # id -> variant index


func _init(event_bank: AudioEventBank = null) -> void:
	bank = event_bank


func _ready() -> void:
	GameSettings.shared().apply_audio()
	if bank == null:
		bank = AudioEventBank.shared()
	var d := bank.def
	_pool_2d = AudioVoicePool.new(d.pool_2d)
	_pool_3d = AudioVoicePool.new(d.pool_3d)
	for i in d.pool_2d:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)
	for i in d.pool_3d:
		var p := AudioStreamPlayer3D.new()
		add_child(p)
		_players_3d.append(p)
	for i in d.pool_loops:
		var p := AudioStreamPlayer3D.new()
		add_child(p)
		_loop_free.append(p)


## Bounded node count (tests): every player this node owns.
func voice_count() -> int:
	return _players_2d.size() + _players_3d.size() + _loop_free.size() + _loops.size()


## Plays event `id`; returns the player used or null (filtered / culled / dropped).
func play(id: StringName, relation: int = AudioEventDef.OwnerFilter.ANY, at: Variant = null,
		gain_db: float = 0.0) -> Node:
	var e := bank.get_def(id)
	if e == null or not e.accepts(relation):
		return null
	var now: int = clock_fn.call()
	if e.cooldown_ms > 0 and _last_ms.has(id) and now - int(_last_ms[id]) < e.cooldown_ms:
		return null
	var streams := bank.streams_for(id)
	if streams.is_empty():
		return null
	var positional := e.spatial == AudioEventDef.Spatial.POSITIONAL_3D and at is Vector3
	var dist := 0.0
	if positional:
		var lis: Variant = listener_fn.call() if listener_fn.is_valid() else null
		if lis is Vector3:
			dist = (lis as Vector3).distance_to(at)
			if e.max_distance_m > 0.0 and dist > e.max_distance_m:
				return null
	var pool := _pool_3d if positional else _pool_2d
	_sync(pool, positional)
	var slot := pool.claim(id, e.priority_at(dist), e.max_voices, now)
	if slot < 0:
		return null
	_last_ms[id] = now
	var v := bank.pick(id, rng, int(_last_variant.get(id, -1)))
	_last_variant[id] = v
	var db := e.volume_db + gain_db + rng.randf_range(-e.vol_jitter_db, e.vol_jitter_db) + _night_db(e)
	var pitch := maxf(e.pitch * (1.0 + rng.randf_range(-e.pitch_jitter, e.pitch_jitter)), 0.05)
	if positional:
		var p3 := _players_3d[slot]
		_setup_3d(p3, e, streams[v], db, pitch)
		p3.global_position = at if p3.is_inside_tree() else Vector3.ZERO
		p3.play()
		played.emit(id, at, relation)
		return p3
	var p2 := _players_2d[slot]
	p2.stream = streams[v]
	p2.bus = e.bus
	p2.volume_db = db
	p2.pitch_scale = pitch
	p2.play()
	played.emit(id, at, relation)
	return p2


## Starts looping event `id` under `key` at `at` (no-op if already running or no free voice).
func start_loop(id: StringName, key: Variant, at: Vector3, gain_db: float = 0.0) -> bool:
	if _loops.has(key) or _loop_free.is_empty():
		return false
	var e := bank.get_def(id)
	if e == null:
		return false
	var streams := bank.streams_for(id)
	if streams.is_empty():
		return false
	var p: AudioStreamPlayer3D = _loop_free.pop_back()
	_setup_3d(p, e, streams[0], e.volume_db + gain_db + _night_db(e), e.pitch)
	if p.is_inside_tree():
		p.global_position = at
	p.play()
	_loops[key] = p
	return true


func move_loop(key: Variant, at: Vector3) -> void:
	var p: AudioStreamPlayer3D = _loops.get(key)
	if p != null and p.is_inside_tree():
		p.global_position = at


func stop_loop(key: Variant) -> void:
	var p: AudioStreamPlayer3D = _loops.get(key)
	if p == null:
		return
	p.stop()
	_loops.erase(key)
	_loop_free.append(p)


func has_loop(key: Variant) -> bool:
	return _loops.has(key)


func _setup_3d(p: AudioStreamPlayer3D, e: AudioEventDef, s: AudioStream, db: float, pitch: float) -> void:
	p.stream = s
	p.bus = e.bus
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = e.unit_size
	p.max_distance = e.max_distance_m
	p.attenuation_model = e.attenuation as AudioStreamPlayer3D.AttenuationModel


func _night_db(e: AudioEventDef) -> float:
	var gs := settings if settings != null else GameSettings.shared()
	return e.night_db if gs.night_mode else 0.0


## Frees pool slots whose players finished.
func _sync(pool: AudioVoicePool, positional: bool) -> void:
	for i in pool.size():
		if pool.is_busy(i):
			var playing: bool = _players_3d[i].playing if positional else _players_2d[i].playing
			if not playing:
				pool.release(i)
