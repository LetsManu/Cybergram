class_name WorldPropsDef
extends Resource
## Placement rules for the world prop kit (WorldProps, docs/assets/props.md;
## art bible §6.1-6.2 lane dressing, §4.6 neon caps, §10.6 budgets).
##
## Props are visual only (no collision). The walk guarantee lives in these
## numbers: a prop stands only with its back on a vertical collision face
## (`wall_search_m`), its floor footprint no deeper than `max_wall_depth_m`
## from that face, with the face continuous along its whole width (no door
## openings), on a flat floor, in a volume free of any collision, outside every
## exclusion zone and the lane corridors; or on a roof at `roof_min_y` and up,
## above every floor a hero can stand on.

## The asset key of the kit (WorldModel: assets/models/world/<key>/<key>.glb).
@export var model_key: StringName = &"world_props"
## MapDef.id this placement is made for (its navmesh); other maps get no props.
@export var map_id: StringName = &"map_front"
## The walkable navmesh whose border is walked to find walls (the map's NavRegion mesh).
@export var navmesh: NavigationMesh
## Seed of every random choice; same seed + same map = same placement.
@export var placement_seed: int = 7301

@export_group("Wall props")
## Spacing of the candidate points along the navmesh border (m).
@export var edge_step_m: float = 2.0
## How far from the navmesh border a wall must be (ray length, m).
@export var wall_search_m: float = 1.6
## Floor-footprint depth limit measured from the wall face (m): the walk rule.
@export var max_wall_depth_m: float = 1.2
## Space left between the wall face and the prop's back (m).
@export var wall_gap_m: float = 0.04
## Maximum floor height spread under a footprint (m).
@export var max_floor_spread_m: float = 0.12
## Minimum distance between two prop centres (m).
@export var min_spacing_m: float = 3.5
## Chance that an accepted wall spot gets a prop, per zone (density).
@export var density: Dictionary = {&"lane": 0.32, &"plaza": 0.45, &"hq": 0.6, &"flank": 0.35}
## Piece weights per zone: {zone: {piece: weight}}. Zones: lane, plaza, hq, flank, roof.
@export var weights: Dictionary = {}
## Floor footprint (width along the wall, depth from the wall) of pieces whose
## mesh overhangs above head height (lamp arm, sign board): {piece: Vector2}.
## Pieces not listed use their mesh bounds.
@export var foot_override: Dictionary = {}
## Pieces fixed to a wall (cables, pipes, AC units): the wall must reach their top.
@export var wall_mounted: Array[StringName] = []
## Pieces that carry team colour: placed only in HQ courtyards, with the HQ team's material.
@export var team_pieces: Array[StringName] = []

@export_group("Roof props")
## Roofs: grid spacing of the downward probe rays (m).
@export var roof_step_m: float = 7.0
## Lowest roof that gets props (m). Above every walkable floor + a jump.
@export var roof_min_y: float = 7.0
## Every walkable navmesh of the map (main + jungle): a roof point that lies on
## one of their polygons (within 1.5 m in height) is walkable, so no roof prop.
@export var walk_navmeshes: Array[NavigationMesh] = []
## Chance that a roof probe point gets a prop.
@export var roof_density: float = 0.35

@export_group("Zones")
## HQ compound half width around the Sanctum's x (m); the compound runs from
## the back wall to the lane gate line.
@export var hq_half_width_m: float = 30.0
## Distance from a hardpoint zone edge that still counts as its plaza rim (m).
@export var plaza_rim_m: float = 14.0
## Distance from a flank loop centreline that counts as flank path (m).
@export var flank_band_m: float = 5.0

@export_group("Render")
## Spatial chunk size of the MultiMesh batches (m): frustum and range culling per chunk.
@export var chunk_m: float = 40.0
## Visibility range end of small (< 1.5 m tall) and tall pieces (m).
@export var range_small_m: float = 80.0
@export var range_tall_m: float = 220.0

@export_group("Keep-out")
## Margin added to every hardpoint zone_radius (m).
@export var hardpoint_margin_m: float = 3.0
## Armory pad radius (owner: 7 m) + margin.
@export var armory_radius_m: float = 7.0
## Radius around each spawn point, the Sanctum ring adds sanctum_radius.
@export var spawn_radius_m: float = 3.0
@export var sanctum_margin_m: float = 2.0
## Around Uplinks, Foundries, lane gates (m).
@export var uplink_radius_m: float = 9.0
@export var foundry_radius_m: float = 6.0
@export var gate_radius_m: float = 9.0
## Around flank side doors, Barricade sockets, Cell Cradles, Supply Caches,
## Garrison posts (m).
@export var door_radius_m: float = 5.0
@export var socket_radius_m: float = 7.0
@export var cradle_radius_m: float = 4.0
## Lane corridor: half width around each lane's polyline (HQ A gate ->
## hardpoints -> HQ B gate). No floor footprint inside it.
@export var corridor_half_width_m: float = 4.0

@export_group("Budget")
## Hard cap on placed props (all kinds).
@export var max_props: int = 900
