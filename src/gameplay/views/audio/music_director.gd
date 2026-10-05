class_name MusicDirector
extends Node
## W21-A1: plays MusicLogic (design/audio/audio-events.md §Music). One per
## process, created lazily under the SceneTree root so music survives the
## menu -> match handover. A no-op headless (never on the dedicated server).
##   MusicDirector.request(MusicLogic.State.MENU)   # menu / pick screens
##   MusicDirector.shared().bind_client(client)     # ClientSfx does this in a match
## Two decks crossfade bar-synced (2-4 s). Match states are 4 synchronized stems
## (AudioStreamSynchronized) whose gains follow the intensity; menu / pick are
## single mixes. Reduced music: no match loop, stingers at phase changes and
## when final_stinger_s remain to the time cap.

const DEF_PATH := "res://assets/data/audio/music.tres"
const SILENT_DB := -80.0

static var _inst: MusicDirector

var def: MusicDef
var logic: MusicLogic
## False headless: every method returns at once.
var enabled: bool = true
## Settings for reduce_music (null = process-wide).
var settings: GameSettings
var state: int = MusicLogic.State.NONE
var client: Node
var _decks: Array[AudioStreamPlayer] = []
var _deck_state: Array[int] = [MusicLogic.State.NONE, MusicLogic.State.NONE]
var _gain: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _target: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _rate: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
var _active: int = 0
var _pending: int = -1
var _pending_delay: float = 0.0
var _pending_fade: float = 2.0
var _stems: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 0.0, 0.0])
var _stinger: AudioStreamPlayer
var _final_done: bool = false
var _phase: int = -1


## The process-wide director (created on first use; disabled headless).
static func shared() -> MusicDirector:
	if _inst == null or not is_instance_valid(_inst):
		_inst = MusicDirector.new()
		_inst.name = "MusicDirector"
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			tree.root.add_child.call_deferred(_inst)
	return _inst


## Menu hook: `MusicDirector.request(MusicLogic.State.MENU)`.
static func request(s: int) -> void:
	shared().set_state(s)


func _init(music_def: MusicDef = null, headless: bool = DisplayServer.get_name() == "headless") -> void:
	def = music_def if music_def != null else load(DEF_PATH) as MusicDef
	logic = MusicLogic.new(def)
	enabled = not headless
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = GameSettings.BUS_MUSIC
		p.volume_db = SILENT_DB
		add_child(p)
		_decks.append(p)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = GameSettings.BUS_MUSIC
	add_child(_stinger)


func _ready() -> void:
	if enabled:
		GameSettings.shared().apply_audio()
	set_process(enabled)


func _settings() -> GameSettings:
	return settings if settings != null else GameSettings.shared()


## Requests looping state `s` (MusicLogic.State). VICTORY / DEFEAT play their
## stinger and fade the loop out. Bar-synced crossfade from the current loop.
func set_state(s: int) -> void:
	if not enabled:
		return
	if s == MusicLogic.State.VICTORY or s == MusicLogic.State.DEFEAT:
		stinger(&"victory" if s == MusicLogic.State.VICTORY else &"defeat")
		state = s
		_queue(MusicLogic.State.NONE)
		return
	if s == state and _pending < 0:
		return
	state = s
	var loop_state := s
	if MusicLogic.is_match(s) and _settings().reduce_music:
		loop_state = MusicLogic.State.NONE
	if loop_state == _deck_state[_active] and _pending < 0:
		return
	_queue(loop_state)


func _queue(loop_state: int) -> void:
	var cur := _deck_state[_active]
	var plan := Vector2(0.0, def.crossfade_min_s)
	if cur != MusicLogic.State.NONE and _decks[_active].playing:
		var info: Dictionary = def.states.get(MusicLogic.STATE_NAMES.get(cur, &""), {})
		plan = logic.crossfade_plan(_decks[_active].get_playback_position(), float(info.get("bpm", 0.0)),
			int(info.get("beats_per_bar", 4)))
	_pending = loop_state
	_pending_delay = plan.x
	_pending_fade = plan.y


## One-shot stinger by kind (MusicDef.stingers) on the Music bus.
func stinger(kind: StringName) -> void:
	if not enabled:
		return
	var path: String = def.stingers.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	_stinger.stream = load(path)
	_stinger.volume_db = def.stinger_db
	_stinger.play()


