class_name CellCradleAnchor
extends Marker3D
## Placement anchor for a Mana Cell Cradle (match-flow-and-map.md §3.4 Plant 1,
## E14): where `team` takes Cells for the Plant hardpoint `hardpoint_id`. It sits
## at the adjacent hardpoint toward that team's HQ (its HQ lane gate when the
## Plant node is the team's own Inner). Mirrors HardpointDef.cell_cradles.

## The Plant hardpoint the Cells are for.
@export var hardpoint_id: StringName
## The attacking team that uses this Cradle (MapDef.TEAM_*).
@export var team: int = 0
