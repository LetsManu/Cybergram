class_name HeroModelLoader
extends RefCounted
## Picks a hero's 3P model: the rigged toon glb (RiggedHeroModel) when
## assets/models/heroes/<key>/<key>.glb exists, else the procedural box model
## (HeroModelBuilder). design/art/hero-art-bible.md. `-- --box-heroes` forces the
## procedural models for every hero (A/B and perf baselines).

const GLB_PATH := "res://assets/models/heroes/%s/%s.glb"

static var _scenes: Dictionary = {}
static var _forced_box: int = -1


static func glb_path(model_key: StringName) -> String:
	return GLB_PATH % [model_key, model_key]


## True when `model_key` has an imported rigged glb (and it is not disabled).
static func has_rigged(model_key: StringName) -> bool:
	if model_key == &"" or box_forced():
		return false
	return ResourceLoader.exists(glb_path(model_key))


static func box_forced() -> bool:
	if _forced_box < 0:
		_forced_box = 1 if OS.get_cmdline_user_args().has("--box-heroes") else 0
	return _forced_box == 1


## Test hook: force (1) / allow (0) / re-read (-1) the procedural fallback.
static func set_box_forced(v: int) -> void:
	_forced_box = v


## The model for `model_key`: rigged if available, else the procedural one.
static func build(model_key: StringName, team: int) -> HeroModel:
	if has_rigged(model_key):
		var scene := _scene(model_key)
		if scene != null:
			var m := RiggedHeroModel.new()
			m.build_from_scene(model_key, scene, team)
			return m
	return HeroModelBuilder.build(model_key, team)


static func _scene(model_key: StringName) -> PackedScene:
	if not _scenes.has(model_key):
		_scenes[model_key] = load(glb_path(model_key)) as PackedScene
	return _scenes[model_key]
