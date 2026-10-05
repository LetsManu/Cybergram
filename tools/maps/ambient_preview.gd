extends Node3D
## W18-LIFE evidence scene: Shardline Front with its ambient life, seen from a
## named camera. Used with tools/ci/capture_scene.sh, e.g.
##   tools/ci/capture_scene.sh res://tools/maps/ambient_preview.tscn out.png 40 \
##     --ambient-cam skyline --ambient-time night
## Cameras: skyline, market, train, lane, wide. Ambient debug args: see
## AmbientWorld.parse_debug_args().

const MAP := "res://assets/maps/front/shardline_front.tscn"
## name -> [eye, look-at] (world space, z = -L).
const CAMS := {
	"skyline": [Vector3(-88.0, 7.0, -150.0), Vector3(-260.0, 45.0, -260.0)],
	"market": [Vector3(0.0, 2.2, -70.0), Vector3(0.0, 4.5, -170.0)],
	"train": [Vector3(-90.0, 6.0, -100.0), Vector3(-130.0, 58.0, -170.0)],
	"lane": [Vector3(-80.0, 2.0, -104.0), Vector3(-80.0, 2.0, -200.0)],
	"wide": [Vector3(110.0, 26.0, 20.0), Vector3(-60.0, 10.0, -220.0)],
}


func _ready() -> void:
	HudStrings.ensure_loaded()  # the HUD would load the string table in a match
	var map: Node3D = (load(MAP) as PackedScene).instantiate()
	add_child(map)
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 1500.0
	add_child(cam)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--ambient-cam")
	var key := args[i + 1] if i >= 0 and i + 1 < args.size() else "skyline"
	var c: Array = CAMS.get(key, CAMS["skyline"])
	cam.look_at_from_position(c[0], c[1])
	cam.current = true
