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
## Last replicated health (E12: the HUD draws the compact world health plate in
## screen space, src/ui/hud/world_overlay.gd; the old 64 px Label3D is gone).
var hp: int = 0
var max_hp: int = 0
## E10 status tells (StatusComponent.BIT_*): shell (Fortify DR / shield),
## halo (stun), ground ring (casting), slow chevrons.
var _shell: MeshInstance3D
var _halo: MeshInstance3D
var _cast_ring: MeshInstance3D
var _status: int = 0
## Art pass: procedural stand-in model (HeroModel) replacing the capsule.
## ClientWorld calls set_hero() from the replicated hero index
## (EntityState.hero_index -> ContentDB -> HeroDef id, protocol v8); the
## baseline hero (Ryker) is shown only for an unknown index. Team, velocity and
## pitch are read from the replicated snapshot entity of this view.
const DEFAULT_MODEL_ID: StringName = &"ryker"
var model: HeroModel
var model_key: StringName = &""
## Armory v2 public build of this hero (SnapshotData.EntityState.build; the
## tracer, scoreboard and death card read it).
var build := PackedInt32Array()
var team: int = -1
var _net_id: int = 0
var _pitch: float = 0.0
var _vel := Vector3.ZERO
var _last_pos := Vector3.INF
var _last_us: int = 0
var _crouching: bool = false
var _slow_ring: MeshInstance3D
## W13: last replicated dead flag (rigged models play the death clip, then hide).
var _dead: bool = false


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
	_slow_ring = MeshInstance3D.new()
	var sr := TorusMesh.new()
	sr.inner_radius = 0.5
	sr.outer_radius = 0.6
	_slow_ring.mesh = sr
	_slow_ring.position.y = 0.08
	_slow_ring.material_override = _tell_mat(Color(0.5, 0.75, 1.0, 0.8))
	add_child(_slow_ring)
	if ModelCatalog.models_enabled():
		_attach_model(model_key if model_key != &"" else DEFAULT_MODEL_ID)
		_bind_client.call_deferred()
	set_status(_status)


func apply(pos: Vector3, yaw: float, crouching: bool) -> void:
	if model != null:
		var now := Time.get_ticks_usec()
		if _net_id == 0 and _last_pos != Vector3.INF and now > _last_us:
			var v := (pos - _last_pos) / ((now - _last_us) / 1000000.0)
			_vel = _vel.lerp(v, 0.35) if v.length() < 30.0 else _vel
		_last_pos = pos
		_last_us = now
	position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	_crouching = crouching
	if model != null:
		scale = Vector3.ONE  # the model crouches by pose
		model.set_motion(_vel, crouching, _pitch)
	else:
		scale = Vector3(1.0, _CROUCH_SCALE if crouching else 1.0, 1.0)


## Replicated health; a dead hero is hidden until it respawns. A rigged model
## (W13) plays its death clip first and is hidden RiggedHeroModel.DEATH_HOLD_S later.
func set_health(hp_: int, max_hp_: int, dead: bool) -> void:
	var was_dead := _dead
	_dead = dead
	if model is RiggedHeroModel:
		model.set_dead(dead)
		if not dead:
			visible = true
		elif not was_dead and is_inside_tree():
			get_tree().create_timer(RiggedHeroModel.DEATH_HOLD_S).timeout.connect(_hide_if_dead)
		elif not was_dead:
			visible = false
	else:
		visible = not dead
	if model != null and hp_ < hp and not dead:
		model.flinch(clampf(float(hp - hp_) / maxf(1.0, max_hp_) * 6.0, 0.35, 1.0))
	hp = hp_
	max_hp = max_hp_


func _hide_if_dead() -> void:
	if _dead:
		visible = false


## E10: replicated status bits -> greybox tells.
func set_status(bits: int) -> void:
	_status = bits
	if _shell == null:
		return
	var dr := (bits & (StatusComponent.BIT_DR | StatusComponent.BIT_SHIELD | StatusComponent.BIT_CC_IMMUNE)) != 0
	_shell.visible = dr
	_halo.visible = (bits & (StatusComponent.BIT_STUN | StatusComponent.BIT_ROOT)) != 0
	_cast_ring.visible = (bits & (StatusComponent.BIT_CASTING | StatusComponent.BIT_DASHING)) != 0
	_slow_ring.visible = model != null and (bits & StatusComponent.BIT_SLOW) != 0
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


