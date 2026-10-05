class_name AudioEventBank
extends RefCounted
## W21-A1: event id -> AudioEventDef + resolved variant streams (presentation
## only). Resolution order per event (AudioEventDef doc): explicit streams,
## file_paths, convention files res://assets/audio/<folder>/<stem>_NN.ogg,
## then the SfxSynth fallback archetype. File probing and loading are
## injectable (`exists_fn`, `load_fn`) so tests can simulate missing files.

const DEF_PATH := "res://assets/data/audio/audio_events.tres"

static var _shared: AudioEventBank

var def: AudioEventBankDef
## Callable(path: String) -> bool. Default: ResourceLoader.exists.
var exists_fn: Callable
## Callable(path: String) -> AudioStream. Default: load().
var load_fn: Callable
## Callable(recipe: StringName) -> AudioStream. Default: SfxBank archetypes.
var synth_fn: Callable
var _defs: Dictionary = {}  # id -> AudioEventDef
var _streams: Dictionary = {}  # id -> Array[AudioStream] (resolved lazily)
## id -> "file" | "synth" | "none" after resolution (diagnostics, evidence).
var source: Dictionary = {}


## The process-wide bank built from DEF_PATH (loaded on first use).
static func shared() -> AudioEventBank:
	if _shared == null:
		_shared = AudioEventBank.new(load(DEF_PATH) as AudioEventBankDef)
	return _shared


func _init(bank_def: AudioEventBankDef = null) -> void:
	def = bank_def if bank_def != null else AudioEventBankDef.new()
	exists_fn = func(p: String) -> bool: return ResourceLoader.exists(p)
	load_fn = func(p: String) -> AudioStream: return load(p) as AudioStream
	synth_fn = func(r: StringName) -> AudioStream: return SfxBank.shared().stream(r)
	for e in def.events:
		if e != null:
			_defs[e.id] = e


func has(id: StringName) -> bool:
	return _defs.has(id)


func get_def(id: StringName) -> AudioEventDef:
	return _defs.get(id)


func ids() -> Array:
	return _defs.keys()


## Adds or replaces an event at runtime (tests, debug tools).
func add(e: AudioEventDef) -> void:
	_defs[e.id] = e
	_streams.erase(e.id)


## Every playable variant of `id` (empty = silent event / unknown id).
func streams_for(id: StringName) -> Array[AudioStream]:
	if _streams.has(id):
		return _streams[id]
	var out: Array[AudioStream] = []
	var e: AudioEventDef = _defs.get(id)
	if e == null:
		return out
	for s in e.streams:
		if s != null:
			out.append(s)
	for p in e.file_paths:
		_try_load(p, out)
	if out.is_empty() and e.file_stem != "":
		for n in range(1, def.max_variants + 1):
			if not _try_load(e.convention_path(n), out):
				break
	source[id] = "file" if not out.is_empty() else "none"
	if out.is_empty() and e.synth_recipe != &"":
		var s: AudioStream = synth_fn.call(e.synth_recipe)
		if s != null:
			out.append(s)
			source[id] = "synth"
	if e.loop:
		for s in out:
			_set_loop(s)
	_streams[id] = out
	return out


## Picks one variant with `rng` (never the same as `last` when there are two or more).
func pick(id: StringName, rng: RandomNumberGenerator, last: int = -1) -> int:
	var n := streams_for(id).size()
	if n <= 1:
		return n - 1
	if last < 0 or last >= n:
		return rng.randi_range(0, n - 1)
	var i := rng.randi_range(0, n - 2)
	return i + 1 if i >= last else i


func _try_load(path: String, out: Array[AudioStream]) -> bool:
	if not bool(exists_fn.call(path)):
		return false
	var s: AudioStream = load_fn.call(path)
	if s == null:
		return false
	out.append(s)
	return true


static func _set_loop(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2
