class_name HardpointAnchor
extends Marker3D
## Placement anchor for a hardpoint in a map scene (zone centre on the floor).
## Marker only: E7's HardpointSim attaches here by id. No capture logic.

@export var hardpoint_id: StringName
@export var task: HardpointDef.TaskKind = HardpointDef.TaskKind.HOLD
@export var zone_radius: float = 12.0
