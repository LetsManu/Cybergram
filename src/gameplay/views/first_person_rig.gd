class_name FirstPersonRig
extends Node3D
## Local first-person camera with a placeholder viewmodel (architecture.md §5.1
## FirstPersonRig). Yaw on the rig, pitch on the camera; the viewmodel is a child
## of the camera so it follows the view.

const _GUN_COLOR := Color(0.18, 0.2, 0.26)
const _ACCENT := Color(0.2, 0.95, 1.0)

var camera: Camera3D
## The placeholder viewmodel; E13 greybox mounts are children of it.
var gun: MeshInstance3D
var _strip: MeshInstance3D
var _mounts: Node3D
var _mount_key: String = ""


func setup(look: LookSettings) -> void:
	camera = Camera3D.new()
	camera.fov = look.fov_deg
	camera.near = 0.05
	camera.current = true
	add_child(camera)
	gun = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.07, 0.32)
	gun.mesh = box
	gun.position = Vector3(0.16, -0.15, -0.38)
	gun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gun.material_override = _mat(_GUN_COLOR, false)
	camera.add_child(gun)
	var strip := MeshInstance3D.new()
	_strip = strip
	var s := BoxMesh.new()
	s.size = Vector3(0.055, 0.015, 0.2)
	strip.mesh = s
	strip.position = Vector3(0.0, 0.04, -0.04)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.material_override = _mat(_ACCENT, true)
	gun.add_child(strip)


## E13 "Power You Can See" (weapons-and-mods.md §3.6.3, §3.10 greybox): one
## primitive per line at its socket, scaled and brighter per tier. `items` /
## `tiers` follow SnapshotData.ProgressState.MOUNT_SOCKETS (Core, Frame,
## Chamber); null = empty socket. Crystals are faceted prisms, Chips are cards
## with fins; Tier III adds a halo ring. The Chamber tints the conduit strip.
func set_mounts(items: Array, tiers: PackedInt32Array) -> void:
	var key := ""
	for i in items.size():
		key += "%s:%d;" % [(items[i] as ArmoryItemDef).id if items[i] != null else "-", tiers[i]]
	if key == _mount_key or gun == null:
		return
	_mount_key = key
	if _mounts != null:
		_mounts.queue_free()
	_mounts = Node3D.new()
	gun.add_child(_mounts)
	_strip.material_override = _mat(_ACCENT, true)
	for i in items.size():
		var item := items[i] as ArmoryItemDef
		if item == null:
			continue
		var tier := clampi(tiers[i], 1, 3)
		match item.socket:
			ArmoryItemDef.Socket.CORE:
				_core_mount(item, tier)
			ArmoryItemDef.Socket.FRAME:
				_frame_mount(item, tier)
			ArmoryItemDef.Socket.CHAMBER:
				_strip.material_override = _mat(item.hue, true, 0.9)


## Number of mount meshes on the gun (tests / diagnostics).
func mount_mesh_count() -> int:
	return _mounts.get_child_count() if _mounts != null else 0


func _core_mount(item: ArmoryItemDef, tier: int) -> void:
	var s := [0.6, 0.85, 1.15][tier - 1] as float
	var glow := [0.5, 0.9, 1.4][tier - 1] as float
	var m := MeshInstance3D.new()
	if item.family == ArmoryItemDef.Family.CRYSTAL:
		var prism := PrismMesh.new()
		prism.size = Vector3(0.03, 0.05, 0.03) * s
		m.mesh = prism
		m.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	else:
		var card := BoxMesh.new()
		card.size = Vector3(0.04, 0.02, 0.06) * s
		m.mesh = card
		for f in tier:  # heatsink fins
			var fin := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(0.042 * s, 0.012, 0.004)
			fin.mesh = fb
			fin.position = Vector3(0.0, 0.012 * s, -0.02 * s + f * 0.02 * s)
			fin.material_override = _mat(item.hue.darkened(0.3), false)
			m.add_child(fin)
	m.position = Vector3(0.0, 0.035 + 0.025 * s, -0.06)
	m.material_override = _mat(item.hue, true, glow)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mounts.add_child(m)
	if tier >= 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.032
		torus.outer_radius = 0.038
		ring.mesh = torus
		ring.position = m.position
		ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		ring.material_override = _mat(item.hue.lightened(0.3), true, glow)
		_mounts.add_child(ring)


func _frame_mount(item: ArmoryItemDef, tier: int) -> void:
	for k in tier:  # count = tier (side crystals / plate chips)
		var m := MeshInstance3D.new()
		if item.family == ArmoryItemDef.Family.CRYSTAL:
			var p := PrismMesh.new()
			p.size = Vector3(0.018, 0.03, 0.018)
			m.mesh = p
			m.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		else:
			var b := BoxMesh.new()
			b.size = Vector3(0.006, 0.03, 0.03)
			m.mesh = b
		m.position = Vector3(-0.034, -0.005, 0.07 + k * 0.035)
		m.material_override = _mat(item.hue, true, 0.35 + 0.3 * tier)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mounts.add_child(m)


## Places the camera at `feet` + eye height with the given look angles.
func follow(feet: Vector3, eye_height: float, yaw: float, pitch: float) -> void:
	position = feet + Vector3(0.0, eye_height, 0.0)
	rotation = Vector3(0.0, yaw, 0.0)
	camera.rotation = Vector3(pitch, 0.0, 0.0)


func _mat(c: Color, emissive: bool, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m
