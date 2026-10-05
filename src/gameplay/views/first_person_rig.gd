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
## W16-COMFORT: weapon bob on/off (GameSettings.comfort_weapon_bob).
var bob_enabled: bool = true
## Tuning (viewmodel FOV compensation, kick gain); ComfortRulesDef defaults.
var comfort_rules: ComfortRulesDef = ComfortRulesDef.new()
const GUN_POS := Vector3(0.16, -0.15, -0.38)
var _fov_factor: float = 1.0
var _vm_kick: Vector2 = Vector2.ZERO
## W19-VM: the hero's FP viewmodel (gloved hands, own weapon, FP clips) when
## assets/models/heroes/<key>/<key>_fp.glb exists; null = the box weapon above.
var fp_model: FpViewmodel
## Viewmodel pivot and scale at the reference FOV (the box gun or the FP glb grip).
var _vm_base_pos: Vector3 = VIEWMODEL_POS
var _vm_base_scale: float = VIEWMODEL_SCALE
var _weapon_def: WeaponDef
## Hero run speed (m/s) for the walk / sprint sway blend (HeroDef.move_speed).
var run_speed: float = 6.0
## W16-COMFORT reduce motion: freezes the FP loops and skips jump / land sway.
var reduce_motion: bool = false
var _grounded: bool = true
var _prev_cd := PackedInt32Array()
var _was_reloading: bool = false
var _was_burnout: bool = false
var _prev_ammo: float = 0.0
var _was_dead: bool = false


func setup(look: LookSettings) -> void:
	camera = Camera3D.new()
	camera.fov = look.fov_deg
	_fov_factor = ComfortMath.viewmodel_fov_factor(look.fov_deg, comfort_rules.viewmodel_ref_fov_deg)
	camera.near = 0.05
	camera.current = true
	add_child(camera)
	gun = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.07, 0.32)
	gun.mesh = box
	gun.position = _gun_pos()
	gun.scale = Vector3.ONE * _fov_factor
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
		run_speed = (hd as HeroDef).move_speed
		var team := int(p.call("own_team")) if p.has_method("own_team") else 0
		set_weapon((hd as HeroDef).weapon, ModelCatalog.hero_key(hd as HeroDef), team)


## Swaps the greybox gun for `def`'s viewmodel (null or unknown id = keep the box).
func set_weapon(def: WeaponDef, hero_key: StringName = &"", team: int = 0) -> void:
	var k := ModelCatalog.weapon_key(def)
	if k == &"" or camera == null:
		return
	if _vm != null:
		_vm.queue_free()
	_weapon_def = def
	weapon_model = null
	fp_model = null
	_vm = Node3D.new()
	_vm.name = "Viewmodel"
	camera.add_child(_vm)
	if hero_key == &"":
		hero_key = ModelCatalog.hero_key_from_id(String(def.id))
	if hero_key == &"":
		for hk in ModelCatalog.HERO_WEAPON:
			if ModelCatalog.HERO_WEAPON[hk] == k:
				hero_key = hk
	fp_model = FpViewmodel.build(hero_key, team, def.feed_kind == WeaponDef.FeedKind.MANA)
	if fp_model != null:  # W19-VM: the hero's own FP set
		_vm_base_pos = fp_model.fp_pos
		_vm_base_scale = fp_model.fp_scale
		_vm.add_child(fp_model)
		fp_model.play_draw()
	else:  # fallback: procedural box weapon + box forearms
		_vm_base_pos = VIEWMODEL_POS
		_vm_base_scale = VIEWMODEL_SCALE
		weapon_model = WeaponModelBuilder.build(k, true, team)
		weapon_model.rotation_degrees = Vector3(0.0, 4.0, 0.0)
		_vm.add_child(weapon_model)
		_add_arms(hero_key, team)
	_vm.position = _vm_pos()
	_vm.scale = Vector3.ONE * _vm_base_scale * _fov_factor
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
	if fp_model != null:
		fp_model.set_mounts(items, tiers)
		return
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
	if fp_model != null:
		return fp_model.mount_count()
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


## Sets the camera FOV and re-fits the viewmodel to it (a gun at a fixed camera
## offset drifts to the centre and shrinks at wide FOV; see ComfortMath).
func set_fov(deg: float) -> void:
	if camera == null:
		return
	camera.fov = deg
	_fov_factor = ComfortMath.viewmodel_fov_factor(deg, comfort_rules.viewmodel_ref_fov_deg)
	if gun != null:
		gun.scale = Vector3.ONE * _fov_factor
	if _vm != null:
		_vm.scale = Vector3.ONE * _vm_base_scale * _fov_factor


## Viewmodel pivot, FOV-compensated (x / y only; the depth stays).
func _vm_pos() -> Vector3:
	return Vector3(_vm_base_pos.x * _fov_factor, _vm_base_pos.y * _fov_factor, _vm_base_pos.z)


## Greybox gun position, FOV-compensated (x / y only).
func _gun_pos() -> Vector3:
	return Vector3(GUN_POS.x * _fov_factor, GUN_POS.y * _fov_factor, GUN_POS.z)


