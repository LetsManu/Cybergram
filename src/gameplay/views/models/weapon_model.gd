class_name WeaponModel
extends Node3D
## A procedural stand-in for one signature weapon (WeaponModelBuilder): body
## mesh(es), a Chamber conduit / magazine window, animated parts, and the four
## mount markers fixed by weapons-and-mods.md §3.6.1 (socket_core,
## socket_barrel, socket_frame, socket_chamber) plus fx_muzzle and the hand
## grips (grip_r = origin, grip_l = support hand). Mount visuals (E13 lines,
## tiers I-III) attach to the markers through set_mounts(). Faces -Z.

const SOCKETS: Array[StringName] = [&"socket_core", &"socket_barrel", &"socket_frame", &"socket_chamber"]
## Third-person mounts are 1.3x the viewmodel's (art bible §7).
const TP_MOUNT_SCALE: float = 1.3

var key: StringName = &""
var first_person: bool = false
var team: int = ModelPalette.TEAM_NEUTRAL
## True for Mana guns (crystal claws), false for Mechanical (chip slots).
var mana: bool = true

var _bp: Dictionary = {}
var _pivots: Dictionary = {}
var _markers: Dictionary = {}
var _mats: Array = []  # [MeshInstance3D, descriptor]
var _anim: Array = []
var _mount_nodes: Array[Node3D] = []
var _spinners: Array = []  # [Node3D, axis, speed]
var _conduit_tint := Color(0, 0, 0, 0)
var _time: float = 0.0


func build_from(bp: Dictionary, first_person_: bool, team_: int) -> void:
	_bp = bp
	key = bp.key
	mana = bp.get("mana", true)
	first_person = first_person_
	name = "WeaponModel_%s%s" % [key, "_fp" if first_person else ""]
	_pivots[&"root"] = self
	for p in bp.pivots:
		var n := Node3D.new()
		n.name = String(p.name)
		n.position = p.pos
		n.rotation = p.get("rot", Vector3.ZERO)
		(_pivots[p.parent] as Node3D).add_child(n)
		_pivots[p.name] = n
		if p.has("anim"):
			_anim.append([n, p.anim[0], p.anim[1], p.anim[2], n.rotation])
	for k in bp.meshes:
		var parts := (k as String).split("|")
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_%s_%s" % [parts[0], parts[1].get_slice(":", 0)]
		mi.mesh = bp.meshes[k]
		if first_person or parts[1] != "toon":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_pivots[StringName(parts[0])] as Node3D).add_child(mi)
		_mats.append([mi, parts[1]])
	for mk in bp.markers:
		var d: Array = bp.markers[mk]
		var m := Marker3D.new()
		m.name = String(mk)
		m.position = d[1]
		(_pivots[d[0]] as Node3D).add_child(m)
		_markers[mk] = m
	set_team(team_)


func socket(socket_name: StringName) -> Marker3D:
	return _markers.get(socket_name)


func marker_names() -> Array:
	return _markers.keys()


func grip_r_global() -> Vector3:
	return global_transform.origin


func grip_l_global() -> Vector3:
	return (_markers[&"grip_l"] as Node3D).global_position


func set_team(team_: int, enemy_outline: bool = false) -> void:
	team = team_
	for e in _mats:
		var mi: MeshInstance3D = e[0]
		var d: String = e[1]
		if d == "toon":
			mi.material_override = ModelMaterials.toon(team, first_person, enemy_outline)
		elif d == "conduit":
			mi.material_override = _conduit_material()
		else:
			mi.material_override = HeroModel.material_for(d, team, enemy_outline)


## Chamber conduit / magazine window tint (loaded Ammo Type hue; alpha 0 = team).
func set_chamber_tint(c: Color) -> void:
	_conduit_tint = c
	for e in _mats:
		if e[1] == "conduit":
			(e[0] as MeshInstance3D).material_override = _conduit_material()


func _conduit_material() -> Material:
	var c := _conduit_tint if _conduit_tint.a > 0.0 else ModelPalette.team_color(team)
	# Mechanical windows are Accent tier (never bloom, V5); mana conduits are Signal.
	return ModelMaterials.crystal(c, 1.4 if mana else 0.9, 4.0 if mana else 1.0, 0.5)


## E13 mount visuals: `items` (ArmoryItemDef or null) with `tiers`; each item
## goes to the marker of its socket. Returns the number of mount nodes.
func set_mounts(items: Array, tiers: PackedInt32Array) -> int:
	for n in _mount_nodes:
		n.queue_free()
	_mount_nodes.clear()
	_spinners.clear()
	set_chamber_tint(Color(0, 0, 0, 0))
	var s := 1.0 if first_person else TP_MOUNT_SCALE
	for i in items.size():
		var item := items[i] as ArmoryItemDef
		if item == null:
			continue
		var tier := clampi(tiers[i] if i < tiers.size() else 1, 1, 3)
		if item.socket == ArmoryItemDef.Socket.CHAMBER:
			set_chamber_tint(item.hue)
		var sock := socket(MountVisuals.socket_marker(item.socket))
		if sock == null:
			continue
		var n := MountVisuals.build(item, tier, mana, s * float(_bp.get("mount_scale", 1.0)))
		sock.add_child(n)
		_mount_nodes.append(n)
		for sp in n.get_meta(&"spinners", []):
			_spinners.append(sp)
	return _mount_nodes.size()


func mount_count() -> int:
	return _mount_nodes.size()


func triangle_count() -> int:
	return _bp.get("tris", 0)


func mesh_instance_count() -> int:
	return _mats.size()


func _process(delta: float) -> void:
	_time += delta
	for a in _anim:
		var n: Node3D = a[0]
		var r0: Vector3 = a[4]
		match a[1]:
			&"spin_z":
				n.rotation = Vector3(r0.x, r0.y, r0.z + _time * a[2])
			&"wobble_z":
				n.rotation = Vector3(r0.x, r0.y, r0.z + sin(_time * a[2]) * a[3])
	for sp in _spinners:
		var n: Node3D = sp[0]
		if is_instance_valid(n):
			n.rotate(sp[1], sp[2] * delta)
