class_name AbilityPresenter
extends Node3D
## Client greybox VFX for skills (E10; art bible §8.2 telegraph language):
## one node per replicated SnapshotData.FxState (AbilityWorld.FX_*).
## - Team colour rims (Concord azure, Syndicate ember); raw mana = violet core.
## - Hostile areas: serrated border ticks + ≤25% fill; allied areas: smooth
##   thin border + ≤12% fill (own effects use the allied style).
## - Projectiles: white core, team rim; enemy ones 20% thicker.
## Presentation only: built from snapshots, never feeds back into the sim.

const VIOLET := Color("#8E5CFF")
const HEAL := Color("#46E07A")
const _TICKS: int = 18

## PLACEHOLDER. Veilwalk readability bands (heroes.md §4.2): fully visible within
## FULL_M, a heat-shimmer within SHIMMER_M, invisible beyond; Sabotage Charges
## show to enemies only within CHARGE_SEE_M.
const FULL_M: float = 3.0
const SHIMMER_M: float = 8.0
const CHARGE_SEE_M: float = 6.0
const SHIMMER_FADE: float = 0.8
const BLIND_ALPHA: float = 0.7

## W10-W5 sfx hooks (presentation only): an FX appeared / moved (heal beam only) / ended.
signal fx_started(kind: int, position: Vector3, id: int)
signal fx_moved(kind: int, position: Vector3, id: int)
signal fx_ended(kind: int, id: int)

var client: ClientWorld
var _nodes: Dictionary = {}  # fx id -> [Node3D, kind]
## net id -> true while a remote hero is stealthed (from the replicated status).
var _stealthed: Dictionary = {}
var _revealed: Dictionary = {}  # net id -> true while revealed to our team (W11-M1)
var _faded: Dictionary = {}  # net id -> true while its model is faded by us
var _blind_rect: ColorRect
var _blind: bool = false
## W11-V1: recent SKILL_CAST events [team, fork, position, msec] and young, untinted FX
## [node, team, position, msec]; matched either way round (event / snapshot order varies).
var _recent_casts: Array = []
var _young_fx: Array = []
const _MATCH_MS: int = 600
const _MATCH_RANGE_M: float = 45.0


func apply_snapshot(s: SnapshotData) -> void:
	_stealthed.clear()
	_revealed.clear()
	_blind = false
	for e in s.entities:
		if (e.status & SkillStatusBits.REVEALED) != 0 and e.net_id != s.own_net_id:
			_revealed[e.net_id] = true
		if e.net_id == s.own_net_id:
			_blind = (e.status & SkillStatusBits.BLIND) != 0
		elif (e.status & SkillStatusBits.STEALTH) != 0:
			_stealthed[e.net_id] = true
	var seen := {}
	for f in s.fx:
		seen[f.id] = true
		var rec: Array = _nodes.get(f.id, [])
		if rec.is_empty() or rec[1] != f.kind:
			if not rec.is_empty():
				(rec[0] as Node3D).queue_free()
			rec = [_build(f), f.kind]
			_nodes[f.id] = rec
			_young_fx.append([rec[0], f.team, f.position, Time.get_ticks_msec()])
			_match_tints()
			fx_started.emit(f.kind, f.position, f.id)
		elif f.kind == SkillEntities.FX_BEAM:
			fx_moved.emit(f.kind, f.position, f.id)
		_update(rec[0], f)
	for id in _nodes.keys():
		if not seen.has(id):
			(_nodes[id][0] as Node3D).queue_free()
			fx_ended.emit(_nodes[id][1], id)
			_nodes.erase(id)


## W11-V1: a hero cast a skill (GameEvent.SKILL_CAST); its Fork tints the FX it spawns.
## `team` is the caster's team (from the replicated snapshot).
func on_skill_cast(fork: int, team: int, at: Vector3) -> void:
	if fork < 1:
		return
	_recent_casts.append([team, fork, at, Time.get_ticks_msec()])
	_match_tints()


