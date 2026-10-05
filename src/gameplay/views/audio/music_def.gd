class_name MusicDef
extends Resource
## W21-A1: adaptive music tuning (assets/data/audio/music.tres; design/audio/audio-events.md §Music).

## State name (MusicLogic.STATE_NAMES) -> {"stems": PackedStringArray of
## [pad, bass, drums, lead] paths, or "mix": path; "bpm": float; "beats_per_bar": int}.
@export var states: Dictionary = {}
## Stinger kind (victory, defeat, phase, final, sudden_death) -> path.
@export var stingers: Dictionary = {}
## MatchRules.Phase (int) -> base intensity 0..1 of that phase.
@export var phase_intensity: Dictionary = {}
## Combat heat: each shot within heat_radius_m of the listener adds heat_per_shot
## (cap 1); heat decays to 0 over heat_decay_s; intensity = base + heat * heat_weight.
@export var heat_radius_m: float = 25.0
@export var heat_per_shot: float = 0.08
@export var heat_decay_s: float = 6.0
@export var heat_weight: float = 0.45
## Stems: drums above drums_threshold, lead above lead_threshold; gains glide over stem_fade_s.
@export_range(0.0, 1.0, 0.01) var drums_threshold: float = 0.5
@export_range(0.0, 1.0, 0.01) var lead_threshold: float = 0.8
@export var stem_fade_s: float = 1.5
## State crossfades: bar-synced, between crossfade_min_s and crossfade_max_s.
@export var crossfade_min_s: float = 2.0
@export var crossfade_max_s: float = 4.0
## Deck gain per context: menu / pick at menu_db, match states at match_db (6 dB under menu).
@export var menu_db: float = 0.0
@export var match_db: float = -6.0
@export var stinger_db: float = -3.0
## Reduced music: also a stinger when this many seconds remain to the time cap.
@export var final_stinger_s: float = 120.0
