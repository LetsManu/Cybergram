class_name WardlingView
extends Node3D
## Greybox Wardling (architecture.md §5.1 wardling_view, hud.md §4.6, art bible
## team palette): a small biped block tinted by team, a crystal eye showing
## facing, an owner sash (personal squads; brighter for your own squad), a
## pennant for ownerless Vanguard, and an HP bar. Presentation only.

const COLOR_CONCORD := Color("#2E86FF")
const COLOR_SYNDICATE := Color("#FF5A1F")
const SASH_OWN := Color(1.0, 0.86, 0.25)
const SASH_OTHER := Color(0.85, 0.85, 0.9)
const PENNANT := Color(0.96, 0.96, 1.0)
const _H: float = 1.2

var net_id: int = 0
var team: int = -1
var _body: MeshInstance3D
var _sash: MeshInstance3D
var _pennant: Node3D
var _hp_fill: MeshInstance3D
var _hp_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D


func _ready() -> void:
	_body_mat = _mat(Color.GRAY, false)
	_body = _box(Vector3(0.7, 0.9, 0.5), Vector3(0.0, 0.75, 0.0), _body_mat)
	_box(Vector3(0.2, 0.3, 0.2), Vector3(-0.18, 0.15, 0.0), _body_mat)
	_box(Vector3(0.2, 0.3, 0.2), Vector3(0.18, 0.15, 0.0), _body_mat)
	_box(Vector3(0.22, 0.14, 0.08), Vector3(0.0, 1.0, -0.27), _mat(Color(0.75, 1.0, 1.0), true))
	_sash = _box(Vector3(0.74, 0.12, 0.54), Vector3(0.0, 0.62, 0.0), _mat(SASH_OTHER, true))
	_sash.rotation.z = 0.5
	_pennant = Node3D.new()
	add_child(_pennant)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.2
	pole.mesh = cyl
	pole.position = Vector3(0.25, 1.6, 0.2)
	pole.material_override = _mat(Color(0.3, 0.3, 0.35), false)
	_pennant.add_child(pole)
	var flag := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.02, 0.32, 0.5)
	flag.mesh = fb
	flag.position = Vector3(0.25, 2.0, 0.46)
	flag.material_override = _mat(PENNANT, true)
	_pennant.add_child(flag)
	_pennant.visible = false
	_hp_mat = _mat(Color(0.4, 1.0, 0.5), true)
	_hp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.08)
	_hp_fill.mesh = q
	_hp_fill.material_override = _hp_mat
	_hp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_fill.position = Vector3(0.0, _H + 0.3, 0.0)
	add_child(_hp_fill)


func apply(pos: Vector3, yaw: float) -> void:
	position = pos
	rotation = Vector3(0.0, yaw, 0.0)


## `owner_kind`: 0 = Vanguard (pennant), 1 = someone's squad (grey sash), 2 = your squad (gold sash).
func set_state(team_: int, hp_frac: float, owner_kind: int) -> void:
	if team_ != team:
		team = team_
		_body_mat.albedo_color = COLOR_CONCORD if team == MapDef.TEAM_CONCORD else COLOR_SYNDICATE
	_pennant.visible = owner_kind == 0
	_sash.visible = owner_kind != 0
	if owner_kind != 0:
		(_sash.material_override as StandardMaterial3D).albedo_color = SASH_OWN if owner_kind == 2 else SASH_OTHER
		(_sash.material_override as StandardMaterial3D).emission = SASH_OWN if owner_kind == 2 else SASH_OTHER
	var f := clampf(hp_frac, 0.0, 1.0)
	_hp_fill.scale = Vector3(maxf(f, 0.02), 1.0, 1.0)
	_hp_mat.albedo_color = Color(1.0, 0.25, 0.2).lerp(Color(0.4, 1.0, 0.5), f)


func _box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = m
	add_child(mi)
	return mi


static func _mat(c: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m
