class_name LaneDef
extends Resource
## One lane: its hardpoints in order from the Concord HQ to the Syndicate HQ,
## and its flank loops (match-flow-and-map.md §3.2, §3.7).

@export var id: StringName
## Ordered by lane_index (0 = Concord Inner).
@export var hardpoints: Array[HardpointDef] = []
@export var flank_loops: Array[FlankLoopDef] = []


func hardpoint(hp_id: StringName) -> HardpointDef:
	for h in hardpoints:
		if h.id == hp_id:
			return h
	return null
