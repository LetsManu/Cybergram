class_name PlacementRulesDef
extends Resource
## Physical-plausibility rules for every placed world object (owner plan
## 2026-10-06, docs/placement.md). Read by PlacementValidator and PlacementKit.
## Tolerances in metres / degrees; defaults are the shipped values.

## Max gap between an object's base and the surface under it (grounded).
@export var ground_tol_m: float = 0.08
## Fraction of footprint probes (4 corners + centre) that must find a surface
## within ground_tol_m (supported; 0.8 = one corner may overhang).
@export var support_min: float = 0.8
## Max tilt of an upright object from vertical (degrees).
@export var upright_max_deg: float = 10.0
## Shrink of the object's box a side before the interpenetration test (m):
## touching surfaces are fine, overlapping ones are not.
@export var overlap_shrink_m: float = 0.05
## Max gap between a wall-mounted object's back and its wall (m).
@export var mount_gap_m: float = 0.12
## Scale against the hero (HeroDef height): a prop taller than this many hero
## heights, or a floor prop smaller than min_height_ratio, reads wrong.
@export var max_height_ratio: float = 3.2
@export var min_height_ratio: float = 0.08
@export var hero_height_m: float = 1.8
## A terminal / kiosk must face walkable floor: floor within this distance in
## front of its face (m).
@export var front_floor_m: float = 0.8
## Decals: max projection half-height (m), min floor-normal y of the surface.
@export var decal_max_half_height_m: float = 0.6
@export var decal_floor_normal_y: float = 0.9
## Decals whose box meets a wall must fade on steep surfaces at least this much.
@export var decal_min_normal_fade: float = 0.3
