class_name GearVisuals
extends RefCounted
## Procedural body-gear meshes for Armory v2 open-slot items
## (items-and-armory.md §3.5 "Visual tell" column, §3.8). One shared mesh per
## (shape, tier); tier reads by SIZE, element COUNT, GLOW and idle motion
## (Signature only), never by colour (weapons-and-mods.md §3.6.2). Loose
## weapon components are belt clip-ons in their line hue (crystal on Mana
## guns, card on Mechanical guns, §3.3). Spares are unlit (§3.4 rule 3).
## Node meta "spinners" = [[Node3D, axis, rad/s]], "idle" = true when the
## item has idle motion (culled beyond ArmoryVisualsData.idle_cull_m()).

const PB := PartBuilder.Kind
const HW := Color("#3A3F48")
const CHROME := Color("#9AA3B0")

static var _cache: Dictionary = {}


## Builds the gear node for `item` at visual `tier` (1..3).
static func build(item: ArmoryItemDef, tier: int, mana_gun: bool, spare: bool, scl: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Gear_%s%s" % [item.id, "_spare" if spare else ""]
	var t := clampi(tier, 1, 3)
	root.scale = Vector3.ONE * scl * ArmoryVisualsData.tier_size(t)
	var energy := ArmoryVisualsData.tier_glow(t) * (ArmoryVisualsData.spare_dim() if spare else 1.0)
	var hue := item.hue.darkened(0.55) if spare else item.hue
	var glow := ModelMaterials.crystal(hue, energy, 1.0 if spare else 2.0, 0.0 if spare else 0.25 * (t - 1))
	var hw := ModelMaterials.toon(ModelPalette.TEAM_NEUTRAL)
	var spinners: Array = []
	var shape := ArmoryVisualsData.gear_shape(item.id)
	if item.kind == ArmoryItemDef.Kind.MOUNT:
		shape = "clip_crystal" if mana_gun else "clip_card"
	var key := "%s|%d" % [shape, t]
	if shape.begins_with("clip"):
		key = "%s|%s" % [shape, ArmoryVisualsData.item_cut(item.id)]
	_mi(root, _mesh("hw|" + key, func(b: PartBuilder) -> void: _hardware(b, shape, t)), hw)
	_mi(root, _mesh("glow|" + key, func(b: PartBuilder) -> void: _glow(b, shape, t, ArmoryVisualsData.item_cut(item.id))), glow)
	if t >= 3 and not spare:
		var spin := Node3D.new()
		spin.name = "Idle"
		root.add_child(spin)
		_mi(spin, _mesh("idle|" + shape, func(b: PartBuilder) -> void: _idle_part(b, shape)),
			ModelMaterials.holo(item.hue.lightened(0.2), 0.9))
		spinners.append([spin, Vector3.UP, 1.4])
	root.set_meta(&"spinners", spinners)
	root.set_meta(&"idle", not spinners.is_empty())
	return root


## Small badge on the back plate for an item with no position left (§3.8 rule 3).
static func badge(item: ArmoryItemDef, tier: int, spare: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Badge_%s" % item.id
	var e := ArmoryVisualsData.tier_glow(tier) * (ArmoryVisualsData.spare_dim() if spare else 1.0)
	_mi(root, _mesh("badge|%d" % tier, func(b: PartBuilder) -> void:
		b.cyl(0.018, 0.018, 0.006, PartBuilder.xf(Vector3.ZERO, Vector3(90, 0, 0)), Color.WHITE, PB.FLAT, 0.0, 6)
		for k in clampi(tier, 1, 3):  # pips = tier
			b.box(Vector3(0.005, 0.005, 0.004), PartBuilder.xf(Vector3(-0.008 + k * 0.008, -0.022, 0.0)), Color.WHITE)),
		ModelMaterials.crystal(item.hue, e, 1.0, 0.0))
	root.set_meta(&"spinners", [])
	root.set_meta(&"idle", false)
	return root


static func _hardware(b: PartBuilder, shape: String, t: int) -> void:
	match shape:
		"clip_crystal", "clip_card":
			b.box(Vector3(0.022, 0.03, 0.008), PartBuilder.xf(Vector3(0, 0, 0)), HW, PB.METAL)
		"cell", "cell_cage", "heart_cage":
			for k in 2 + t:  # cage bars
				var a := TAU * k / (2.0 + t)
				b.box(Vector3(0.004, 0.05, 0.004), PartBuilder.xf(Vector3(cos(a) * 0.024, 0, sin(a) * 0.024)), CHROME, PB.CHROME)
		"plate", "plates", "pauldron":
			for k in t:  # stacked plates = tier
				b.box(Vector3(0.09 - k * 0.012, 0.012, 0.08 - k * 0.01), PartBuilder.xf(Vector3(0, -k * 0.016, 0), Vector3(0, 0, -12)), CHROME, PB.METAL)
			if t >= 3:
				b.box(Vector3(0.1, 0.035, 0.014), PartBuilder.xf(Vector3(0, 0.025, -0.03)), CHROME, PB.METAL)  # raised collar
		"spool":
			b.cyl(0.018, 0.018, 0.006, PartBuilder.xf(Vector3(0, 0.014, 0)), HW, PB.METAL, 0.0, 10)
			b.cyl(0.018, 0.018, 0.006, PartBuilder.xf(Vector3(0, -0.014, 0)), HW, PB.METAL, 0.0, 10)
		"cowl", "fins", "lattice":
			b.box(Vector3(0.06, 0.012, 0.02), PartBuilder.xf(Vector3.ZERO), HW, PB.METAL)
		"bead":
			b.box(Vector3(0.006, 0.02, 0.006), PartBuilder.xf(Vector3(0.06, -0.06, 0)), HW, PB.METAL)
		"circlet", "halo":
			pass
		"band", "calf_rig":
			b.torus(0.045, 0.052, PartBuilder.xf(Vector3.ZERO), HW, PB.METAL, 0.0, 14, 4)
		"gauntlet":
			b.cyl(0.042, 0.038, 0.09, PartBuilder.xf(Vector3.ZERO), HW, PB.METAL, 0.0, 10)
		_:
			b.box(Vector3(0.03, 0.03, 0.01), PartBuilder.xf(Vector3.ZERO), HW, PB.METAL)


static func _glow(b: PartBuilder, shape: String, t: int, cut: String) -> void:
	var w := Color.WHITE
	match shape:
		"clip_crystal":
			match cut:
				"ember_heart":
					b.sphere(0.01, PartBuilder.xf(Vector3(-0.006, 0.01, -0.008)), w, PB.FLAT, 0.0, 6)
					b.sphere(0.01, PartBuilder.xf(Vector3(0.006, 0.01, -0.008)), w, PB.FLAT, 0.0, 6)
				"tempest":
					b.prism(Vector3(0.012, 0.04, 0.012), PartBuilder.xf(Vector3(0, 0.01, -0.008), Vector3(0, 0, 12)), w, PB.FLAT, 0.0, 0.2)
				"lens":
					b.torus(0.008, 0.013, PartBuilder.xf(Vector3(0, 0.01, -0.008), Vector3(90, 0, 0)), w, PB.FLAT, 0.0, 10, 4)
				"flat":
					b.box(Vector3(0.024, 0.024, 0.005), PartBuilder.xf(Vector3(0, 0.008, -0.008), Vector3(0, 0, 45)), w)
				"vial":
					b.capsule(0.007, 0.034, PartBuilder.xf(Vector3(0, 0.01, -0.008)), w)
				_:
					b.sphere(0.01, PartBuilder.xf(Vector3(0, 0.01, -0.008), Vector3.ZERO, Vector3(0.9, 1.7, 0.9)), w, PB.FLAT, 0.0, 6)
		"clip_card":
			b.box(Vector3(0.026, 0.034, 0.003), PartBuilder.xf(Vector3(0, 0.012, -0.006)), w)
		"cell":
			b.capsule(0.016, 0.04, PartBuilder.xf(Vector3.ZERO), w)
		"cell_cage":
			b.sphere(0.022, PartBuilder.xf(Vector3.ZERO), w, PB.FLAT, 0.0, 8)
		"heart_cage":
			b.sphere(0.02, PartBuilder.xf(Vector3(-0.012, 0.008, 0)), w, PB.FLAT, 0.0, 8)
			b.sphere(0.02, PartBuilder.xf(Vector3(0.012, 0.008, 0)), w, PB.FLAT, 0.0, 8)
			b.prism(Vector3(0.05, 0.035, 0.03), PartBuilder.xf(Vector3(0, -0.012, 0), Vector3(0, 0, 180)), w)
		"plate", "plates", "pauldron":
			for k in t:  # one glowing edge strip per plate
				b.box(Vector3(0.08 - k * 0.012, 0.003, 0.004), PartBuilder.xf(Vector3(0, -k * 0.016 + 0.007, -0.04 + k * 0.005), Vector3(0, 0, -12)), w)
		"spool":
			b.cyl(0.012, 0.012, 0.024, PartBuilder.xf(Vector3.ZERO), w, PB.FLAT, 0.0, 10)
		"cowl":
			for k in 2 + t:
				b.prism(Vector3(0.02, 0.07, 0.008), PartBuilder.xf(Vector3(-0.04 + k * 0.08 / (1.0 + t), -0.035, 0.0), Vector3(0, 0, 180)), w)
		"fins":
			for k in 3 + t:  # spine fins
				b.prism(Vector3(0.006, 0.05, 0.04), PartBuilder.xf(Vector3(0, 0.04 - k * 0.03, 0.02)), w)
		"lattice":
			b.cyl(0.03, 0.03, 0.01, PartBuilder.xf(Vector3(0, 0, 0.012), Vector3(90, 0, 0)), w, PB.FLAT, 0.0, 6)
		"bead":
			b.sphere(0.012, PartBuilder.xf(Vector3(0.06, -0.075, 0)), w, PB.FLAT, 0.0, 8)
		"circlet":
			b.torus(0.085, 0.093, PartBuilder.xf(Vector3(0, -0.06, 0)), w, PB.FLAT, 0.0, 20, 4)
		"halo":
			b.torus(0.07, 0.08, PartBuilder.xf(Vector3(0, 0.05, 0)), w, PB.FLAT, 0.0, 20, 4)
		"band":
			b.box(Vector3(0.016, 0.03, 0.006), PartBuilder.xf(Vector3(0, 0, 0.052)), w)
		"calf_rig":
			for k in t:
				b.box(Vector3(0.05, 0.006, 0.006), PartBuilder.xf(Vector3(0, -0.02 + k * 0.02, 0.054)), w)
		"gauntlet":
			b.prism(Vector3(0.04, 0.05, 0.01), PartBuilder.xf(Vector3(0, 0, -0.045), Vector3(90, 0, 0)), w)
		_:
			b.sphere(0.012, PartBuilder.xf(Vector3(0, 0, -0.008)), w, PB.FLAT, 0.0, 6)


## Signature idle part (floating / turning element, Signal tier).
static func _idle_part(b: PartBuilder, shape: String) -> void:
	var w := Color.WHITE
	match shape:
		"halo":
			for k in 6:
				var a := TAU * k / 6.0
				b.prism(Vector3(0.012, 0.03, 0.006), PartBuilder.xf(Vector3(cos(a) * 0.075, 0.07, sin(a) * 0.075)), w)
		"lattice":
			b.torus(0.06, 0.066, PartBuilder.xf(Vector3(0, 0, 0.02), Vector3(90, 0, 0)), w, PB.FLAT, 0.0, 6, 3)
		"heart_cage":
			b.torus(0.036, 0.04, PartBuilder.xf(Vector3.ZERO), w, PB.FLAT, 0.0, 16, 3)
		_:
			b.torus(0.05, 0.055, PartBuilder.xf(Vector3.ZERO), w, PB.FLAT, 0.0, 16, 3)


static func _mesh(k: String, fill: Callable) -> ArrayMesh:
	if not _cache.has(k):
		var b := PartBuilder.new()
		fill.call(b)
		_cache[k] = b.commit() if not b.is_empty() else ArrayMesh.new()
	return _cache[k]


static func _mi(parent: Node3D, mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = GfxQuality.character_layers()
	parent.add_child(mi)
	return mi
