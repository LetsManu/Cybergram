class_name WorldDecalsDef
extends Resource
## Look and placement constants for the painted floor and the world decals
## (WorldDecals, docs/assets/floor.md; design/art-bible.md §6.2 lit floor arrows,
## §10.6 "Environment Decal nodes <= 48 visible in any lane view").
## Data only: WorldDecals reads it, tests build their own copies.

@export_group("Atlas")
## Painted decal atlas (tools/art/world/floor_kit.py --decals), imported as an Image.
@export_file("*.png") var atlas_path: String = "res://assets/textures/world/decals/world_decals_albedo.png"
## Cell names in atlas order (row-major), = floor_kit.DECALS.
@export var cells: PackedStringArray = PackedStringArray([
	"arrow", "arrow_double", "chevrons", "glyph_concord", "glyph_syndicate", "tag_a", "tag_b", "tag_c",
	"crack_a", "crack_b", "crack_c", "grime_a", "grime_b", "oil", "puddle", "scorch"])
@export var atlas_columns: int = 8
@export var cell_px: int = 256
## Injected atlas (tests, tools); null = load atlas_path. Not saved.
var atlas_override: Image

@export_group("Floor tiles")
## Painted floor trim sheet (tools/art/world/floor_kit.py), installed as the
## default textures of spatial_env_panel.gdshader. Empty = keep the flat v1 floor.
@export_file("*.png") var floor_albedo_path: String = "res://assets/textures/world/floor/floor_tiles_albedo.png"
@export_file("*.png") var floor_normal_path: String = "res://assets/textures/world/floor/floor_tiles_normal.png"
@export_file("*.png") var floor_mask_path: String = "res://assets/textures/world/floor/floor_tiles_mask.png"
## Height map for the shader's parallax occlusion (empty = flat tiles, no parallax).
@export_file("*.png") var floor_height_path: String = "res://assets/textures/world/floor/floor_tiles_height.png"

@export_group("Budget")
## Hard cap: no camera position sees more decals than this (art bible §10.6).
@export var max_visible: int = 48
## Every decal fades out between fade_begin and fade_begin + fade_length metres
## from the camera; beyond that it is not drawn. The cap counts decals inside
## that radius (horizontal distance, which is <= the 3D distance the engine uses).
@export var fade_begin: float = 22.0
@export var fade_length: float = 8.0
## Spacing of the cap's check grid (m). The check radius grows by half its diagonal.
@export var cap_grid_m: float = 4.0
## Deterministic placement seed.
@export var placement_seed: int = 7

@export_group("Arrows")
## Lane arrows along the lane path (HQ gate -> hardpoints -> enemy HQ gate),
## pointing toward the enemy side in each team's half. White, Accent tier.
@export var arrow_spacing_m: float = 16.0
@export var arrow_size_m: float = 2.4
## Every n-th lane arrow is the double chevron.
@export var arrow_double_every: int = 3
## Emission energy of arrows and HQ glyphs (Accent tier, design §4.6: 0.4-1.0, no bloom).
@export var arrow_emission: float = 0.6
## Flank loop arrows (design §6.2: lit floor arrows toward the lane they join).
@export var flank_arrow_spacing_m: float = 8.0
@export var flank_arrow_size_m: float = 1.8
## Arrows keep this margin outside hardpoint capture zones and the Mid plaza.
@export var arrow_zone_margin_m: float = 2.0
## Distance down the lane axis from an HQ gate before the path turns to the lane.
@export var approach_turn_m: float = 24.0

@export_group("HQ")
@export var glyph_size_m: float = 6.0
@export var glyph_emission: float = 0.8
## Glyph position between the Sanctum (0) and the Uplink (1).
@export var glyph_t: float = 0.5
@export var concord_color: Color = Color("#2E86FF")
@export var syndicate_color: Color = Color("#FF5A1F")
## Hazard chevrons inside each HQ lane gate, pointing out to the lane.
@export var chevron_size_m: float = 3.0
@export var chevron_inset_m: float = 4.0

@export_group("Wear")
## Cracks / scorch / oil around hardpoints (annulus from wear_r0 to zone radius + margin).
@export var hardpoint_cracks: int = 3
@export var hardpoint_scorch: int = 1
@export var hardpoint_oil: int = 1
@export var wear_r0_m: float = 5.0
@export var wear_size_m: Vector2 = Vector2(1.6, 3.2)
## Grime along the lane edges.
@export var grime_spacing_m: float = 9.0
@export var grime_chance: float = 0.75
@export var lane_edge_offset_m: float = 6.5
@export var grime_size_m: Vector2 = Vector2(2.2, 3.6)
## Crew tags (graffiti) near the lane edges.
@export var tag_spacing_m: float = 34.0
@export var tag_size_m: float = 2.2
## Puddles and oil stains on the lane.
@export var puddle_spacing_m: float = 26.0
@export var puddle_chance: float = 0.5
@export var puddle_size_m: Vector2 = Vector2(1.8, 3.0)

@export_group("Projection")
## Decal box height (m); aligned to the floor normal, so slopes stay covered.
@export var box_height_m: float = 1.0
## Fades the projection on faces steeper than the floor (no smears up walls).
@export var normal_fade: float = 0.5


## Atlas cell index of `cell_name`, or -1.
func cell_index(cell_name: String) -> int:
	return cells.find(cell_name)


## Pixel rect of `cell_name` in the atlas (empty Rect2i if unknown).
func cell_rect(cell_name: String) -> Rect2i:
	var i := cell_index(cell_name)
	if i < 0:
		return Rect2i()
	return Rect2i((i % atlas_columns) * cell_px, (i / atlas_columns) * cell_px, cell_px, cell_px)


## Distance (m) beyond which a decal is not drawn.
func visible_radius() -> float:
	return fade_begin + fade_length
