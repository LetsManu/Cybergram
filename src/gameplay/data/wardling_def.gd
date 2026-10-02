class_name WardlingDef
extends Resource
## One Wardling variant at Tier I (design/gdd/wardlings-and-economy.md §4, §6).
## Picket = the baseline every variant multiplies. Values marked PLACEHOLDER
## are not given by the GDD.

@export var id: StringName = &""
@export var display_name: String = ""
## Two-letter squad-strip glyph (hud.md §4.6: Pk, Sh, St...).
@export var glyph: String = "Pk"
@export_range(1.0, 5000.0, 1.0) var max_hp: float = 150.0
@export_range(0.0, 0.7, 0.01) var armor: float = 0.0
@export_range(0.0, 200.0, 0.1) var bolt_damage: float = 7.0
## Seconds between bolts (0.333 = 3 bolts/s).
@export_range(0.05, 5.0, 0.001) var fire_interval_s: float = 0.333
@export_range(1.0, 100.0, 0.5) var range_m: float = 22.0
## Mana bolt speed (slow, dodgeable; no hitscan).
@export_range(5.0, 200.0, 0.5) var projectile_speed: float = 55.0
## Full spread cone in degrees: Attack Target (focused) and otherwise.
@export_range(0.0, 20.0, 0.1) var spread_focused_deg: float = 2.5
@export_range(0.0, 20.0, 0.1) var spread_retaliation_deg: float = 4.0
@export_range(0.0, 20.0, 0.1) var move_speed: float = 6.5
## Catch-up sprint (more than 10 m from the slot, or returning).
@export_range(0.0, 20.0, 0.1) var sprint_speed: float = 8.5
## Hold presence (C4).
@export_range(0.0, 2.0, 0.05) var presence: float = 0.5
## PLACEHOLDER. Body capsule radius / height (m), also the avoidance radius.
@export_range(0.1, 2.0, 0.01) var radius: float = 0.45
@export_range(0.3, 3.0, 0.01) var height: float = 1.2
## PLACEHOLDER. Bolt muzzle / chest height above the feet (m).
@export_range(0.1, 3.0, 0.01) var chest_m: float = 0.75

@export_group("Art")
## Procedural model key (ModelCatalog), e.g. &"vesper". Empty = derived from `id`.
@export var model_id: StringName = &""
## Optional authored model scene; when set, views instance it instead of the
## procedural stand-in (the swap path for final art).
@export var model_scene: PackedScene
