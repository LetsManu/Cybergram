class_name FirstPersonRig
extends Node3D
## Local first-person camera with a placeholder viewmodel (architecture.md §5.1
## FirstPersonRig). Yaw on the rig, pitch on the camera; the viewmodel is a child
## of the camera so it follows the view.

const _GUN_COLOR := Color(0.18, 0.2, 0.26)
const _ACCENT := Color(0.2, 0.95, 1.0)

var camera: Camera3D


func setup(look: LookSettings) -> void:
	camera = Camera3D.new()
	camera.fov = look.fov_deg
	camera.near = 0.05
	camera.current = true
	add_child(camera)
	var gun := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.07, 0.32)
	gun.mesh = box
	gun.position = Vector3(0.16, -0.15, -0.38)
	gun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gun.material_override = _mat(_GUN_COLOR, false)
	camera.add_child(gun)
	var strip := MeshInstance3D.new()
	var s := BoxMesh.new()
	s.size = Vector3(0.055, 0.015, 0.2)
	strip.mesh = s
	strip.position = Vector3(0.0, 0.04, -0.04)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.material_override = _mat(_ACCENT, true)
	gun.add_child(strip)


## Places the camera at `feet` + eye height with the given look angles.
func follow(feet: Vector3, eye_height: float, yaw: float, pitch: float) -> void:
	position = feet + Vector3(0.0, eye_height, 0.0)
	rotation = Vector3(0.0, yaw, 0.0)
	camera.rotation = Vector3(pitch, 0.0, 0.0)


func _mat(c: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m
