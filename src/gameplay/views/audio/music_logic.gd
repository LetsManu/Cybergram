class_name MusicLogic
extends RefCounted
## W21-A1: adaptive-music state machine and intensity (pure logic; MusicDirector
## plays it). design/audio/audio-events.md §Music.
##
## Transition table (event -> state):
##   menu shown                  -> MENU
##   hero pick / lobby           -> PICK
##   phase LOAD, DEPLOY, SKIRMISH, DROUGHT          -> MATCH_EARLY
##   phase SURGE_I, SURGE_II, TIME_OUT              -> MATCH_LATE
##   phase SUDDEN_DEATH                              -> SUDDEN_DEATH
##   match ended, own team won   -> VICTORY (stinger, then silence)
##   match ended, lost or draw   -> DEFEAT  (stinger, then silence)
##   reduce music on, any match state -> STINGERS_ONLY (no loop; stingers only)
## Intensity 0..1 = phase base + combat heat * heat_weight; heat rises per shot
## near the listener and decays linearly to 0 over heat_decay_s.

enum State { NONE, MENU, PICK, MATCH_EARLY, MATCH_LATE, SUDDEN_DEATH, VICTORY, DEFEAT }
const STATE_NAMES := {State.MENU: &"menu", State.PICK: &"pick", State.MATCH_EARLY: &"match_early",
	State.MATCH_LATE: &"match_late", State.SUDDEN_DEATH: &"sudden_death"}
## Stem order in MusicDef.states[*].stems.
enum Stem { PAD, BASS, DRUMS, LEAD }

var def: MusicDef
var heat: float = 0.0
var base: float = 0.3
var intensity: float = 0.3


func _init(music_def: MusicDef = null) -> void:
	def = music_def if music_def != null else MusicDef.new()


## Looping state for a match phase (MatchRules.Phase); NONE for END.
static func state_for_phase(phase: int) -> State:
	match phase:
		MatchRules.Phase.SURGE_I, MatchRules.Phase.SURGE_II, MatchRules.Phase.TIME_OUT:
			return State.MATCH_LATE
		MatchRules.Phase.SUDDEN_DEATH:
			return State.SUDDEN_DEATH
		MatchRules.Phase.END:
			return State.NONE
	return State.MATCH_EARLY


## End-of-match state for `winner` (-1 / neutral = draw) seen by `own_team`.
static func state_for_end(winner: int, own_team: int) -> State:
	return State.VICTORY if winner == own_team else State.DEFEAT


## True for the in-match looping states (6 dB under the menu, heat applies).
static func is_match(s: int) -> bool:
	return s == State.MATCH_EARLY or s == State.MATCH_LATE or s == State.SUDDEN_DEATH


func set_phase(phase: int) -> void:
	base = float(def.phase_intensity.get(phase, base))
	_update()


## A shot `distance_m` from the listener: adds heat inside heat_radius_m.
func add_shot(distance_m: float) -> void:
	if distance_m <= def.heat_radius_m:
		heat = minf(heat + def.heat_per_shot, 1.0)
		_update()


## Advances `dt` seconds (heat decay).
func step(dt: float) -> void:
	if def.heat_decay_s > 0.0:
		heat = maxf(heat - dt / def.heat_decay_s, 0.0)
	else:
		heat = 0.0
	_update()


func _update() -> void:
	intensity = clampf(base + heat * def.heat_weight, 0.0, 1.0)


## Target linear gain per Stem at the current intensity (pad and bass always on).
func stem_targets() -> PackedFloat32Array:
	return PackedFloat32Array([1.0, 1.0,
		1.0 if intensity >= def.drums_threshold else 0.0,
		1.0 if intensity >= def.lead_threshold else 0.0])


## Moves `current` toward `target` at 1 / stem_fade_s per second (frame-rate independent).
func glide(current: PackedFloat32Array, target: PackedFloat32Array, dt: float) -> PackedFloat32Array:
	var out := current.duplicate()
	var k := dt / maxf(def.stem_fade_s, 0.001)
	for i in out.size():
		out[i] = move_toward(out[i], target[i], k)
	return out


## Bar-synced crossfade: Vector2(delay_s until the next bar line, fade_s).
## The fade is a whole number of bars clamped to [crossfade_min_s, crossfade_max_s].
func crossfade_plan(position_s: float, bpm: float, beats_per_bar: int) -> Vector2:
	if bpm <= 0.0:
		return Vector2(0.0, def.crossfade_min_s)
	var bar := 60.0 / bpm * float(maxi(beats_per_bar, 1))
	var delay := bar - fmod(position_s, bar)
	if delay >= bar - 0.001:
		delay = 0.0
	var fade := bar * ceilf(def.crossfade_min_s / bar)
	return Vector2(delay, clampf(fade, def.crossfade_min_s, def.crossfade_max_s))
