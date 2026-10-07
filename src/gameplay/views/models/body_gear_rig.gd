class_name BodyGearRig
extends Node3D
## Armory v2 body anchors + gear on one hero model (items-and-armory.md §3.8).
## Creates the `body_*` Marker3D anchors (belt 6 clips, chest 2, shoulders 2,
## back 2, head 1, legs 2, forearm 2, each with an overflow position, plus the
## back-plate badge row) from the per-hero preset in armory_visuals.json, on
## skeleton bones (BoneAttachment3D) or, without a skeleton, at model-space
## fallbacks. set_build() places the open-slot gear (BuildVisuals.plan_body)
## and forwards the gun places to the held WeaponModel. Idle motion is culled
## beyond ArmoryVisualsData.idle_cull_m() (§3.8 rule 6).

const ANCHORS: Array[StringName] = [&"body_belt", &"body_chest", &"body_shoulders", &"body_back",
	&"body_head", &"body_legs", &"body_forearm"]

var hero_key: StringName = &""
var mana_gun: bool = true
## Only the anchors first-person arms show (belt, forearm).
var first_person: bool = false

var _skeleton: Skeleton3D
var _model: Node3D
var _attach: Dictionary = {}  # bone -> Node3D
## anchor -> Array[Marker3D] (subs); anchor + "_overflow" -> Marker3D.
var _markers: Dictionary = {}
var _badge_root: Marker3D
var _gear: Array[Node3D] = []
var _spinners: Array = []
var _build := PackedInt32Array()
var _gear_scale: float = 1.0
var _gun: Array[Node3D] = []
var _gun_markers: Dictionary = {}


## Builds the anchors on `model` (HeroModel / RiggedHeroModel or any Node3D).
func setup(model: Node3D, hero_key_: StringName, skeleton: Skeleton3D = null) -> void:
	name = "BodyGear"
	_model = model
	hero_key = hero_key_
	_skeleton = skeleton
	model.add_child(self)
	var preset := ArmoryVisualsData.hero_preset(hero_key)
	var spread := float(preset.get("spread", 1.0))
	_gear_scale = float(preset.get("gear_scale", 1.0))
	var nudge: Dictionary = preset.get("nudge", {})
	var table := ArmoryVisualsData.anchors()
	for a in ANCHORS:
		var spec: Dictionary = table.get(String(a), {})
		var n := ArmoryVisualsData.vec(nudge.get(String(a), []))
		var subs: Array[Marker3D] = []
		var i := 0
		for s in spec.get("subs", []):
			subs.append(_marker(s, "%s_%d" % [a, i], spread, n))
			i += 1
		_markers[a] = subs
		var ov: Variant = spec.get("overflow")
		if ov is Dictionary:
			_markers[StringName(String(a) + "_overflow")] = _marker(ov, String(a) + "_overflow", spread, n)
	_badge_root = _marker(ArmoryVisualsData.badge(), "body_badges", spread, Vector3.ZERO)


## Anchor sub-position markers (tests / tools).
func anchor_markers(anchor: StringName) -> Array:
	return _markers.get(anchor, [])


func overflow_marker(anchor: StringName) -> Marker3D:
	return _markers.get(StringName(String(anchor) + "_overflow"))


func badge_root() -> Marker3D:
	return _badge_root


## Places `build` (11 places, SnapshotData.EntityState.build order). Does
## nothing when the build is unchanged. Returns the number of gear nodes.
func set_build(build: PackedInt32Array, cat: ArmoryCatalogDef = null) -> int:
	if build == _build:
		return _gear.size()
	_build = build.duplicate()
	var c := cat if cat != null else ArmoryVisualsData.catalog()
	for g in _gear:
		g.queue_free()
	_gear.clear()
	_spinners.clear()
	for g in _gun:
		for sp in g.get_meta(&"spinners", []):
			_spinners.append(sp)
	var subs := {}
	var has_ov := {}
	for a in ANCHORS:
		subs[a] = (_markers.get(a, []) as Array).size()
		has_ov[a] = overflow_marker(a) != null
	var step := ArmoryVisualsData.vec(ArmoryVisualsData.badge().get("step", [0.045, 0, 0]))
	for p in BuildVisuals.plan_body(build, c, subs, has_ov, first_person):
		var parent: Marker3D = null
		var node: Node3D
		match p.place:
			BuildVisuals.PLACE_SUB:
				parent = (_markers[p.anchor] as Array)[p.index]
			BuildVisuals.PLACE_OVERFLOW:
				parent = overflow_marker(p.anchor)
		if parent != null:
			node = GearVisuals.build(p.item, p.tier, mana_gun, p.spare, _gear_scale)
			if String(parent.name).ends_with("_0") and p.anchor in [&"body_shoulders", &"body_legs", &"body_forearm"]:
				node.scale.x = -node.scale.x  # mirror the left-side piece
		else:
			parent = _badge_root
			node = GearVisuals.badge(p.item, p.tier, p.spare)
			node.position = step * (p.index - 2.5)
		parent.add_child(node)
		_gear.append(node)
		for sp in node.get_meta(&"spinners", []):
			_spinners.append(sp)
	return _gear.size()


