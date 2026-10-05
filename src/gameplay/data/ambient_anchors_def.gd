class_name AmbientAnchorsDef
extends Resource
## Named mount points and routes for background life (W18-GEO writes it from the
## map builder; W18-LIFE presentation reads it). Static map data only: nothing
## here is simulated on the server or replicated. Format and conventions:
## docs/architecture/ambient-anchors.md.
##
## Mount convention (billboards, neon signs, shop signs, steam vents): a world
## Transform3D whose origin is the centre of the mount surface and whose basis
## is orthonormal with +Z = the outward face normal (the direction a viewer
## stands in), +Y = up, +X = the sign's right edge as seen by that viewer.
## Each mount kind keeps parallel arrays: ids[i], xforms[i], sizes[i] (metres,
## width x height on the face plane).

## Large billboard faces on building walls (video / ad panels).
@export var billboard_ids: PackedStringArray = PackedStringArray()
@export var billboard_xforms: Array[Transform3D] = []
@export var billboard_sizes: PackedVector2Array = PackedVector2Array()

## Small neon sign mounts (building faces, jungle alley walls).
@export var neon_ids: PackedStringArray = PackedStringArray()
@export var neon_xforms: Array[Transform3D] = []
@export var neon_sizes: PackedVector2Array = PackedVector2Array()

## Shop sign slots above market shopfronts (Center lane).
@export var shop_sign_ids: PackedStringArray = PackedStringArray()
@export var shop_sign_xforms: Array[Transform3D] = []
@export var shop_sign_sizes: PackedVector2Array = PackedVector2Array()

## Steam vent emitters in the jungle alleys (+Z = emit direction, usually up).
@export var steam_vent_ids: PackedStringArray = PackedStringArray()
@export var steam_vent_xforms: Array[Transform3D] = []

## Sky traffic lanes outside the playable area: closed polylines (the last
## point connects back to the first), world space, metres.
@export var traffic_path_ids: PackedStringArray = PackedStringArray()
@export var traffic_paths: Array[PackedVector3Array] = []

## The sky-train loop: one closed polyline around the map.
@export var sky_train_route: PackedVector3Array = PackedVector3Array()

## Static dock cranes: node path (relative to the map scene root) of each crane's
## "Boom" pivot, for a presentation chunk to rotate. Pivot yaw 0 = as built.
@export var crane_booms: PackedStringArray = PackedStringArray()


## Number of mounts of every kind (billboards + neon + shop signs + vents).
func mount_count() -> int:
	return billboard_ids.size() + neon_ids.size() + shop_sign_ids.size() + steam_vent_ids.size()
