class_name HudTuningDef
extends Resource
## HUD tuning knobs (design/ux/hud.md §18 and §3.2), data-driven:
## assets/ui/hud_tuning.tres. Layout fractions are of the safe area.

const DEFAULT_PATH := "res://assets/ui/hud_tuning.tres"

@export_group("Layout")
## Design canvas the HUD is laid out in (16:9 at 1080p = scale 1.0).
@export var design_size: Vector2 = Vector2(1920.0, 1080.0)
## Smallest design canvas; below it the HUD scales down instead of cramping
## (keeps 1280x720 at scale 0.9 so 18 px text stays >= 16 px, hud.md §15).
@export var min_design_size: Vector2 = Vector2(1422.0, 800.0)
@export var min_scale: float = 0.9
## Safe margin per edge, fraction of the region (hud.md §3.2: 3% default, 0-8%).
@export_range(0.0, 0.08) var safe_margin: float = 0.03

@export_group("Kill feed")
@export var kill_feed_rows: int = 5
@export var kill_feed_seconds: float = 6.0
@export var kill_feed_name_chars: int = 16

@export_group("Centre feedback")
@export var hit_marker_seconds: float = 0.12
@export var kill_marker_seconds: float = 0.3
## Compact damage numbers merge hits on one target within this window.
@export var damage_merge_seconds: float = 0.5
@export var damage_number_seconds: float = 0.9
## Damage numbers float this far above the target (hud.md §13.2: 0.6 m).
@export var damage_number_lift_m: float = 0.6

@export_group("Vitals")
## HP bar segment size (hud.md §4.2: each segment = 50 HP).
@export var hp_segment: int = 50
@export var caution_frac: float = 0.5
@export var low_hp_frac: float = 0.25
@export var lumen_flyout_seconds: float = 1.2

@export_group("World health plates")
## Plate width in px at 1080p, at `plate_near_m` and nearer / at `plate_far_m` and beyond.
@export var plate_max_width: float = 72.0
@export var plate_min_width: float = 36.0
@export var plate_near_m: float = 6.0
@export var plate_far_m: float = 40.0
## Plates are hidden beyond this distance.
@export var plate_max_distance_m: float = 70.0
@export var plate_height_m: float = 2.2
## W11-V1: allies' plates (name + bar) stay visible out to this range, through walls.
@export var plate_ally_max_distance_m: float = 250.0
## Name text size in px at 1080p.
@export var plate_name_size: int = 13

@export_group("Objective tracker")
## Show the nearest task within this range (hud.md §4.9, §18: 40 m).
@export var tracker_range_m: float = 40.0
