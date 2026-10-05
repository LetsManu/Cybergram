class_name AmbientBedsDef
extends Resource
## W21-A1: per-zone ambient beds (assets/data/audio/ambient_beds.tres). Zones
## come from the MapDef: base = around each HQ sanctum / armory, jungle =
## jungle pockets, water = water zones, lane = everywhere else.

## Zone -> AudioEventDef id of its looping bed.
@export var beds: Dictionary = {&"base": &"ambient_base_bed", &"lane": &"ambient_lane_bed",
	&"jungle": &"ambient_jungle_bed", &"water": &"ambient_water_bed"}
## Positional crossfade width at a zone edge (m).
@export var crossfade_m: float = 6.0
## Base zone radius around HqDef.sanctum and HqDef.armory (m).
@export var base_radius_m: float = 24.0
## Bed volume glide (s) so camera teleports / respawns do not jump.
@export var glide_s: float = 0.6
## Bed gain by AmbientComfort level (0 Low, 1 Medium, 2 High), dB.
@export var level_db: PackedFloat32Array = PackedFloat32Array([-6.0, -2.0, 0.0])
