class_name ModelBlueprint
extends RefCounted
## Build-time context shared by the hero / weapon / Wardling builders: a list
## of pivots, one PartBuilder per (pivot, material descriptor) and named
## markers. finish() commits every builder to a shared ArrayMesh, so a
## blueprint is built once per model key and instanced many times.

var key: StringName
var pivots: Array = []  # {name, parent, pos, rot, anim}
var markers: Dictionary = {}  # name -> [pivot, pos]
var data: Dictionary = {}  # recipe-specific values (heights, IK lengths...)
var _builders: Dictionary = {}  # "pivot|mat" -> PartBuilder


func _init(key_: StringName) -> void:
	key = key_


## Adds a pivot. `anim` = [kind, speed, amount] for HeroModel/WeaponModel extras.
func pivot(pivot_name: StringName, parent: StringName, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO,
		anim: Array = []) -> void:
	var p := {"name": pivot_name, "parent": parent, "pos": pos, "rot": rot_deg * (PI / 180.0)}
	if not anim.is_empty():
		p["anim"] = anim
	pivots.append(p)


## The PartBuilder of `pivot_name` for material descriptor `mat`.
func at(pivot_name: StringName, mat: String = "toon") -> PartBuilder:
	var k := "%s|%s" % [pivot_name, mat]
	if not _builders.has(k):
		var b := PartBuilder.new()
		b.keep_uv = mat == "holo_panel"
		_builders[k] = b
	return _builders[k]


func marker(marker_name: StringName, pivot_name: StringName, pos: Vector3) -> void:
	markers[marker_name] = [pivot_name, pos]


func finish() -> Dictionary:
	var meshes := {}
	var tris := 0
	for k in _builders:
		var b: PartBuilder = _builders[k]
		if b.is_empty():
			continue
		tris += b.triangle_count()
		meshes[k] = b.commit()
	var out := data.duplicate()
	out["key"] = key
	out["pivots"] = pivots
	out["markers"] = markers
	out["meshes"] = meshes
	out["tris"] = tris
	return out