func _match_tints() -> void:
	var now := Time.get_ticks_msec()
	_recent_casts = _recent_casts.filter(func(c: Array) -> bool: return now - c[3] <= _MATCH_MS)
	_young_fx = _young_fx.filter(func(f: Array) -> bool: return now - f[3] <= _MATCH_MS and is_instance_valid(f[0]))
	for f in _young_fx.duplicate():
		var best := -1
		var best_d := _MATCH_RANGE_M
		for i in _recent_casts.size():
			var c: Array = _recent_casts[i]
			var d := (c[2] as Vector3).distance_to(f[2])
			if c[0] == f[1] and d <= best_d:
				best = i
				best_d = d
		if best >= 0:
			FxForkTint.tint_tree(f[0], f[1], _recent_casts[best][1])
			_young_fx.erase(f)


func _process(_delta: float) -> void:
	_update_blind()
	if client == null or client.body == null:
		return
	client.body.collision_mask |= HeroBody.block_layer(client.own_team())  # W11-M1 Rampart
	var me := client.body.state.position
	var views := client.remote_views()
	for id in views:
		var v := views[id] as HeroView
		if v == null:
			continue
		_update_reveal_marker(v, _revealed.has(id))
		if v.model == null:
			continue
		if _stealthed.has(id) and v.team != client.own_team():
			var d := v.position.distance_to(me)
			v.model.visible = d <= SHIMMER_M
			_set_fade(v.model, 0.0 if d <= FULL_M else SHIMMER_FADE)
			_faded[id] = true
		elif _faded.has(id):
			v.model.visible = true
			_set_fade(v.model, 0.0)
			_faded.erase(id)


const REVEAL_COLOR := Color(1.0, 0.25, 0.2, 0.45)


## W11-M1: a see-through-walls silhouette on a revealed enemy (no depth test).
func _update_reveal_marker(v: HeroView, on: bool) -> void:
	var m := v.get_node_or_null("RevealMarker") as MeshInstance3D
	if not on:
		if m != null:
			m.queue_free()
			m.name = "RevealMarker_gone"
		return
	if m != null:
		return
	m = MeshInstance3D.new()
	m.name = "RevealMarker"
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.9
	m.mesh = cap
	m.position.y = 0.95
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = REVEAL_COLOR
	mat.render_priority = 100
	m.material_override = mat
	v.add_child(m)


func _set_fade(n: Node, t: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = t
	for c in n.get_children():
		_set_fade(c, t)


## Blind: full-screen white-out of the own screen (heroes.md §3.6).
func _update_blind() -> void:
	if _blind_rect == null:
		if not _blind:
			return
		var layer := CanvasLayer.new()
		layer.layer = 90
		add_child(layer)
		_blind_rect = ColorRect.new()
		_blind_rect.color = Color(1.0, 1.0, 1.0, BLIND_ALPHA)
		_blind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_blind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_blind_rect)
	_blind_rect.visible = _blind


func count() -> int:
	return _nodes.size()


func _hostile(team: int) -> bool:
	return client != null and team != client.own_team()


func _team_color(team: int) -> Color:
	return WardlingView.COLOR_CONCORD if team == MapDef.TEAM_CONCORD else WardlingView.COLOR_SYNDICATE


