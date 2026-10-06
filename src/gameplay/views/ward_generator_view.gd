class_name WardGeneratorView
extends Node3D
## The Ward Generator of a Breach hardpoint at hero fidelity (docs/assets/
## ward_generator.md; match-flow-and-map.md §3.4). Presentation only: it reads
## the replicated HardpointState (owner, shielded, gen_frac, breach_phase2).
##
## Stages (stage_of, pure; ClientSfx uses the same function for the sounds):
##   NEUTRAL   unowned: neutral colours, no shield
##   SHIELDED  owned, shield up (dome with hex lattice)
##   EXPOSED   shield down, HP >= 75 %
##   CRACK_1   HP < 75 %      CRACK_2  HP < 50 %      CRACK_3  HP < 25 %
##   BREACHED  phase 2 (or HP 0): housing torn, core gone, wreck on the plinth
## The shield fades in / collapses over SHIELD_FADE_S; a stage change throws a
## burst of team sparks.

enum Stage { NEUTRAL, SHIELDED, EXPOSED, CRACK_1, CRACK_2, CRACK_3, BREACHED }

const KEY: StringName = &"ward_generator"
const SHIELD_SHADER := "res://assets/shaders/spatial_fx_ward_shield.gdshader"
## HP fractions below which crack stage 1 / 2 / 3 shows.
const CRACK_AT: Array[float] = [0.75, 0.5, 0.25]
const SHIELD_RADIUS_M: float = 3.4
const SHIELD_FADE_S: float = 0.45

var stage: int = Stage.NEUTRAL
var team: int = MapDef.TEAM_NEUTRAL
var _model: Node3D
var _shield: MeshInstance3D
var _shield_mat: ShaderMaterial
var _shield_target := 0.0
var _shield_now := 0.0
var _sparks: CPUParticles3D
var _smoke: CPUParticles3D


## The stage for a replicated hardpoint state (pure).
static func stage_of(owner: int, shielded: bool, gen_frac: float, breached: bool) -> int:
	if owner == MapDef.TEAM_NEUTRAL:
		return Stage.NEUTRAL
	if breached or gen_frac <= 0.0:
		return Stage.BREACHED
	if shielded:
		return Stage.SHIELDED
	if gen_frac < CRACK_AT[2]:
		return Stage.CRACK_3
	if gen_frac < CRACK_AT[1]:
		return Stage.CRACK_2
	if gen_frac < CRACK_AT[0]:
		return Stage.CRACK_1
	return Stage.EXPOSED


## Pieces visible at `s` (pure): [crack_1, crack_2, crack_3, wreck, core].
static func pieces_for(s: int) -> Dictionary:
	var crack := 0
	match s:
		Stage.CRACK_1:
			crack = 1
		Stage.CRACK_2:
			crack = 2
		Stage.CRACK_3, Stage.BREACHED:
			crack = 3
	return {&"crack_1": crack >= 1, &"crack_2": crack >= 2, &"crack_3": crack >= 3,
		&"wreck": s == Stage.BREACHED, &"core": s != Stage.BREACHED}


static func available() -> bool:
	return WorldModel.exists(KEY)