## Follows a ClientWorld (duck-typed: match_phase_changed, match_ended,
## shot_received, match_state, own_team(), hero_view_position(), body).
func bind_client(c: Node) -> void:
	if not enabled or c == client:
		return
	client = c
	_final_done = false
	_phase = -1
	c.match_phase_changed.connect(on_phase)
	c.match_ended.connect(func(winner: int, _reason: int) -> void:
		set_state(MusicLogic.state_for_end(winner, c.own_team())))
	c.shot_received.connect(_on_shot)
	c.tree_exiting.connect(func() -> void:
		if client == c:
			client = null)
	set_state(MusicLogic.State.MATCH_EARLY)


## Match phase change (MatchRules.Phase).
func on_phase(phase: int) -> void:
	if not enabled or phase == _phase:
		return
	var first := _phase < 0
	_phase = phase
	logic.set_phase(phase)
	if phase == MatchRules.Phase.SUDDEN_DEATH:
		stinger(&"sudden_death")
	elif not first and _settings().reduce_music and phase != MatchRules.Phase.END:
		stinger(&"phase")
	var s := MusicLogic.state_for_phase(phase)
	if s != MusicLogic.State.NONE:
		set_state(s)


## Combat heat from a shot `distance_m` from the listener.
func add_heat(distance_m: float) -> void:
	if enabled:
		logic.add_shot(distance_m)


func _on_shot(e: GameEvent) -> void:
	if client == null or client.body == null:
		return
	var at: Variant = client.hero_view_position(e.source_net_id)
	var d := 0.0 if at == null else (at as Vector3).distance_to(client.body.state.position)
	add_heat(d)


func _process(delta: float) -> void:
	if _pending >= 0:
		_pending_delay -= delta
		if _pending_delay <= 0.0:
			_switch(_pending, _pending_fade)
			_pending = -1
	logic.step(delta)
	_stems = logic.glide(_stems, logic.stem_targets(), delta)
	for i in 2:
		_gain[i] = move_toward(_gain[i], _target[i], delta * _rate[i])
		var st := _deck_state[i]
		var base := def.match_db if MusicLogic.is_match(st) else def.menu_db
		_decks[i].volume_db = base + linear_to_db(maxf(_gain[i], 0.0001)) if _gain[i] > 0.0 else SILENT_DB
		if _gain[i] <= 0.0 and _target[i] <= 0.0 and _decks[i].playing:
			_decks[i].stop()
			_deck_state[i] = MusicLogic.State.NONE
		var sync := _decks[i].stream as AudioStreamSynchronized
		if sync != null:
			for k in mini(sync.stream_count, _stems.size()):
				sync.set_sync_stream_volume(k, linear_to_db(maxf(_stems[k], 0.0001)) if _stems[k] > 0.0 else SILENT_DB)
	_check_final()


func _check_final() -> void:
	if client == null or _final_done or not _settings().reduce_music:
		return
	var ms = client.match_state
	var rules = client.match_rules if client.match_rules != null else \
		(client.map_def.match_rules if client.map_def != null else null)
	if ms == null or rules == null:
		return
	if MusicLogic.is_match(state) and rules.time_cap_s - ms.time_s <= def.final_stinger_s:
		_final_done = true
		stinger(&"final")


func _switch(loop_state: int, fade_s: float) -> void:
	var rate := 1.0 / maxf(fade_s, 0.05)
	_target[_active] = 0.0
	_rate[_active] = rate
	if loop_state == MusicLogic.State.NONE:
		return
	var nxt := 1 - _active
	var s := _stream_for(loop_state)
	if s == null:
		return
	_decks[nxt].stream = s
	_deck_state[nxt] = loop_state
	_gain[nxt] = 0.0
	_target[nxt] = 1.0
	_rate[nxt] = rate
	_decks[nxt].play()
	_active = nxt


## Builds the loop stream of a state: stems -> AudioStreamSynchronized, else the mix.
func _stream_for(loop_state: int) -> AudioStream:
	var info: Dictionary = def.states.get(MusicLogic.STATE_NAMES.get(loop_state, &""), {})
	if info.has("stems"):
		var sync := AudioStreamSynchronized.new()
		var paths: PackedStringArray = info["stems"]
		sync.stream_count = paths.size()
		for i in paths.size():
			var st := _load_loop(paths[i])
			if st != null:
				sync.set_sync_stream(i, st)
		return sync
	if info.has("mix"):
		return _load_loop(info["mix"])
	return null


static func _load_loop(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


## Deck currently fading in / playing (tests).
func active_deck_state() -> int:
	return _deck_state[_active] if _pending < 0 else _pending
