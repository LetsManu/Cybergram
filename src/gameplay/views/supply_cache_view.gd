class_name SupplyCacheView
extends Node3D
## The Supply Cache of one hardpoint (docs/assets/supply_cache.md; C5,
## match-flow-and-map.md §3.5; art bible §6.4). Presentation only: it reads the
## replicated hardpoint owner and derives the Cache's team the way the server
## does (SupplyCacheSystem.owner_at: the owner, supply_switch_delay_s after it
## took the hardpoint).
##
## Stages (stage_of, pure; ClientSfx uses the same function):
##   NEUTRAL    nobody holds the hardpoint: lamps and icon dark, no label glow
##   SWITCHING  held, inside the switch delay: lamps blink in the new owner's
##              colour (<= 3 Hz; reduce motion: steady dim)
##   SERVING    the owner's lamps, icon and holo label lit
## `serving_me` (set by ClientWorld for the own hero in range): brass motes
## rise from the tray while it refills.

enum Stage { NEUTRAL, SWITCHING, SERVING }

const KEY: StringName = &"supply_cache"
const BLINK_HZ: float = 2.0

var stage: int = Stage.NEUTRAL
var team: int = MapDef.TEAM_NEUTRAL
var def: HardpointDef
var _model: Node3D
var _label: Label3D
var _motes: CPUParticles3D
var _seen_owner: int = -99
var _since_s: float = -1e9
var _t := 0.0
var _switch_s := 10.0


## The stage for hardpoint owner `owner`, taken at `since_s`, at `now_s` (pure).
static func stage_of(owner: int, since_s: float, now_s: float, switch_s: float) -> int:
	if owner == MapDef.TEAM_NEUTRAL:
		return Stage.NEUTRAL
	if SupplyCacheSystem.owner_at(owner, since_s, now_s, switch_s) == MapDef.TEAM_NEUTRAL:
		return Stage.SWITCHING
	return Stage.SERVING


static func available() -> bool:
	return WorldModel.exists(KEY)


func setup(d: HardpointDef, rules: MatchRulesDef = null) -> void:
	def = d
	name = "SupplyCache_%s" % d.id
	_switch_s = rules.supply_switch_delay_s if rules != null else MatchRulesDef.new().supply_switch_delay_s
	_model = WorldModel.instantiate(KEY, MapDef.TEAM_CONCORD)
	_model.name = "Model"
	add_child(_model)
	_label = HardpointView.make_world_label()
	_label.name = "Label"
	_label.text = "SUPPLY"
	_label.position.y = 1.6
	_label.visible = true
	# up close only: the zone label carries the hardpoint, this one names the crate
	_label.visibility_range_end = 25.0
	_label.visibility_range_end_margin = 5.0
	_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_label)
	_motes = CPUParticles3D.new()
	_motes.name = "Motes"
	_motes.emitting = false
	_motes.amount = 16
	_motes.lifetime = 0.8
	_motes.direction = Vector3.UP
	_motes.spread = 20.0
	_motes.gravity = Vector3(0, 1.0, 0)
	_motes.initial_velocity_min = 0.6
	_motes.initial_velocity_max = 1.2
	_motes.scale_amount_min = 0.6
	_motes.scale_amount_max = 1.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(0.45, 0.02, 0.3)
	_motes.color = Color("#FFD9A0")
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	q.material = pm
	_motes.mesh = q
	_motes.position.y = 1.0
	add_child(_motes)
	_show(Stage.NEUTRAL, MapDef.TEAM_NEUTRAL)


## Applies the replicated hardpoint owner at match time `now_s`; returns true
## when the stage changed.
func apply_owner(owner: int, now_s: float) -> bool:
	if owner != _seen_owner:
		# first sample: take the owner as settled (a client joining mid-match)
		_since_s = -1e9 if _seen_owner == -99 else now_s
		_seen_owner = owner
	var s := stage_of(owner, _since_s, now_s, _switch_s)
	if s == stage and owner == team:
		return false
	_show(s, owner)
	return true


## True while the own hero is being served here (motes on).
func serving_me() -> bool:
	return _motes.emitting


## The own hero is refilling here (ClientWorld): motes on / off.
func set_serving_me(on: bool) -> void:
	if _motes.emitting != on:
		_motes.emitting = on


func piece(n: StringName) -> MeshInstance3D:
	return WorldModel.piece(_model, n)


func _show(s: int, owner: int) -> void:
	stage = s
	team = owner
	var mat: ShaderMaterial
	if s == Stage.NEUTRAL:
		mat = WardGeneratorView.dead_material_of(KEY, MapDef.TEAM_CONCORD)
	else:
		mat = WorldModel.material(KEY, owner)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	var lit := s == Stage.SERVING
	for n in [&"lamps", &"icon"]:
		var p := piece(n)
		if p != null:
			p.visible = s != Stage.NEUTRAL
	_label.modulate = HardpointView.team_color(owner) if lit else Color(0.75, 0.75, 0.8, 0.6)
	if not lit:
		set_serving_me(false)


func _process(delta: float) -> void:
	_t += delta
	if stage != Stage.SWITCHING:
		return
	var lamps := piece(&"lamps")
	if lamps == null:
		return
	var gs := GameSettings.shared()
	if gs != null and gs.reduce_motion:
		lamps.visible = true
		return
	lamps.visible = fmod(_t * BLINK_HZ, 1.0) < 0.5
