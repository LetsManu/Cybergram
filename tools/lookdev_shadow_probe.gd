extends SceneTree
## Look-dev diagnostics: which shadow casters darken the floor in a shot.gd view.
## Samples floor points in front of the preset camera, marches each toward the
## sun and counts the shadow-casting GeometryInstance3D bounds it crosses.
##   xvfb-run -a $GODOT --path . -s res://tools/lookdev_shadow_probe.gd -- --view fp-lane-center [--look b]

const MAP_DEF := "res://assets/data/match/map_front.tres"
const SHOT := preload("res://tools/shot.gd")


func _initialize() -> void:
	var view := "fp-lane-center"
	var a := OS.get_cmdline_user_args()
	for i in a.size() - 1:
		if a[i] == "--view":
			view = a[i + 1]
	_run.call_deferred(view)


func _run(view: String) -> void:
	var md := load(MAP_DEF) as MapDef
	var map: Node3D = md.scene.instantiate()
	root.add_child(map)
	map.add_child(WorldDecals.create(md))
	WorldProps.spawn(map, md)
	CoverDressing.spawn(map)
	for k in 10:
		await process_frame
	var shot: Array = []
	for s in SHOT.presets(md):
		if s[0] == view:
			shot = s
	var sun := map.get_node("Sun") as DirectionalLight3D
	var to_sun := sun.global_transform.basis.z.normalized()
	var eye: Vector3 = shot[1]
	var fwd: Vector3 = ((shot[2] as Vector3) - eye) * Vector3(1, 0, 1)
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var space := map.get_world_3d().direct_space_state
	var casters: Array[GeometryInstance3D] = []
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and g.is_visible_in_tree():
			casters.append(g)
	var hits := {}
	var pts := 0
	for dz in range(2, 30, 2):
		for dx in range(-8, 9, 2):
			var p0 := eye + fwd * dz + side * dx
			var q := PhysicsRayQueryParameters3D.create(p0 + Vector3.UP * 5.0, p0 + Vector3.DOWN * 20.0)
			var r := space.intersect_ray(q)
			if r.is_empty():
				continue
			pts += 1
			var p: Vector3 = r.position + Vector3.UP * 0.05
			for g in casters:
				var box := g.global_transform * g.get_aabb()
				if not box.intersects_segment(p, p + to_sun * 250.0):
					continue
				if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
					# exact: the triangles, not the bounds (the floor's own box contains p)
					var tm := _tri(g as MeshInstance3D)
					var inv := g.global_transform.affine_inverse()
					if tm == null or tm.intersect_segment(inv * (p + to_sun * 0.3), inv * (p + to_sun * 250.0)).is_empty():
						continue
					var key := "%s (%s)" % [g.get_path().get_concatenated_names().substr(0, 0), _label(g)]
					hits[key] = int(hits.get(key, 0)) + 1
	var keys := hits.keys()
	keys.sort_custom(func(x, y) -> bool: return hits[x] > hits[y])
	print("[probe] view %s, %d floor points, sun dir %s" % [view, pts, to_sun])
	for k in keys.slice(0, 25):
		print("[probe] %4d  %s" % [hits[k], k])
	quit()


var _tris := {}


func _tri(mi: MeshInstance3D) -> TriangleMesh:
	if not _tris.has(mi.mesh):
		_tris[mi.mesh] = mi.mesh.generate_triangle_mesh()
	return _tris[mi.mesh]


func _label(g: GeometryInstance3D) -> String:
	var p := g.get_parent()
	var pp := p.get_parent() if p != null else null
	var m := ""
	if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
		m = (g as MeshInstance3D).mesh.get_class()
	elif g is MultiMeshInstance3D:
		m = "MultiMesh"
	return "%s/%s/%s %s" % [pp.name if pp else "", p.name if p else "", g.name, m]
