class_name MatchRulesDef
extends Resource
## Match rule coefficients (architecture.md §6 MatchRulesDef, abridged to what
## E4 uses). The formula lives in RespawnSystem; the numbers live here.

## design/gdd/match-flow-and-map.md F7 (Canon C11): R = min(cap, base + per_min * minutes).
@export_range(0.0, 60.0, 0.1) var respawn_base_s: float = 6.0
@export_range(0.0, 5.0, 0.01) var respawn_per_min_s: float = 0.4
@export_range(0.0, 120.0, 0.1) var respawn_cap_s: float = 30.0