func _build(f: SnapshotData.FxState) -> Node3D:
	if f.kind >= TrapWorld.FX_FIRST:  # W9-H2 gadgets (Juniper traps, Hex hacks)
		var g := GadgetFx.build(f, _team_color(f.team), _hostile(f.team))
		add_child(g)
		return g
	var root := Node3D.new()
	add_child(root)
	var c := _team_color(f.team)
	var hostile := _hostile(f.team)
	match f.kind:
		AbilityWorld.FX_WALL, AbilityWorld.FX_WALL_SOLID:
			var size := f.position2
			# G1: holo-scanline barrier (art bible §10.4); the replicated `param`
			# still drives the fade, through the shader's `alpha`.
			var wall_mat := ModelMaterials.holo(c.lightened(0.25), 1.3, false, 0.0).duplicate() as ShaderMaterial
			var slab := _mesh(root, _box(Vector3(size.x, size.y, maxf(size.z, 0.2))), wall_mat)
			slab.name = "Slab"
			slab.position.y = size.y * 0.5
			for x in [-0.5, 0.5]:
				var post := _mesh(root, _box(Vector3(0.18, size.y + 0.2, 0.5)), _mat(Color.WHITE, 0.9, true))
				post.position = Vector3(x * size.x, size.y * 0.5, 0.0)
			var top := _mesh(root, _box(Vector3(size.x, 0.1, 0.45)), _mat(c, 0.95, true))
			top.position.y = size.y
			if f.kind == AbilityWorld.FX_WALL_SOLID:  # W11-M1 Rampart: the predicted body must collide too
				var sb := StaticBody3D.new()
				sb.collision_layer = HeroBody.block_layer(1 - f.team)
				sb.collision_mask = 0
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(size.x, size.y, maxf(size.z, 0.2))
				cs.shape = bs
				cs.position.y = size.y * 0.5
				sb.add_child(cs)
				root.add_child(sb)
		AbilityWorld.FX_BEACON:
			var pole := _mesh(root, _cyl(0.12, 1.6), _mat(VIOLET, 0.95, true))
			pole.position.y = 0.8
			var gem := _mesh(root, _sphere(0.28), ModelMaterials.crystal(VIOLET, 2.0, 3.0, 0.5))
			gem.position.y = 1.75
			_area(root, f.position2.x, HEAL.lerp(c, 0.4), hostile)
		AbilityWorld.FX_BASTION:
			_area(root, f.position2.x, c.lightened(0.3), hostile)
		AbilityWorld.FX_CIRCLE, AbilityWorld.FX_BURST:
			_area(root, f.position2.x, c if f.kind == AbilityWorld.FX_CIRCLE else Color.WHITE.lerp(c, 0.5), hostile)
			if f.kind == AbilityWorld.FX_BURST:
				# G1: bright inner shock ring + dome flash on top of the area ring.
				var br := maxf(f.position2.x, 0.5)
				var shock := TorusMesh.new()
				shock.inner_radius = br * 0.7
				shock.outer_radius = br * 0.74
				shock.rings = 48
				_mesh(root, shock, _mat(Color.WHITE, 0.9, true)).position.y = 0.15
				var dome := SphereMesh.new()
				dome.radius = br * 0.6
				dome.height = dome.radius
				dome.is_hemisphere = true
				_mesh(root, dome, _mat(Color.WHITE.lerp(c, 0.4), 0.18, true))
			if f.kind == AbilityWorld.FX_CIRCLE:
				# Ultimate / cast telegraph: vertical light column (art bible §8.2).
				var col := _mesh(root, _cyl(0.25, 14.0), ModelMaterials.holo(c.lightened(0.4), 1.6, false, 0.0))
				col.position.y = 7.0
				var halo := _mesh(root, _cyl(0.7, 14.0), _mat(c, 0.12, true))
				halo.position.y = 7.0
		SkillEntities.FX_THROWN:
			var orb := _mesh(root, _sphere(0.2), _mat(Color.WHITE.lerp(c, 0.35), 1.0, true))
			orb.position.y = 0.0
		SkillEntities.FX_DRONE:
			var body := _mesh(root, _sphere(0.22), _mat(Color.WHITE, 1.0, true))
			body.name = "Body"
			for x in [-1.0, 1.0]:
				var rotor := _mesh(root, _cyl(0.2, 0.02), _mat(HEAL, 0.9, true))
				rotor.position = Vector3(0.28 * x, 0.12, 0.0)
		SkillEntities.FX_DOME:
			var dome := SphereMesh.new()
			dome.radius = maxf(f.position2.x, 1.0)
			dome.height = dome.radius * 2.0
			dome.radial_segments = 32
			dome.rings = 16
			var shell := _mesh(root, dome, _mat(HEAL.lerp(c, 0.3).lightened(0.3), 0.14, true))
			shell.name = "Dome"
			_area(root, f.position2.x, HEAL.lerp(c, 0.3), hostile)
		SkillEntities.FX_CHARGE:
			var pad := _mesh(root, _box(Vector3(0.5, 0.12, 0.5)), _mat(Color("#3FBF8F"), 1.0, true))
			pad.position.y = 0.06
			var led := _mesh(root, _sphere(0.07), _mat(Color.WHITE, 1.0, true))
			led.position.y = 0.2
			led.name = "Led"
		AbilityWorld.FX_THREAD, AbilityWorld.FX_TRAIL, AbilityWorld.FX_ARROW, SkillEntities.FX_BEAM, SkillEntities.FX_DART:
			var w := 0.06 if f.kind != AbilityWorld.FX_ARROW else 0.5
			if hostile:
				w *= 1.2
			var line := _mesh(root, _box(Vector3(w, w if f.kind != AbilityWorld.FX_ARROW else 0.03, 1.0)),
				_mat(Color.WHITE.lerp(_line_color(f.kind, c), 0.45), 0.85, true))
			line.name = "Line"
			if f.kind == AbilityWorld.FX_ARROW:
				var head := _mesh(root, _box(Vector3(1.2, 0.03, 0.6)), _mat(c, 0.7, true))
				head.name = "Head"
	return root


