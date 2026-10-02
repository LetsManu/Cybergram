class_name WeaponDef
extends Resource
## One hero weapon (design/gdd/weapons-and-mods.md §3.2 stat model, §3.3 table).
## Mana guns use the pool fields, Mechanical guns the magazine fields; feed_kind
## selects ManaPoolFeed or MagazineFeed (architecture.md §5.2). Level-1 values.
## Values marked PLACEHOLDER are not given by the GDD.

enum FeedKind { MANA, MAGAZINE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var feed_kind: FeedKind = FeedKind.MANA
## HP per hit (per pellet), level 1, before falloff and armor.
@export_range(0.0, 500.0, 0.1) var damage: float = 20.0
## Hits per trigger pull (Ironmaw: 10 pellets).
@export_range(1, 32) var pellets: int = 1
## Shots per second (cap for semi-auto).
@export_range(0.1, 30.0, 0.01) var fire_rate: float = 5.0
## True: one shot per trigger press (semi-auto). False: fires while held.
@export var semi_auto: bool = false
@export_range(1.0, 4.0, 0.01) var headshot_mult: float = 1.5
## Falloff (§4.3): full damage to start, linear to falloff_min at end, flat beyond (m).
@export_range(0.0, 200.0, 0.1) var falloff_start_m: float = 20.0
@export_range(0.0, 200.0, 0.1) var falloff_end_m: float = 40.0
@export_range(0.0, 1.0, 0.01) var falloff_min: float = 0.6
## Cone half-angles in degrees (§3.2). A fixed cone has base = max and bloom 0.
@export_range(0.0, 20.0, 0.01) var spread_base_deg: float = 0.5
@export_range(0.0, 10.0, 0.01) var spread_bloom_deg: float = 0.1
@export_range(0.0, 20.0, 0.01) var spread_max_deg: float = 2.0
## §3.2: spread recovers at 6 deg/s after 0.15 s without firing.
@export_range(0.0, 60.0, 0.1) var spread_recovery_deg_s: float = 6.0
@export_range(0.0, 2.0, 0.01) var spread_recovery_delay_s: float = 0.15
## PLACEHOLDER. Hitscan max range (m); the GDD has no hard max except Glitchcaster.
@export_range(1.0, 500.0, 1.0) var range_m: float = 150.0

@export_group("Mana feed")
@export_range(1, 1000) var mana_pool: int = 100
@export_range(0.0, 100.0, 0.1) var mana_cost: float = 6.0
@export_range(0.0, 500.0, 0.1) var mana_regen: float = 35.0
@export_range(0.0, 10.0, 0.01) var mana_regen_delay_s: float = 1.0
## §3.5 Burnout: emptying the pool multiplies the regen delay.
@export_range(1.0, 4.0, 0.01) var burnout_delay_mult: float = 1.5

@export_group("Magazine feed")
@export_range(1, 500) var magazine: int = 30
@export_range(0, 2000) var reserve: int = 150
@export_range(0.0, 10.0, 0.01) var reload_s: float = 1.6
## Reload time from an empty magazine (0 = same as reload_s).
@export_range(0.0, 10.0, 0.01) var reload_empty_s: float = 0.0
## True: reload_s loads ONE round, repeated until full (Ironmaw shells); firing
## interrupts it. False: one committed reload moves a full magazine.
@export var reload_per_round: bool = false

@export_group("Art")
## Procedural model key (ModelCatalog), e.g. &"vesper". Empty = derived from `id`.
@export var model_id: StringName = &""
## Optional authored model scene; when set, views instance it instead of the
## procedural stand-in (the swap path for final art).
@export var model_scene: PackedScene


## Ticks between shots at `tick_rate_hz` (fractional; WeaponSim accumulates).
func fire_interval_ticks(tick_rate_hz: int) -> float:
	return tick_rate_hz / fire_rate
