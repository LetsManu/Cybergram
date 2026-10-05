# Ambient anchors and living-map data (W18-GEO)

Static map data written by `tools/maps/build_shardline_front.gd` for
Shardline Front. Nothing here is simulated on the server or replicated; no
protocol change. Consumers: W18-LIFE background life
(`src/gameplay/views/ambient/`, contract in its `docs/architecture/ambient-world.md`),
the lane minimap, the overview render, tests.

## 1. Scene anchors (the W18-LIFE contract)

All under the map scene's `AmbientAnchors` node, each also in the group:

| Name prefix | Group | Node | Notes |
|---|---|---|---|
| `Billboard_*` | `ambient_billboard` | Node3D | Panel centre, panel faces +Z. Meta `size` (Vector2, m). |
| `Neon_*` | `ambient_neon` | Node3D | Sign mount, faces +Z. Meta `size`. |
| `ShopSign_*` | `ambient_shop_sign` | Node3D | Market shop sign slots, faces +Z (toward the Center lane). Meta `size`. Replaces W18-LIFE's fallback signs at x ±9.6. |
| `SteamVent_*` | `ambient_steam_vent` | Node3D | Jungle alley floor vents; +Z = emit direction (up-ish). Not in the W18-LIFE contract yet: a new kind it may adopt. |
| `TrafficPath0..3` | `ambient_traffic_path` | Path3D | Closed loops, one lane each. |
| `DronePath0..1` | `ambient_drone_path` | Path3D | Closed loops over the outer city rows. |
| `SkyTrain` | `ambient_skytrain` | Path3D | Open track (first one is used). |

Transforms are world space (the map root is at the origin). Mount basis:
+Z = outward face normal (toward the viewer), +Y = up, +X = the sign's right.

**Placement rules.** Every route stays outside the W18-LIFE playable box
(|x| <= 100) and to the *sides* of the map (traffic at |x| 156..208, drones at
|x| 116..128 and 36 m up, sky-train at x ~ -146 and 44 m up). None runs over a
lane, so night traffic trails never cross a line of sight down a lane and
cannot be read as tracers. Mounts sit on building faces, never on a floor.

## 2. `AmbientAnchorsDef` (`assets/data/match/ambient_front.tres`)

The same data as a resource on `MapDef.ambient_anchors`, for code that should
not walk the scene: parallel arrays per mount kind (`*_ids`, `*_xforms`,
`*_sizes`), `traffic_path_ids` / `traffic_paths` (closed polylines),
`sky_train_route`, and `crane_booms` (node paths, relative to the map root, of
the dock cranes' `Boom` pivots for a presentation chunk to rotate; yaw 0 = as
built). Class: `src/gameplay/data/ambient_anchors_def.gd`.

## 3. Jungle data on `MapDef`

- `jungle_paths: Array[PackedVector3Array]`: centrelines of the between-lane
  routes (low alleys and the rooftop routes), 6 per quadrant. Minimap, overview.
- `jungle_pockets: Array[JunglePocketDef]`: courtyards that may host neutral
  camps later (`id`, floor `center`, `size`). None is built now.
- `JUNGLE_NAV_LAYER = 2`: the jungle is its own `NavigationRegion3D`
  (`NavRegionJungle`, `shardline_front_navmesh_jungle.res`) joined to the lane
  navmesh by `NavigationLink3D`s at each mouth (`NavLinks/`), all on layer 2.
  `map_get_path` defaults to layer 1, so Wardling paths never enter it; bots
  path on `BotNavigator.NAV_LAYERS` (1 | 2).

## 4. Building markers

`Buildings/<House>_<A|B>/` holds Marker3D nodes per enterable building:
`Interior<n>` (room floor points), `Door<n>` / `InnerDoor` / `Window<n>` with
meta `width`, `height`, `wall`, `axis`, `floor_y`; the building node has meta
`floor_y` / `ceiling_y`. Tests read them.
