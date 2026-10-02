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
## Art pass: the hero's signature weapon as a viewmodel (WeaponModel, chosen
## by WeaponDef through ModelCatalog) + first-person forearms. When present,
## the greybox `gun` is hidden and E13 mounts attach to its socket markers.
const VIEWMODEL_POS := Vector3(0.15, -0.155, -0.27)
const VIEWMODEL_SCALE: float = 0.6
var weapon_model: WeaponModel
var _vm: Node3D
var _last_items: Array = []
var _last_tiers := PackedInt32Array()
var _last_feet := Vector3.INF
var _bob_t: float = 0.0
var _bob_amp: float = 0.0


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


func _ready() -> void:
	if weapon_model == null and ModelCatalog.models_enabled():
		_weapon_from_parent()


## Art hook: picks the viewmodel from the owning ClientWorld's hero_def.
func _weapon_from_parent() -> void:
	var p := get_parent()
	if p == null:
		return
	var hd: Variant = p.get("hero_def")
	if hd is HeroDef and (hd as HeroDef).weapon != null:
		var team := int(p.call("own_team")) if p.has_method("own_team") else 0
		set_weapon((hd as HeroDef).weapon, ModelCatalog.hero_key(hd as HeroDef), team)


## Swaps the greybox gun for `def`'s viewmodel (null or unknown id = keep the box).
func set_weapon(def: WeaponDef, hero_key: StringName = &"", team: int = 0) -> void:
	var k := ModelCatalog.weapon_key(def)
	if k == &"" or camera == null:
		return
	if _vm != null:
		_vm.queue_free()
	_vm = Node3D.new()
	_vm.name = "Viewmodel"
	_vm.position = VIEWMODEL_POS
	_vm.scale = Vector3.ONE * VIEWMODEL_SCALE
	camera.add_child(_vm)
	weapon_model = WeaponModelBuilder.build(k, true, team)
	weapon_model.rotation_degrees = Vector3(0.0, 4.0, 0.0)
	_vm.add_child(weapon_model)
	if hero_key == &"":
		hero_key = ModelCatalog.hero_key_from_id(String(def.id))
	if hero_key == &"":
		for hk in ModelCatalog.HERO_WEAPON:
			if ModelCatalog.HERO_WEAPON[hk] == k:
				hero_key = hk
	_add_arms(hero_key, team)
	gun.visible = false
	_mount_key = ""
	if not _last_items.is_empty():
		set_mounts(_last_items, _last_tiers)


func _add_arms(hero_key: StringName, team: int) -> void:
	var mat := ModelMaterials.toon(team, true)
	var grips := {"r": Vector3.ZERO, "l": weapon_model.transform * (weapon_model.socket(&"grip_l") as Node3D).position}
	var elbows := {"r": Vector3(0.2, -0.3, 0.18), "l": Vector3(-0.32, -0.34, -0.02)}
	for side in ["r", "l"]:
		var arm := MeshInstance3D.new()
		arm.name = "FpArm_" + side
		arm.mesh = HeroModelBuilder.fp_arm_mesh(hero_key, side)
		arm.material_override = mat
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var grip: Vector3 = grips[side]
		var dir: Vector3 = (grip - (elbows[side] as Vector3)).normalized()
		arm.basis = HeroModel._bone_basis(dir, Vector3(0.0, -1.0, 0.4))
		arm.position = grip - dir * HeroModelBuilder.FP_ARM_LEN
		_vm.add_child(arm)


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
	_last_items = items.duplicate()
	_last_tiers = tiers.duplicate()
	if weapon_model != null:
		weapon_model.set_mounts(items, tiers)
		return
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
	if weapon_model != null:
		return weapon_model.mount_count()
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
	if _vm != null:
		_viewmodel_bob(feet)


## Viewmodel walk bob / settle from the camera's ground speed (presentation).
func _viewmodel_bob(feet: Vector3) -> void:
	var dt := get_process_delta_time()
	var speed := 0.0
	if _last_feet != Vector3.INF and dt > 0.0:
		speed = Vector2(feet.x - _last_feet.x, feet.z - _last_feet.z).length() / dt
	_last_feet = feet
	_bob_amp = lerpf(_bob_amp, clampf(speed / 6.0, 0.0, 1.0), clampf(dt * 8.0, 0.0, 1.0))
	_bob_t += dt * (4.0 + 6.0 * _bob_amp)
	_vm.position = VIEWMODEL_POS + Vector3(sin(_bob_t) * 0.008, -absf(cos(_bob_t)) * 0.01, 0.0) * _bob_amp \
		+ Vector3(0.0, sin(_bob_t * 0.35) * 0.002, 0.0)


func _mat(c: Color, emissive: bool, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m
