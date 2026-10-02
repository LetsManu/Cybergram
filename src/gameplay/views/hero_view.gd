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


func apply(pos: Vector3, yaw: float, crouching: bool) -> void:
	position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	scale = Vector3(1.0, _CROUCH_SCALE if crouching else 1.0, 1.0)


func _mat(c: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m
