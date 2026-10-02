class_name FlankLoopDef
extends Resource
## A flank loop between an Outer side door and the Mid side door
## (match-flow-and-map.md §3.7: one per half, ~90 m vs 65 m main path).

@export var id: StringName
## Hardpoint ids the loop links (Outer, Mid).
@export var from_hardpoint: StringName
@export var to_hardpoint: StringName
## Door positions on the floor, in world metres.
@export var outer_door: Vector3
@export var mid_door: Vector3
## Centreline waypoints from outer_door to mid_door (inclusive), for AI and tests.
@export var waypoints: PackedVector3Array = PackedVector3Array()
