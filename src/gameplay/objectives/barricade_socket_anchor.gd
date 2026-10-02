class_name BarricadeSocketAnchor
extends Marker3D
## Placement anchor for a Barricade socket (match-flow-and-map.md §3.2, §3.5).
## The wall spans the main path across local X. Inactive in M1 (arrives in M3).

## Hardpoint this socket belongs to.
@export var hardpoint_id: StringName
## 0 = the socket on the Concord-HQ side of the zone, 1 = the Syndicate-HQ side.
## Only the socket facing the owner's enemy is active (Canon C5).
@export var side: int = 0
## Lane width the wall must span (metres).
@export var span_m: float = 16.0
