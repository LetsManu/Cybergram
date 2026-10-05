class_name ArmoryMarkerDef
extends Resource
## Presentation tuning of the Armory pad marker (world ring + beacon + sign) and
## of the HUD guidance waypoint (W21-G2). Client-only: the server decides
## `at_armory` from EconomyRulesDef.armory_radius_m, the ring is drawn at that
## same radius; nothing here affects gameplay.

const DEFAULT_PATH := "res://assets/data/armory/armory_marker.tres"

@export_group("Floor ring")
## Ring band width (m), inward from the server radius.
@export_range(0.05, 2.0, 0.05) var ring_width_m: float = 0.3
## Lift above the pad floor (m), avoids z-fighting.
@export_range(0.0, 0.5, 0.01) var ring_lift_m: float = 0.05
@export_range(0.0, 1.0, 0.05) var ring_alpha: float = 0.85
## Faint disc inside the ring (0 = none).
@export_range(0.0, 1.0, 0.01) var disc_alpha: float = 0.1
## Share of white mixed into the team colour so the ring reads as light.
@export_range(0.0, 1.0, 0.05) var white_mix: float = 0.25

@export_group("Beacon and sign")
@export_range(5.0, 120.0, 1.0) var beacon_height_m: float = 45.0
@export_range(0.1, 3.0, 0.05) var beacon_radius_m: float = 0.7
@export_range(0.0, 1.0, 0.05) var beacon_alpha: float = 0.55
## Sign height above the pad (m) and its fixed on-screen font size.
@export_range(1.0, 60.0, 0.5) var sign_height_m: float = 9.0
@export_range(8, 128) var sign_font_size: int = 40
## The sign hides within this distance of the pad centre (the [F] prompt takes over)
## and fades out beyond sign_far_m.
@export_range(0.0, 20.0, 0.5) var sign_hide_within_m: float = 7.0
@export_range(10.0, 400.0, 5.0) var sign_far_m: float = 160.0

@export_group("Pulse (Lumen to spend)")
@export_range(0.1, 4.0, 0.1) var pulse_hz: float = 0.8
## Brightness swing of ring and beacon while pulsing (reduced motion: steady at the high end).
@export_range(0.0, 1.0, 0.05) var pulse_depth: float = 0.45

@export_group("Guidance waypoint")
## The waypoint only shows while the hero is this close (m, flat) to its own Sanctum.
@export_range(10.0, 200.0, 1.0) var guide_base_radius_m: float = 60.0
## Seconds the waypoint shows after the first spawn of the match even with no Lumen.
@export_range(0.0, 30.0, 0.5) var guide_spawn_s: float = 8.0
## Fraction of the screen width kept free at each edge for the arrow.
@export_range(0.0, 0.3, 0.01) var guide_edge_margin: float = 0.06