## Gun parts for a model without a WeaponModel (rigged glb gun): mounts the
## gun places of `build` on preset sockets off the hand bone ("gun" in
## armory_visuals.json), 1.3x like other third-person mounts (art bible §7.1).
func set_gun_build(build: PackedInt32Array, cat: ArmoryCatalogDef = null) -> int:
	var c := cat if cat != null else ArmoryVisualsData.catalog()
	var spec: Dictionary = ArmoryVisualsData.data().get("gun", {})
	for g in _gun:
		g.queue_free()
	_gun.clear()
	for it in BuildVisuals.gun_items(build, c):
		var item := it as ArmoryItemDef
		if item == null:
			continue
		var sock := String(MountVisuals.socket_marker(item.socket))
		if not _gun_markers.has(sock):
			_gun_markers[sock] = _marker({"bone": spec.get("bone", "Hand_R"), "pos": spec.get(sock, [0, 0, 0])}, "gun_" + sock, 1.0, Vector3.ZERO)
		if item.kind == ArmoryItemDef.Kind.AMMO:
			var ammo_hue := ArmoryVisualsData.ammo_color(item.ammo_type, item.hue)
			var dup := item.duplicate() as ArmoryItemDef
			dup.hue = ammo_hue
			item = dup
		var n := MountVisuals.build(item, BuildVisuals.visual_tier(item), mana_gun, float(spec.get("scale", 1.3)))
		(_gun_markers[sock] as Marker3D).add_child(n)
		_gun.append(n)
		for sp in n.get_meta(&"spinners", []):
			_spinners.append(sp)
	return _gun.size()


func gear_count() -> int:
	return _gear.size()


func _marker(spec: Dictionary, mname: String, spread: float, nudge: Vector3) -> Marker3D:
	var bone := String(spec.get("bone", "Hips"))
	var off := ArmoryVisualsData.vec(spec.get("pos", [0, 0, 0])) * spread + nudge
	var m := Marker3D.new()
	m.name = mname
	var along: Variant = spec.get("along")
	if _skeleton != null and _skeleton.find_bone(bone) >= 0:
		var bi := _skeleton.find_bone(bone)
		var rest := _skeleton.get_bone_global_rest(bi)
		var p := rest.origin
		if along is Array and (along as Array).size() >= 2 and _skeleton.find_bone(String(along[0])) >= 0:
			p = p.lerp(_skeleton.get_bone_global_rest(_skeleton.find_bone(String(along[0]))).origin, float(along[1]))
		# Local transform so the marker sits at `p + off` in skeleton space with
		# skeleton axes at rest, whatever the bone's own orientation.
		var want := Transform3D(Basis.IDENTITY, p + off)
		m.transform = rest.affine_inverse() * want
		_attachment(bone).add_child(m)
	else:
		var p := ArmoryVisualsData.bone_fallback(bone)
		if along is Array and (along as Array).size() >= 2:
			p = p.lerp(ArmoryVisualsData.bone_fallback(String(along[0])), float(along[1]))
		m.position = p + off
		add_child(m)
	return m


func _attachment(bone: String) -> Node3D:
	if not _attach.has(bone):
		var att := BoneAttachment3D.new()
		att.name = "Gear_" + bone
		att.bone_name = bone
		_skeleton.add_child(att)
		_attach[bone] = att
	return _attach[bone]


func _process(delta: float) -> void:
	if _spinners.is_empty():
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and cam.global_position.distance_to(global_position) > ArmoryVisualsData.idle_cull_m():
		return  # §3.8 rule 6: idle VFX culled beyond 30 m
	for sp in _spinners:
		var n: Node3D = sp[0]
		if is_instance_valid(n):
			n.rotate(sp[1], sp[2] * delta)
