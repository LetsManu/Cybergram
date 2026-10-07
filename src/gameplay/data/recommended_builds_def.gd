class_name RecommendedBuildsDef
extends Resource
## All recommended Armory builds, one or more per hero (data-driven; see
## assets/data/economy/recommended_builds_slice.tres).

const DEFAULT_PATH := "res://assets/data/economy/recommended_builds_slice.tres"

@export var builds: Array[RecommendedBuildDef] = []


## First build for `hero_id` (in `mode`, &"" = any), or null.
func for_hero(hero_id: StringName, mode: StringName = &"") -> RecommendedBuildDef:
	for b in builds:
		if b != null and b.hero_id == hero_id and b.allows_mode(mode):
			return b
	return null


## Every build for `hero_id` in `mode` (&"" = any), in data order.
func all_for_hero(hero_id: StringName, mode: StringName = &"") -> Array[RecommendedBuildDef]:
	var out: Array[RecommendedBuildDef] = []
	for b in builds:
		if b != null and b.hero_id == hero_id and b.allows_mode(mode):
			out.append(b)
	return out