func _update(n: Node3D, f: SnapshotData.FxState) -> void:
	if f.kind >= TrapWorld.FX_FIRST:
		GadgetFx.update(n, f, client, _hostile(f.team))
		return
	match f.kind:
		AbilityWorld.FX_WALL, AbilityWorld.FX_WALL_SOLID:
			n.position = f.position
			n.rotation = Vector3(0.0, f.yaw, 0.0)
			var slab := n.get_node_or_null("Slab") as MeshInstance3D
			if slab != null:
				(slab.material_override as ShaderMaterial).set_shader_parameter("alpha", 0.3 + 0.5 * f.param)
		SkillEntities.FX_THROWN, SkillEntities.FX_DRONE, SkillEntities.FX_DOME:
			n.position = f.position
			if f.kind == SkillEntities.FX_DOME:
				n.position.y += 0.05
		SkillEntities.FX_CHARGE:
			n.position = f.position
			var near := true
			if _hostile(f.team) and client != null and client.body != null:
				near = f.position.distance_to(client.body.state.position) <= CHARGE_SEE_M
			n.visible = near
			var led := n.get_node_or_null("Led") as MeshInstance3D
			if led != null:
				led.visible = f.param > 0.5
		AbilityWorld.FX_THREAD, AbilityWorld.FX_TRAIL, AbilityWorld.FX_ARROW, SkillEntities.FX_BEAM, SkillEntities.FX_DART:
			var tail_first := f.kind == AbilityWorld.FX_THREAD or f.kind == SkillEntities.FX_DART
			var a := f.position2 if tail_first else f.position
			var b := f.position if tail_first else f.position2
			if f.kind == AbilityWorld.FX_ARROW:
				a.y += 0.08
				b.y += 0.08
			var mid := (a + b) * 0.5
			var len := maxf(a.distance_to(b), 0.3)
			n.position = mid
			if len > 0.31:
				n.look_at_from_position(mid, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
			var line := n.get_node_or_null("Line") as Node3D
			if line != null:
				line.scale = Vector3(1.0, 1.0, len)
			var head := n.get_node_or_null("Head") as Node3D
			if head != null:
				head.position = Vector3(0.0, 0.0, -len * 0.5)
		AbilityWorld.FX_BURST:
			n.position = f.position + Vector3(0.0, 0.05, 0.0)
			var k := clampf(1.0 - f.ticks_left / 18.0, 0.2, 1.0)
			n.scale = Vector3(k, 1.0, k)
		_:
			n.position = f.position + Vector3(0.0, 0.05, 0.0)


func _line_color(kind: int, team_c: Color) -> Color:
	match kind:
		AbilityWorld.FX_ARROW:
			return team_c
		SkillEntities.FX_BEAM:
			return HEAL
		SkillEntities.FX_DART:
			return Color("#3FBF8F")
	return VIOLET


## Ground area: ring + fill (+ serrated outward ticks when hostile).
func _area(root: Node3D, radius: float, c: Color, hostile: bool) -> void:
	var r := maxf(radius, 0.5)
	var ring := TorusMesh.new()
	ring.inner_radius = r - (0.12 if hostile else 0.07)
	ring.outer_radius = r
	ring.rings = 48
	_mesh(root, ring, _mat(c, 0.95, true))
	var fill := _mesh(root, _cyl(r, 0.02), _mat(c, 0.22 if hostile else 0.1, false))
	fill.position.y = 0.01
	if hostile:
		for i in _TICKS:
			var a := TAU * i / _TICKS
			var t := _mesh(root, _box(Vector3(0.12, 0.08, 0.5)), _mat(c, 0.95, true))
			t.position = Vector3(cos(a), 0.0, sin(a)) * (r + 0.2)
			t.rotation.y = -a + PI / 2.0


func _mesh(parent: Node3D, m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 32
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


static func _mat(c: Color, alpha: float, emissive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m
