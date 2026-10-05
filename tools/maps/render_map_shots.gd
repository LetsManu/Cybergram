extends SceneTree
## QA evidence renderer for Shardline Front (W14-M2): the labelled top-down
## overview plus first-person-height shots of each lane, a flank tunnel and the
## Mid Plaza. Needs a display (xvfb):
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 \
##     -s res://tools/maps/render_map_shots.gd -- production/qa/evidence/w14-map

const OVERVIEW := "res://assets/maps/front/shardline_front_overview.tscn"
const MAP := "res://assets/maps/front/shardline_front.tscn"

## [file, eye (x, L, y), look-at (x, L, y)] in GDD lane coordinates (z = -L).
const SHOTS := [
	["lane-north-bridge", Vector3(-80, 104, 1.7), Vector3(-80, 200, 1.0)],
	["lane-center-market", Vector3(-3, 112, 1.7), Vector3(0, 160, 1.0)],
	["lane-south-dock", Vector3(83, 108, 1.7), Vector3(80, 160, 1.0)],
	["lane-north-inner-deck", Vector3(-92, 84, 4.8), Vector3(-75, 140, 0.5)],
	["flank-undercroft", Vector3(-63, 148, 1.7), Vector3(-40, 178, -3.0)],
	["flank-junction", Vector3(-45, 172, -2.3), Vector3(-30, 186, -3.0)],
	["mid-plaza", Vector3(-4, 182, 2.2), Vector3(0, 210, 1.0)],
	["mid-plaza-spokes", Vector3(-24, 214, 3.0), Vector3(-80, 210, 1.0)],
	["hq-gates", Vector3(0, 12, 2.0), Vector3(0, 60, 1.0)],
	# W18-GEO living map: level changes, enterable buildings, the jungle.
	["market-sunken-street", Vector3(0, 103, -1.8), Vector3(0, 126, -3.0)],
	["market-terraces", Vector3(11, 102.5, 4.2), Vector3(-2, 126, -1.0)],
	["market-shop-exterior", Vector3(1, 106, 1.7), Vector3(14, 116, 3.6)],
	["market-shop-interior", Vector3(21.8, 120, 4.2), Vector3(14.5, 111, 3.4)],
	["bridge-span-towers", Vector3(-78, 150, 1.7), Vector3(-80, 192, 4.0)],
	["bridge-service-walkway", Vector3(-93, 172.5, -2.8), Vector3(-84, 182, -4.0)],
	["bridge-guardhouse-exterior", Vector3(-83, 129, 1.7), Vector3(-99, 142, 2.0)],
	["bridge-guardhouse-interior", Vector3(-101.6, 150, 1.7), Vector3(-96, 135, 1.2)],
	["dock-quay", Vector3(100, 127, 4.2), Vector3(88, 152, 0.5)],
	["dock-warehouse-exterior", Vector3(79, 96, 1.7), Vector3(92, 110, 2.0)],
	["dock-warehouse-interior", Vector3(99, 116, 1.7), Vector3(89, 102.5, 1.2)],
	["plaza-bridge", Vector3(-6, 191, 1.7), Vector3(-30, 210, 4.0)],
	["jungle-alley", Vector3(15.5, 77.5, 1.7), Vector3(36, 76, 1.2)],
	["jungle-rooftop-route", Vector3(18, 83, 6.2), Vector3(55, 89, 4.0)],
	["jungle-pocket-courtyard", Vector3(34, 92, 1.9), Vector3(46, 80, 0.5)],
	["jungle-catwalk-undercroft", Vector3(42, 137, 1.7), Vector3(42, 172, -3.5)],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "production/qa/evidence/w14-map"
	DirAccess.make_dir_recursive_absolute(out)
	var ov: Node = (load(OVERVIEW) as PackedScene).instantiate()
	root.add_child(ov)
	await _settle()
	_save(out + "/overview-topdown.png")
	ov.queue_free()
	await process_frame
	var map: Node3D = (load(MAP) as PackedScene).instantiate()
	root.add_child(map)
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 1500.0
	map.add_child(cam)
	cam.current = true
	for s in SHOTS:
		var e: Vector3 = s[1]
		var t: Vector3 = s[2]
		cam.global_position = Vector3(e.x, e.z, -e.y)
		cam.look_at(Vector3(t.x, t.z, -t.y))
		await _settle()
		_save("%s/%s.png" % [out, s[0]])
	quit()


func _settle() -> void:
	for i in 12:
		await process_frame


func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path)