## Art hook: which hero this view shows (HeroDef, model key or id) and its
## team. Data-driven via HeroDef.model_id (ModelCatalog).
func set_hero(hero: Variant, team_: int = -2) -> void:
	var k: StringName = &""
	if hero is HeroDef:
		k = ModelCatalog.hero_key(hero as HeroDef)
	elif hero != null:
		k = ModelCatalog.hero_key_from_id(String(hero))
	if team_ != -2:
		team = team_
	if k != &"" and k != model_key and ModelCatalog.models_enabled():
		_attach_model(k)
	elif model != null and model.team != team:
		model.set_team(team)


func _attach_model(k: StringName) -> void:
	if not is_inside_tree() and _body == null:
		model_key = k
		return
	if model != null:
		model.queue_free()
	model_key = k
	model = HeroModelLoader.build(k, team)  # W13: rigged glb if present, else the box model
	add_child(model)
	_body.visible = false
	scale = Vector3.ONE


## Reads team / pitch for this view from replicated snapshots (no ClientWorld
## change needed): finds its own net id in the parent's remote_views().
func _bind_client() -> void:
	var cw := get_parent()
	if cw == null or not cw.has_method("remote_views"):
		return
	var session: Variant = cw.get("session")
	if session != null and (session as Object).has_signal("snapshot_received"):
		(session as Object).connect("snapshot_received", _on_snapshot)
	# W13: shot / skill-cast events drive the model's one-shot clips.
	if cw.has_signal("shot_received"):
		cw.connect("shot_received", _on_shot_event)
	if cw.has_signal("hit_confirmed"):  # W14-P2: directional additive flinch
		cw.connect("hit_confirmed", _on_hit_event)
	if cw.has_signal("skill_cast_received"):
		cw.connect("skill_cast_received", _on_cast_event)
	if cw.has_signal("kill_received"):  # W16: killing-blow direction picks the death clip
		cw.connect("kill_received", _on_kill_event)


func _on_shot_event(e: GameEvent) -> void:
	if model != null and _net_id != 0 and e.source_net_id == _net_id:
		model.play_shoot()


func _on_hit_event(e: GameEvent) -> void:
	if not (model is RiggedHeroModel) or _net_id == 0 or e.target_net_id != _net_id:
		return
	var cw := get_parent()
	var from: Variant = cw.call("hero_view_position", e.source_net_id) if cw != null else null
	model.flinch(clampf(e.amount / maxf(1.0, float(max_hp)) * 6.0, 0.35, 1.0), from if from != null else Vector3.INF)


## W16: KILL (to every client) carries victim + killer; the killer's position picks
## RiggedHeroModel's forward or backward death. Presentation only, no protocol change.
func _on_kill_event(e: GameEvent) -> void:
	if not (model is RiggedHeroModel) or _net_id == 0 or e.target_net_id != _net_id:
		return
	(model as RiggedHeroModel).set_death_dir(killer_position(get_parent(), e.source_net_id))


## World position of a killer: a remote hero's view, else the own player's body,
## else Vector3.INF (minions, towers, unknown).
static func killer_position(cw: Node, killer_id: int) -> Vector3:
	if cw == null or killer_id == 0:
		return Vector3.INF
	if cw.has_method("hero_view_position"):
		var p: Variant = cw.call("hero_view_position", killer_id)
		if p != null:
			return p
	var session: Variant = cw.get("session")
	var body: Variant = cw.get("body")
	if session != null and body != null and int((session as Object).get("own_net_id")) == killer_id:
		return (body as Node3D).global_position + Vector3(0.0, 1.45, 0.0)
	return Vector3.INF


func _on_cast_event(e: GameEvent) -> void:
	if model != null and _net_id != 0 and e.source_net_id == _net_id:
		model.play_cast(e.cast_slot())


func _on_snapshot(snap: SnapshotData) -> void:
	if _net_id == 0:
		var views: Dictionary = get_parent().call("remote_views")
		for id in views:
			if views[id] == self:
				_net_id = id
				break
	for e in snap.entities:
		if e.net_id == _net_id:
			_pitch = e.pitch
			_vel = e.velocity
			if model != null:
				model.set_grounded(e.grounded)
				# Armory v2 public build (items-and-armory.md §3.8): gun parts and
				# body gear; skipped inside the model while the build is unchanged.
				model.set_build(e.build)
			build = e.build
			if e.team != team:
				team = e.team
				if model != null:
					model.set_team(team)
			return

