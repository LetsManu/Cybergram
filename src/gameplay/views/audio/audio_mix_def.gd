class_name AudioMixDef
extends Resource
## W21-A1: in-match mix tuning (assets/data/audio/audio_mix.tres): code-driven
## ducks (the Voice duck itself is the side-chain compressor in GameSettings),
## low-HP heartbeat, low-ammo tick and the combat-derived sound rules.

## Ambient -3 dB while a weapon fired within weapon_duck_radius_m in the last weapon_duck_hold_s.
@export var ambient_weapon_duck_db: float = -3.0
@export var weapon_duck_radius_m: float = 15.0
@export var weapon_duck_hold_s: float = 0.6
## Music -4 dB on big moments (enemy ult, explosion, high-priority announcer line).
@export var music_big_moment_db: float = -4.0
@export var big_moment_hold_s: float = 2.5
## Duck glide times (attack / release), seconds.
@export var duck_attack_s: float = 0.05
@export var duck_release_s: float = 0.4
## Heartbeat below this HP fraction (own hero alive), beats per second at 0 HP / at the threshold.
@export_range(0.0, 1.0, 0.01) var heartbeat_hp_frac: float = 0.3
@export var heartbeat_rate_min_hz: float = 1.1
@export var heartbeat_rate_max_hz: float = 2.0
## Low-ammo tick on the last fraction of the magazine / pool (own only).
@export_range(0.0, 1.0, 0.01) var low_ammo_frac: float = 0.2
## Damage-taken pan: hits whose source is within this angle of straight ahead play centred.
@export var damage_center_deg: float = 20.0
## Damage direction source: a SHOT ending within this distance of the own hero (and this recent).
@export var damage_shot_radius_m: float = 3.0
@export var damage_shot_window_ms: int = 400
## Assist: an own hit on the victim within this window before someone else's kill.
@export var assist_window_s: float = 6.0
## Landing: vertical speed (m/s) at touchdown for light / heavy landings.
@export var land_light_mps: float = 4.0
@export var land_heavy_mps: float = 9.0
## Remote footsteps: stride (m) and minimum ground speed for enemy steps.
@export var remote_stride_m: float = 2.3
@export var remote_min_speed: float = 1.5
## Surfaces: hardpoint platforms are metal, Y above grate_min_y is a catwalk grate; else concrete.
@export var grate_min_y: float = 2.5
