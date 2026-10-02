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
## E10 status tells (StatusComponent.BIT_*): shell (Fortify DR / shield),
## halo (stun), ground ring (casting), slow chevrons.
var _shell: MeshInstance3D
var _halo: MeshInstance3D
var _cast_ring: MeshInstance3D
var _status: int = 0


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
	_shell = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.75
	sph.height = 2.2
	_shell.mesh = sph
	_shell.position.y = _HEIGHT / 2.0
	_shell.material_override = _tell_mat(Color(0.6, 0.8, 1.0, 0.25))
	add_child(_shell)
	_halo = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.3
	t.outer_radius = 0.4
	_halo.mesh = t
	_halo.position.y = _HEIGHT + 0.15
	_halo.material_override = _tell_mat(Color(1.0, 0.9, 0.2, 0.95))
	add_child(_halo)
	_cast_ring = MeshInstance3D.new()
	var r := TorusMesh.new()
	r.inner_radius = 0.9
	r.outer_radius = 1.05
	_cast_ring.mesh = r
	_cast_ring.position.y = 0.05
	_cast_ring.material_override = _tell_mat(Color(0.56, 0.36, 1.0, 0.9))
	add_child(_cast_ring)
	set_status(_status)


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


## E10: replicated status bits -> greybox tells.
func set_status(bits: int) -> void:
	_status = bits
	if _shell == null:
		return
	var dr := (bits & (StatusComponent.BIT_DR | StatusComponent.BIT_SHIELD | StatusComponent.BIT_CC_IMMUNE)) != 0
	_shell.visible = dr
	_halo.visible = (bits & (StatusComponent.BIT_STUN | StatusComponent.BIT_ROOT)) != 0
	_cast_ring.visible = (bits & (StatusComponent.BIT_CASTING | StatusComponent.BIT_DASHING)) != 0
	_body.transparency = 0.0
	(_body.material_override as StandardMaterial3D).albedo_color = \
		_BODY_COLOR.lerp(Color(0.5, 0.75, 1.0), 0.5) if (bits & StatusComponent.BIT_SLOW) != 0 else _BODY_COLOR


func _tell_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	return m


func _mat(c: Color, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m
