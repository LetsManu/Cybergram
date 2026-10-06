extends SceneTree
## Look-dev frames for the Wardling v2 rig (docs/assets/wardling.md): Vesper for
## scale plus Concord / Syndicate Wardlings in idle, walk, run and shoot, on the
## Shardline Front Mid plaza, from the front, three-quarter and side.
## Needs render path 2b (xvfb + lavapipe), see docs/visual-verification.md:
##   xvfb-run -a -s "-screen 0 1600x900x24" $GODOT --path . --resolution 1600x900 \
##     -s res://tools/art/render_wardling.gd -- --out production/qa/evidence/<dir>

const MAP_DEF := "res://assets/data/match/map_front.tres"

var _out := "production/qa/evidence/wardling-v2"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]
	if DisplayServer.get_name() == "headless":
		push_error("[wardling] NOT ASSESSED: headless renders no pixels")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var md := load(MAP_DEF) as MapDef
	var map: Node3D = md.scene.instantiate()
	root.add_child(map)
	var hp: Vector3 = md.lanes[1].hardpoints[2].position + Vector3(0, 0, 14)
	var cam := Camera3D.new()
	cam.fov = 60.0
	map.add_child(cam)
	cam.current = true
	var v := HeroModelLoader.build(&"vesper", ModelPalette.TEAM_CONCORD)
	map.add_child(v)
	v.global_position = hp + Vector3(-2.2, 0, 0)
	v.rotation.y = 0.0
	var rows := [["idle", Vector3.ZERO], ["walk", Vector3(0, 0, -1.4)], ["run", Vector3(0, 0, -4.5)], ["shoot", Vector3.ZERO]]
	var ws: Array = []
	for i in rows.size():
		for t in 2:
			var key: StringName = &"wardling_c" if t == 0 else &"wardling_s"
			var m := HeroModelLoader.build(key, t)
			map.add_child(m)
			m.global_position = hp + Vector3(-0.6 + i * 1.2, 0, 1.5 * t)
			ws.append([m, rows[i]])
	for f in 40:
		for e in ws:
			var m: HeroModel = e[0]
			var vel: Vector3 = e[1][1]
			# HeroModel faces -Z; the velocity is world space.
			m.set_motion(vel, false, 0.0)
			if e[1][0] == "shoot" and f % 10 == 0:
				m.call("play_shoot")
		v.set_motion(Vector3.ZERO, false, 0.0)
		await process_frame
	var views := {"front": Vector3(0, 0.9, -4.6), "three-quarter": Vector3(3.2, 1.3, -3.6), "side": Vector3(5.2, 0.8, 0.8),
		"close": Vector3(-0.2, 0.8, -2.2)}
	var n := 0
	for name: String in views:
		var focus := hp + (Vector3(-0.6, 0.55, 0.0) if name == "close" else Vector3(1.0, 0.55, 0.8))
		cam.global_position = focus + views[name] - Vector3(0, 0.55, 0)
		cam.look_at(focus)
		for f in 6:
			for e in ws:
				(e[0] as HeroModel).set_motion(e[1][1], false, 0.0)
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/wardling-%s.png" % [_out, name])
		n += 1
	print("[wardling] %d frames -> %s" % [n, _out])
	quit(0)
