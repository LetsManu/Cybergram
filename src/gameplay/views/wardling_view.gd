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
## HP bar (M1 clutter fix): a small billboard strip, shown only once damaged.
const HP_BAR_SIZE := Vector2(0.42, 0.045)

var net_id: int = 0
var team: int = -1
var _body: MeshInstance3D
var _sash: MeshInstance3D
var _pennant: Node3D
var _hp_fill: MeshInstance3D
var _hp_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
## E10 Rewrite tells: Elite = gold outline shell + x1.3 scale; Turned = violet sash.
const ELITE_GOLD := Color("#FFC93C")
const TURNED_VIOLET := Color("#B07CFF")
const ELITE_SCALE: float = 1.3
## C5 Garrison Sentinel: a little larger than a squad Picket (art bible §6.4: static defenders).
const SENTINEL_SCALE: float = 1.12
var _elite_shell: MeshInstance3D
var _elite: bool = false
var _turned: bool = false
## Art pass: the procedural Picket (WardlingModel); the greybox stays hidden
## underneath. Tier is replicated (WardlingState.tier, protocol v8; set_tier).
var model: WardlingModel
var tier: int = 1
var _kind: int = 1
## Wardling v2 death: the rig plays its fall for DEATH_S, then fades over FADE_S
## and the view frees itself (WardlingPresenter hands removed Wardlings over).
const DEATH_S: float = 1.4
const FADE_S: float = 0.5
var dying: bool = false
var _dead_t: float = 0.0
var _hp_last: float = 1.0


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
	q.size = HP_BAR_SIZE
	_hp_fill.mesh = q
	_hp_fill.material_override = _hp_mat
	_hp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_fill.position = Vector3(0.0, _H + 0.25, 0.0)
	_hp_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_fill.visible = false
	add_child(_hp_fill)
	var gold := _mat(ELITE_GOLD, true)
	gold.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gold.albedo_color.a = 0.45
	gold.cull_mode = BaseMaterial3D.CULL_FRONT
	_elite_shell = _box(Vector3(0.86, 1.25, 0.66), Vector3(0.0, 0.62, 0.0), gold)
	_elite_shell.visible = false
	if ModelCatalog.models_enabled():
		_attach_model(null)


## Art hook: swaps the greybox for the model `def` resolves to (null = Picket).
func _attach_model(def: WardlingDef) -> void:
	if model != null:
		model.queue_free()
	model = WardlingModelBuilder.build(ModelCatalog.wardling_key(def), tier, team)
	model.apply_elite_scale = false
	add_child(model)
	for c in get_children():
		if c is MeshInstance3D and c != _hp_fill:
			(c as MeshInstance3D).visible = false
	_pennant.visible = false
	_sync_model()


## Model for a specific WardlingDef (variants arrive with their own models).
func set_def(def: WardlingDef) -> void:
	if ModelCatalog.models_enabled():
		_attach_model(def)


## Surge tier I-III (silhouette + scale per art bible §5.3).
func set_tier(tier_: int) -> void:
	tier = clampi(tier_, 1, 3)
	if model != null:
		model.set_tier(tier)


func _sync_model() -> void:
	if model == null:
		return
	if model.team != team:
		model.set_team(team)
	model.set_owner_kind(_kind)
	model.set_elite(_elite)
	model.set_turned(_turned)
	_sash.visible = false
	_pennant.visible = false
	_elite_shell.visible = false


func apply(pos: Vector3, yaw: float) -> void:
	position = pos
	rotation = Vector3(0.0, yaw, 0.0)


## `owner_kind`: 0 = Vanguard (pennant), 1 = someone's squad (grey sash), 2 = your squad (gold sash),
## 3 = Garrison Sentinel (plated, a little larger, no sash or pennant).
func set_state(team_: int, hp_frac: float, owner_kind: int) -> void:
	if team_ != team:
		team = team_
		_body_mat.albedo_color = COLOR_CONCORD if team == MapDef.TEAM_CONCORD else COLOR_SYNDICATE
	_pennant.visible = owner_kind == 0
	_sash.visible = owner_kind == 1 or owner_kind == 2
	if owner_kind != 0:
		(_sash.material_override as StandardMaterial3D).albedo_color = SASH_OWN if owner_kind == 2 else SASH_OTHER
		(_sash.material_override as StandardMaterial3D).emission = SASH_OWN if owner_kind == 2 else SASH_OTHER
	var f := clampf(hp_frac, 0.0, 1.0)
	if f < _hp_last - 0.001 and model != null:
		model.hit()
	_hp_last = f
	_hp_fill.visible = f < 0.995
	_hp_fill.scale = Vector3(maxf(f, 0.02), 1.0, 1.0)
	_hp_mat.albedo_color = Color(1.0, 0.25, 0.2).lerp(Color(0.4, 1.0, 0.5), f)
	_kind = owner_kind
	_sync_model()


## E10: Elite / Turned (snapshot state bits 6 / 7).
func set_rewrite(elite: bool, turned: bool) -> void:
	_elite = elite
	_turned = turned
	_elite_shell.visible = elite
	scale = Vector3.ONE * (ELITE_SCALE if elite else (SENTINEL_SCALE if _kind == 3 else 1.0))
	if turned:
		_sash.visible = true
		(_sash.material_override as StandardMaterial3D).albedo_color = TURNED_VIOLET
		(_sash.material_override as StandardMaterial3D).emission = TURNED_VIOLET
	_sync_model()


func is_elite() -> bool:
	return _elite


## A bolt left this Wardling's emitter (WardlingPresenter matches bolts to shooters).
func shoot() -> void:
	if model != null:
		model.shoot()


## True when the model can play a death (the v2 rig); otherwise the view just goes.
func can_die() -> bool:
	return model != null and model.rig != null


## Plays the death fall, then fades and frees the view. Presentation only: the
## Wardling is already gone on the server.
func die() -> void:
	if not can_die():
		queue_free()
		return
	dying = true
	_hp_fill.visible = false
	model.die()


func _process(delta: float) -> void:
	if not dying:
		return
	_dead_t += delta
	if _dead_t > DEATH_S:
		model.set_fade(clampf(1.0 - (_dead_t - DEATH_S) / FADE_S, 0.0, 1.0))
	if _dead_t > DEATH_S + FADE_S:
		queue_free()


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
