class_name RecommendedBuildsDef
extends Resource
## All recommended Armory builds, one or more per hero (data-driven; see
## assets/data/economy/recommended_builds_slice.tres).

const DEFAULT_PATH := "res://assets/data/economy/recommended_builds_slice.tres"

@export var builds: Array[RecommendedBuildDef] = []


## First build for `hero_id`, or null.
func for_hero(hero_id: StringName) -> RecommendedBuildDef:
	for b in builds:
		if b != null and b.hero_id == hero_id:
			return b
	return null