func setup(owner_team: int) -> void:
	name = "WardGenerator"
	team = owner_team
	_model = WorldModel.instantiate(KEY, owner_team)
	_model.name = "Model"
	add_child(_model)
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = load(SHIELD_SHADER)
	_shield = MeshInstance3D.new()
	_shield.name = "Shield"
	var sm := SphereMesh.new()
	sm.radius = SHIELD_RADIUS_M
	sm.height = SHIELD_RADIUS_M * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	_shield.mesh = sm
	_shield.material_override = _shield_mat
	_shield.position.y = 0.4
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false
	add_child(_shield)
	_sparks = CPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 40
	_sparks.lifetime = 0.9
	_sparks.explosiveness = 0.9
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 3.0
	_sparks.initial_velocity_max = 7.0
	_sparks.gravity = Vector3(0, -9.8, 0)
	_sparks.scale_amount_min = 0.04
	_sparks.scale_amount_max = 0.09
	_sparks.position.y = 1.6
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = pm
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_sparks.mesh = quad
	add_child(_sparks)
	# breached: a slow column of dark smoke from the torn housing
	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.emitting = false
	_smoke.amount = 24
	_smoke.lifetime = 3.5
	_smoke.direction = Vector3.UP
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 0.8
	_smoke.initial_velocity_max = 1.4
	_smoke.gravity = Vector3(0.15, 0.2, 0.0)
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	_smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.16, 0.14, 0.18, 0.55))
	fade.set_color(1, Color(0.3, 0.28, 0.34, 0.0))
	_smoke.color_ramp = fade
	_smoke.position.y = 2.0
	var sq := QuadMesh.new()
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.albedo_texture = _soft_dot()
	sq.material = smat
	_smoke.mesh = sq
	add_child(_smoke)
	_set_team(owner_team)
	_show_stage(Stage.NEUTRAL)


## Applies a replicated state; returns true when the stage changed.
func apply_state(owner: int, shielded: bool, gen_frac: float, breached: bool) -> bool:
	if owner != team:
		_set_team(owner)
	var s := stage_of(owner, shielded, gen_frac, breached)
	if s == stage:
		return false
	var prev := stage
	stage = s
	_show_stage(s)
	if s > Stage.EXPOSED and s > prev:
		_burst(1.0 if s == Stage.BREACHED else 0.5)
	return true


## A piece's MeshInstance3D (tests).
func piece(n: StringName) -> MeshInstance3D:
	return WorldModel.piece(_model, n)


func shield_visible() -> bool:
	return _shield.visible


func _show_stage(s: int) -> void:
	var vis := pieces_for(s)
	for n: StringName in vis:
		var mi := WorldModel.piece(_model, n)
		if mi != null:
			mi.visible = vis[n]
	_shield_target = 1.0 if s == Stage.SHIELDED else 0.0
	_apply_material()
	if _smoke != null:
		_smoke.emitting = s == Stage.BREACHED


func _set_team(t: int) -> void:
	team = t
	_apply_material()
	var c := ModelPalette.team_color(t) if t != MapDef.TEAM_NEUTRAL else Color(0.8, 0.78, 0.95)
	_shield_mat.set_shader_parameter("color", c)
	_sparks.color = c.lightened(0.3)


## The asset material for the current team; breached = no glow (a dead machine).
func _apply_material() -> void:
	if _model == null:
		return
	var mat := dead_material(team) if stage == Stage.BREACHED else WorldModel.material(KEY, team)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat


static var _dead: Dictionary = {}


## The team material with every emissive channel off (shared per team).
static func dead_material(t: int) -> ShaderMaterial:
	if not _dead.has(t):
		var m := WorldModel.material(KEY, t).duplicate() as ShaderMaterial
		m.set_shader_parameter("emission_energy", 0.0)
		m.set_shader_parameter("map_emission", 0.0)
		_dead[t] = m
	return _dead[t]


## A soft round puff (radial falloff), generated once.
static var _dot: ImageTexture


static func _soft_dot() -> ImageTexture:
	if _dot == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.5))
		_dot = ImageTexture.create_from_image(img)
	return _dot


func smoking() -> bool:
	return _smoke.emitting


func _burst(scale: float) -> void:
	_sparks.amount = int(40 * scale) + 10
	_sparks.restart()
	_sparks.emitting = true


func _process(delta: float) -> void:
	if _shield_now != _shield_target:
		_shield_now = move_toward(_shield_now, _shield_target, delta / SHIELD_FADE_S)
		_shield_mat.set_shader_parameter("strength", _shield_now)
		# collapse: the dome shrinks a little as it fades
		_shield.scale = Vector3.ONE * lerpf(0.85, 1.0, _shield_now)
	_shield.visible = _shield_now > 0.001
