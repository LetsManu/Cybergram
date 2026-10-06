class_name GarrisonSocketView
extends Node3D
## One Garrison socket of a hardpoint (docs/assets/garrison.md; art bible §6.4;
## wardlings-and-economy.md §11). Presentation only: ClientWorld tells it the
## hardpoint owner and whether that owner's Sentinel stands on it.
##
## Stages (stage_of, pure):
##   OFF       nobody holds the hardpoint: ring dark
##   WAITING   held, no Sentinel here (settling or respawning): ring dim
##   MANNED    held, its Sentinel stands on it: ring lit

enum Stage { OFF, WAITING, MANNED }

const KEY: StringName = &"garrison_socket"
## A Sentinel this close (m, flat) to the socket counts as standing on it.
const MANNED_M: float = 1.5

var stage: int = Stage.OFF
var team: int = MapDef.TEAM_NEUTRAL
var _model: Node3D


static func stage_of(owner: int, manned: bool) -> int:
	if owner == MapDef.TEAM_NEUTRAL:
		return Stage.OFF
	return Stage.MANNED if manned else Stage.WAITING


static func available() -> bool:
	return WorldModel.exists(KEY)


func setup(index: int) -> void:
	name = "GarrisonSocket%d" % index
	_model = WorldModel.instantiate(KEY, MapDef.TEAM_CONCORD)
	_model.name = "Model"
	add_child(_model)
	_show(Stage.OFF, MapDef.TEAM_NEUTRAL)


## Returns true when the stage or team changed. A Sentinel taking its post
## plays `garrison_post` through `sfx` (ClientWorld's AudioEventPlayer, if any).
func apply(owner: int, manned: bool, sfx: Object = null) -> bool:
	var s := stage_of(owner, manned)
	if s == stage and owner == team:
		return false
	if s == Stage.MANNED and stage == Stage.WAITING and sfx != null and is_inside_tree():
		sfx.call("play", &"garrison_post", AudioEventDef.OwnerFilter.ANY, global_position + Vector3(0, 0.5, 0))
	_show(s, owner)
	return true


func piece(n: StringName) -> MeshInstance3D:
	return WorldModel.piece(_model, n)


static var _dim: Dictionary = {}


## The team material with the emission turned down (a waiting socket).
static func dim_material(t: int) -> ShaderMaterial:
	if not _dim.has(t):
		var m := WorldModel.material(KEY, t).duplicate() as ShaderMaterial
		var e: Variant = m.get_shader_parameter("emission_energy")
		m.set_shader_parameter("emission_energy", (float(e) if e != null else 1.0) * 0.25)
		_dim[t] = m
	return _dim[t]


func _show(s: int, owner: int) -> void:
	stage = s
	team = owner
	var base := WardGeneratorView.dead_material_of(KEY, MapDef.TEAM_CONCORD) if s == Stage.OFF \
		else WorldModel.material(KEY, owner)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = base
	var ring := piece(&"ring")
	if ring != null:
		ring.visible = s != Stage.OFF
		if s == Stage.WAITING:
			ring.material_override = dim_material(owner)
