class_name WorldModel
extends RefCounted
## World assets built on the hero pipeline (tools/art/world/, docs/model-pipeline.md):
## a glb under assets/models/world/<key>/ with one mesh node per piece and the
## heroes' texture contract (<key>_albedo / _normal / _mask.png). They use the
## heroes' toon material (spatial_char_toon_rigged + ink hull, RiggedHeroModel),
## so the world and the heroes share one look.
##
## Example:
##   var inst := WorldModel.instantiate(&"uplink", team)   # null when not built
##   var ring := WorldModel.piece(inst, &"ring_0")

const ROOT := "res://assets/models/world/%s/%s"

static var _materials: Dictionary = {}


## Path of the asset's glb.
static func glb_path(key: StringName) -> String:
	return (ROOT % [key, key]) + ".glb"


static func exists(key: StringName) -> bool:
	return ResourceLoader.exists(glb_path(key))


## The asset's scene with the team's toon material on every mesh, or null.
static func instantiate(key: StringName, team: int) -> Node3D:
	if not exists(key):
		return null
	var inst := (load(glb_path(key)) as PackedScene).instantiate() as Node3D
	var mat := material(key, team)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	return inst


## One shared material per (asset, team): the hero toon shader with the asset's
## baked maps and the ink hull; flat colours when the maps are missing.
static func material(key: StringName, team: int) -> ShaderMaterial:
	var k := "%s|%d" % [key, team]
	if _materials.has(k):
		return _materials[k]
	var m := RiggedHeroModel.material(team).duplicate() as ShaderMaterial
	m.next_pass = RiggedHeroModel.hull_material(team)
	RiggedHeroModel.bind_maps_from(m, (ROOT % [key, key]) + "_")
	_materials[k] = m
	return m


## The mesh node of piece `name` (the export splits pieces into mesh nodes).
static func piece(inst: Node, name: StringName) -> MeshInstance3D:
	if inst == null:
		return null
	return inst.find_child(String(name), true, false) as MeshInstance3D
