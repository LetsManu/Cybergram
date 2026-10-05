class_name JunglePocketDef
extends Resource
## A small courtyard / plaza inside the between-lane jungle (W18-GEO): a natural
## fight spot that may host a neutral camp later (none is built now). Static
## map data; nothing reads it at runtime yet besides tests and the overview.

@export var id: StringName
## Floor centre (world space, on the floor).
@export var center: Vector3 = Vector3.ZERO
## Footprint x / z size in metres (axis-aligned).
@export var size: Vector2 = Vector2(10.0, 10.0)


func contains_flat(p: Vector3) -> bool:
	return absf(p.x - center.x) <= size.x * 0.5 and absf(p.z - center.z) <= size.y * 0.5
