class_name AppConfig
extends Resource
## Boot wiring as data (assets/data/app/app_config.tres). Keeps src/core free of
## references to higher layers: the session and overlay scenes are named here.

## Scene instantiated as the session (receives `launch_config`).
@export var session_scene: PackedScene
## Debug overlays added in non-headless runs (each receives `session`).
@export var overlay_scenes: Array[PackedScene] = []