## Places the camera at `feet` + eye height with the given look angles.
## `hidden_kick` (x yaw, y pitch, radians) is the view punch the camera does not
## show at a reduced camera-recoil setting; the viewmodel spends it, so the gun
## still kicks (W16-COMFORT).
func follow(feet: Vector3, eye_height: float, yaw: float, pitch: float, hidden_kick: Vector2 = Vector2.ZERO) -> void:
	position = feet + Vector3(0.0, eye_height, 0.0)
	rotation = Vector3(0.0, yaw, 0.0)
	camera.rotation = Vector3(pitch, 0.0, 0.0)
	_vm_kick = hidden_kick * comfort_rules.viewmodel_kick_gain
	if gun != null:
		gun.position = _gun_pos() + _kick_offset()
		gun.rotation = Vector3(_vm_kick.y, _vm_kick.x, 0.0)
	if _vm != null:
		_viewmodel_bob(feet)


## Viewmodel displacement for the hidden kick (up / sideways on the view arc).
func _kick_offset() -> Vector3:
	var arm := comfort_rules.viewmodel_kick_arm_m
	return Vector3(-_vm_kick.x * arm, _vm_kick.y * arm, 0.0)


## Viewmodel walk bob / settle from the camera's ground speed (presentation).
func _viewmodel_bob(feet: Vector3) -> void:
	var dt := get_process_delta_time()
	var speed := 0.0
	if _last_feet != Vector3.INF and dt > 0.0:
		speed = Vector2(feet.x - _last_feet.x, feet.z - _last_feet.z).length() / dt
	_last_feet = feet
	var base := _vm_pos()
	if fp_model != null:  # W19-VM: walk / sprint sway are clips; the hidden kick stays procedural
		var sway := bob_enabled and not reduce_motion
		var sprint := speed > run_speed * 1.15
		_bob_amp = lerpf(_bob_amp, FpViewmodel.loco_point(speed, run_speed, sprint, sway), clampf(dt * 8.0, 0.0, 1.0))
		fp_model.set_motion(_bob_amp, 0.0 if reduce_motion else clampf(speed / maxf(run_speed, 0.1), 0.8, 1.4))
		_vm.position = base + _kick_offset()
		_vm.rotation = Vector3(_vm_kick.y, _vm_kick.x, 0.0)
		return
	if not bob_enabled:  # W16-COMFORT: a still gun (the hidden kick still shows)
		_bob_amp = 0.0
		_vm.position = base + _kick_offset()
		_vm.rotation = Vector3(_vm_kick.y, _vm_kick.x, 0.0)
		return
	_bob_amp = lerpf(_bob_amp, clampf(speed / 6.0, 0.0, 1.0), clampf(dt * 8.0, 0.0, 1.0))
	_bob_t += dt * (4.0 + 6.0 * _bob_amp)
	_vm.position = base + Vector3(sin(_bob_t) * 0.008, -absf(cos(_bob_t)) * 0.01, 0.0) * _bob_amp \
		+ Vector3(0.0, sin(_bob_t * 0.35) * 0.002, 0.0) + _kick_offset()
	_vm.rotation = Vector3(_vm_kick.y, _vm_kick.x, 0.0)


func _mat(c: Color, emissive: bool, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m


## Muzzle position for tracers / muzzle FX (null without a viewmodel).
func muzzle_global() -> Variant:
	var m: Marker3D = null
	if fp_model != null:
		m = fp_model.socket(&"fx_muzzle")
	elif weapon_model != null:
		m = weapon_model.socket(&"fx_muzzle")
	return m.global_position if m != null else null


## W19-VM hooks (presentation only, never gameplay timing) ---------------------

## A predicted own shot (ClientWorld.tick, the same moment RecoilKick kicks).
func play_shot() -> void:
	if fp_model != null and _weapon_def != null:
		fp_model.play_fire(_weapon_def.fire_rate)


## Own combat snapshot: death holsters and respawn draws the weapon; reload /
## Burnout start plays the reload clip stretched to the WeaponDef time; a
## restarted cooldown plays that slot's cast gesture.
func on_own_combat(c: SnapshotData.OwnCombat) -> void:
	if c == null:
		return
	if fp_model != null and c.dead != _was_dead:  # no weapon swap exists: holster on death, draw on respawn
		if c.dead:
			fp_model.play_holster()
		else:
			fp_model.play_draw()
	_was_dead = c.dead
	var reloading := (c.ammo_flags & AmmoFeed.FLAG_RELOADING) != 0
	var burnout := (c.ammo_flags & AmmoFeed.FLAG_BURNOUT) != 0
	if fp_model != null and not c.dead:
		var per_round := _weapon_def != null and _weapon_def.reload_per_round
		if reloading and (not _was_reloading or (per_round and c.ammo > _prev_ammo)):
			fp_model.play_reload(FpViewmodel.reload_duration(_weapon_def, c.ammo <= 0.0))  # per-round: once a round
		elif burnout and not _was_burnout:
			fp_model.play_reload(FpViewmodel.reload_duration(_weapon_def))
		if _prev_cd.size() == c.skill_cd_left.size():
			for i in c.skill_cd_left.size():
				if c.skill_cd_left[i] > _prev_cd[i]:
					fp_model.play_cast(i)
	_was_reloading = reloading
	_was_burnout = burnout
	_prev_ammo = c.ammo
	_prev_cd = c.skill_cd_left.duplicate()


## Jump / land sway (skipped with weapon bob off or reduce motion).
func set_grounded(grounded: bool) -> void:
	if fp_model != null:
		fp_model.set_grounded(grounded, bob_enabled and not reduce_motion)
	_grounded = grounded


## Weapon inspect (InputBindings action "inspect").
func play_inspect() -> void:
	if fp_model != null:
		fp_model.play_inspect()
