class_name HeroView
extends Node3D
## Placeholder third-person view of a replicated hero (architecture.md §5.1
## hero_view.tscn): a capsule body and a visor that shows facing. Presentation
## only; it is positioned from an InterpolationBuffer by ClientWorld.

const _BODY_COLOR := Color(1.0, 0.35, 0.25)
const _VISOR_COLOR := Color(0.2, 0.95, 1.0)
const _HEIGHT: float = 1.8
const _RADIUS: float = 0.4
const _CROUCH_SCALE: float = 0.67

var _body: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = _RADIUS
	capsule.height = _HEIGHT
	_body.mesh = capsule
	_body.position.y = _HEIGHT / 2.0
	_body.material_override = _mat(_BODY_COLOR, false)
	add_child(_body)
	var visor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.15, 0.2)
	visor.mesh = box
	visor.material_override = _mat(_VISOR_COLOR, true)
	_body.add_child(visor)
	visor.position = Vector3(0.0, 1.5 - _HEIGHT / 2.0, -_RADIUS)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 64
	_label.outline_size = 14
	_label.pixel_size = 0.01
	_label.position = Vector3(0.0, _HEIGHT + 0.35, 0.0)
	add_child(_label)


func apply(pos: Vector3, yaw: float, crouching: bool) -> void:
	position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	scale = Vector3(1.0, _CROUCH_SCALE if crouching else 1.0, 1.0)


## Replicated health; a dead hero is hidden until it respawns.
func set_health(hp: int, max_hp: int, dead: bool) -> void:
	visible = not dead
	if _label != null:
		_label.text = "%d / %d" % [hp, max_hp]
		var f := float(hp) / maxf(1.0, max_hp)
		_label.modulate = Color(1.0, 0.25, 0.2).lerp(Color(0.4, 1.0, 0.5), f)


func _mat(c: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m
