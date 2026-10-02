class_name HeroDef
extends Resource
## Minimal hero definition for M1 combat (architecture.md §6 HeroDef, abridged).
## Stats from design/gdd/heroes.md §3.1. Skills, squads and level growth arrive
## with E10/E15. Hitbox values marked PLACEHOLDER are not in the GDD.

@export var id: StringName = &""
@export var display_name: String = ""
@export_range(1, 5000) var max_hp: int = 250
## Flat damage reduction, 0..1 (heroes.md §3.1: Brannoc 0.20).
@export_range(0.0, 0.7, 0.01) var armor: float = 0.0
## Run speed (m/s). Overrides MovementDef.base_move_speed for this hero.
@export_range(0.0, 20.0, 0.1) var move_speed: float = 6.0
@export var weapon: WeaponDef

@export_group("Hitbox")
## Linear scale of the hitbox. heroes.md §3.1: Brannoc +25% volume -> 1.25^(1/3) = 1.077.
@export_range(0.5, 2.0, 0.001) var hitbox_scale: float = 1.0
## PLACEHOLDER. Body capsule radius and top height above the feet (standing, m).
@export_range(0.1, 2.0, 0.01) var body_radius: float = 0.4
@export_range(0.5, 3.0, 0.01) var body_top_m: float = 1.42
## PLACEHOLDER. Head sphere centre height above the feet (standing) and radius (m).
@export_range(0.5, 3.0, 0.01) var head_center_m: float = 1.6
@export_range(0.05, 1.0, 0.01) var head_radius: float = 0.2


## `base` with this hero's run speed (a per-hero copy; `base` is not mutated).
func movement_for(base: MovementDef) -> MovementDef:
	if is_equal_approx(base.base_move_speed, move_speed):
		return base
	var m := base.duplicate() as MovementDef
	m.base_move_speed = move_speed
	return m
