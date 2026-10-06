class_name SceneAudit
extends RefCounted
## Scene validator checks that the map tests do not already cover
## (docs/placement.md "Scene validator"): every mesh surface has a material,
## every walkable navmesh polygon lies on real collision, and every world
## geometry instance under a dressing node is range-culled (visibility range =
## its LOD). Each returns a list of problems ("" lines); empty = pass. Pure apart
## from the physics rays on `space`.

## Mesh surfaces without any material (they render the engine's default grey).
static func missing_materials(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.visible:
			continue
		for s in mi.mesh.get_surface_count():
			if mi.get_active_material(s) == null:
				out.append("%s surface %d has no material" % [root.get_path_to(mi), s])
	return out


## Navmesh polygons whose centre has no collision within `tol` m below it
## (agents would walk on air). Checks every polygon of `nm`.
static func navmesh_off_collision(nm: NavigationMesh, space: PhysicsDirectSpaceState3D, tol: float = 0.8) -> PackedStringArray:
	var out := PackedStringArray()
	var verts := nm.get_vertices()
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var c := Vector3.ZERO
		for k in poly:
			c += verts[k]
		c /= float(poly.size())
		var h := PlacementKit.ray(space, c + Vector3.UP * 0.3, c - Vector3.UP * tol)
		if h.is_empty():
			out.append("navmesh polygon %d at %s has no floor under it" % [i, c.snapped(Vector3.ONE * 0.1)])
	return out


## Geometry instances under `root` with no visibility range (never culled by
## distance: no LOD).
static func unculled(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for gi: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if gi.visibility_range_end <= 0.0:
			out.append("%s has no visibility range" % root.get_path_to(gi))
	return out
