class_name HardpointDef
extends Resource
## One task hardpoint on a lane (match-flow-and-map.md §3.3, §3.7; architecture.md §6 MapDef).
## Static layout data only: capture state and rules live in E7 objective sims.
## Positions are world metres in the map scene (see MapDef for the axis convention).

enum TaskKind { HOLD, PLANT, BREACH }
## Lane row: own Inner/Outer per half, or the shared Mid (Incursion depth, F8).
enum Tier { INNER, OUTER, MID }

## Stable id (also the HardpointAnchor.hardpoint_id in the map scene), e.g. &"s_ai".
@export var id: StringName
@export var display_name: String = ""
@export var task: TaskKind = TaskKind.HOLD
@export var tier: Tier = Tier.MID
## Index along the lane, 0 = nearest Concord HQ.
@export var lane_index: int = 0
## Owner at match start: MapDef.TEAM_CONCORD, MapDef.TEAM_SYNDICATE or MapDef.TEAM_NEUTRAL.
@export var initial_owner: int = -1
## Zone centre on the floor (Hold: pillar; Plant: Socket; Breach: Generator).
@export var position: Vector3
## Zone cylinder (§3.2: Hold r 12, Breach r 12, Plant r 10, all 6 m tall).
@export var zone_radius: float = 12.0
@export var zone_height: float = 6.0
## Hold / Plant base duration, or the Breach phase-2 Hold (§3.3, §3.7).
@export var base_duration_s: float = 60.0
## Breach phase-1 Generator HP before D_s (0 for non-Breach).
@export var generator_hp: float = 0.0
## Barricade sockets, 15 m outside the zone edge on the main path:
## [0] = the side toward the Concord HQ, [1] = the side toward the Syndicate HQ.
@export var barricade_sockets: PackedVector3Array = PackedVector3Array()
