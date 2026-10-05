class_name SfxBankDef
extends Resource
## W10-W5: data for the synthesized sound bank (assets/data/audio/sfx_bank.tres).
## Everything a designer tunes lives here; SfxSynth only holds the waveforms.

## Voice-pool sizes (bounded voice count).
@export_range(1, 32) var pool_2d: int = 6
@export_range(1, 64) var pool_3d: int = 10
@export_range(1, 16) var pool_ui: int = 3
@export_range(1, 8) var pool_loops: int = 2
## WeaponDef.sfx_voice -> {archetype: StringName, pitch: float, db: float}.
@export var weapon_voices: Dictionary = {}
## SkillDef id -> {cast: StringName, impact: StringName (optional), pitch: float}.
@export var skills: Dictionary = {}
## Replicated FX kind (int) -> archetype played when that FX first appears
## (impact / explode / deploy). Kinds without an entry are silent.
@export var fx_impacts: Dictionary = {}
## UI event name -> archetype.
@export var ui: Dictionary = {}
## W11-C1 feel events (reload_start, reload_done, dry_fire, footstep) -> archetype.
@export var feel: Dictionary = {}
@export var feel_db: float = -10.0
@export var footstep_db: float = -18.0
## Own footsteps: voices (bounded pool), metres walked per step, speed below
## which there are none, and the stride / volume multipliers while crouched.
@export_range(1, 4) var pool_feet: int = 2
@export_range(0.5, 6.0, 0.05) var footstep_stride_m: float = 2.3
@export_range(0.0, 5.0, 0.05) var footstep_min_speed: float = 1.2
@export_range(0.5, 3.0, 0.05) var footstep_crouch_stride_mult: float = 1.4
@export var cast_db: float = -6.0
@export var impact_db: float = -4.0
@export var ui_db: float = -8.0
@export var beam_db: float = -14.0
