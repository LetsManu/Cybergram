extends SceneTree
## Placement report for the shipped map (docs/placement.md): every world prop
## and floor decal checked by PlacementValidator against the map's collision.
## Exit 1 when a violation has no waiver.
##   godot --headless --path . -s res://tools/validate_placement.gd [-- --out reports/placement.txt]

const MAP_DEF := "res://assets/data/match/map_front.tres"


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ""
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out = args[i + 1]
	var md := load(MAP_DEF) as MapDef
	var map := md.scene.instantiate() as Node3D
	root.add_child(map)
	await physics_frame
	await physics_frame
	var space := map.get_world_3d().direct_space_state
	var res := MapPlacementAudit.run(md, space, func(p: Vector3) -> Dictionary: return WorldDecals.physics_ground(space, p))
	var text := PlacementValidator.format(res[1], (res[0] as Array).size())
	print(text)
	if out != "":
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(text + "\n")
	quit(1 if PlacementValidator.unwaived(res[1]) > 0 else 0)
