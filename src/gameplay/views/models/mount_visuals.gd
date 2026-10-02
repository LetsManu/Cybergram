class_name MountVisuals
extends RefCounted
## E13 "Power You Can See" mount meshes (art bible §7.1-7.4) built in code:
## a Crystal or Chip line at one socket, tiers read by SIZE, COUNT, GLOW and
## idle motion — never by colour. Crystal cut shapes per line (Ember Heart =
## twin-lobe heart, Flux Coil = helix rings...). Tier III adds the floating
## holo rune ring / moving module (>= 15 cm of silhouette at 1.3x in 3P).
## Meshes are cached per (line, tier, part) and shared by every gun.

const PB := PartBuilder.Kind
## Glow per tier: Crystals may reach Signal tier at II-III (faint bloom),
## Chips stay Accent tier (<= 1.0, never bloom: art bible V5 / §7.3).
const CRYSTAL_ENERGY: Array[float] = [0.9, 1.5, 2.4]
const CHIP_ENERGY: Array[float] = [0.55, 0.8, 1.0]
const CRYSTAL_SIZE: Array[float] = [1.0, 1.4, 1.85]

static var _mesh_cache: Dictionary = {}


static func socket_marker(socket: int) -> StringName:
	match socket:
		ArmoryItemDef.Socket.CORE:
			return &"socket_core"
		ArmoryItemDef.Socket.BARREL:
			return &"socket_barrel"
		ArmoryItemDef.Socket.FRAME:
			return &"socket_frame"
		ArmoryItemDef.Socket.CHAMBER:
			return &"socket_chamber"
	return &""


## Builds the visual for `item` at `tier` (1..3). Node meta "spinners" lists
## [Node3D, axis, rad/s] for the owning WeaponModel to animate.
static func build(item: ArmoryItemDef, tier: int, mana_gun: bool, scl: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Mount_%s_t%d" % [item.id, tier]
	root.scale = Vector3.ONE * scl
	var spinners: Array = []
	var crystal := item.family == ArmoryItemDef.Family.CRYSTAL or (item.family == ArmoryItemDef.Family.ANY and mana_gun)
	var t := clampi(tier, 1, 3) - 1
	var glow: float = CRYSTAL_ENERGY[t] if crystal else CHIP_ENERGY[t]
	var glow_mat := ModelMaterials.crystal(item.hue, glow, 4.0 if crystal else 1.0, 0.3 + 0.3 * t)
	var hw_mat := ModelMaterials.toon(ModelPalette.TEAM_NEUTRAL)
	match item.socket:
		ArmoryItemDef.Socket.CORE:
			if crystal:
				var spin := Node3D.new()
				spin.position.y = 0.012 * (1.0 + t)
				root.add_child(spin)
				_mi(spin, _mesh("core_c|%s|%d" % [_cut(item.id), t], func(b: PartBuilder) -> void:
					_crystal_cut(b, _cut(item.id), CRYSTAL_SIZE[t])), glow_mat)
				spinners.append([spin, Vector3.UP, 0.6])
				if t >= 1:
					var motes := Node3D.new()
					motes.position.y = spin.position.y
					root.add_child(motes)
					_mi(motes, _mesh("motes|%d" % t, func(b: PartBuilder) -> void:
						for k in 2 + (t - 1):
							var a := TAU * k / (2.0 + (t - 1))
							b.sphere(0.006, PartBuilder.xf(Vector3(cos(a) * 0.045, 0.0, sin(a) * 0.045)), Color.WHITE, PB.FLAT, 0.0, 6)), glow_mat)
					spinners.append([motes, Vector3.UP, 2.2])
				if t >= 2:
					var ring := Node3D.new()
					ring.position.y = spin.position.y
					root.add_child(ring)
					_mi(ring, _mesh("runering", func(b: PartBuilder) -> void:
						b.torus(0.06, 0.068, PartBuilder.xf(Vector3.ZERO), Color.WHITE, PB.FLAT, 0.0, 24, 4)
						for k in 6:
							var a := TAU * k / 6.0
							b.box(Vector3(0.012, 0.004, 0.006), PartBuilder.xf(Vector3(cos(a) * 0.075, 0.0, sin(a) * 0.075), Vector3(0, -rad_to_deg(a), 0)), Color.WHITE)),
						ModelMaterials.holo(item.hue.lightened(0.25), 1.0))
					spinners.append([ring, Vector3.UP, -0.9])
			else:
				_mi(root, _mesh("core_chip|%d" % t, func(b: PartBuilder) -> void:
					b.box(Vector3(0.036, 0.014, 0.052), PartBuilder.xf(Vector3(0, 0.007, 0)), Color("#202329"))
					b.box(Vector3(0.03, 0.004, 0.044), PartBuilder.xf(Vector3(0, 0.0155, 0)), Color("#3A3F48"))
					for f in t + 1:  # heat-sink fins = tier
						b.box(Vector3(0.044, 0.016 + 0.004 * t, 0.003), PartBuilder.xf(Vector3(0, 0.026, -0.016 + f * 0.014)), Color("#5B6170"), PB.CHROME)), hw_mat)
				_mi(root, _mesh("core_chip_led|%d" % t, func(b: PartBuilder) -> void:
					for k in t + 1:
						b.box(Vector3(0.006, 0.004, 0.006), PartBuilder.xf(Vector3(0.022, 0.012, -0.015 + k * 0.012)), Color.WHITE)), glow_mat)
				if t >= 2:
					var fly := Node3D.new()
					fly.position = Vector3(0.0, 0.05, 0.0)
					root.add_child(fly)
					_mi(fly, _mesh("flywheel", func(b: PartBuilder) -> void:
						b.torus(0.024, 0.034, PartBuilder.xf(Vector3.ZERO, Vector3(0, 0, 90)), Color("#9AA3B0"), PB.CHROME, 0.0, 16, 4)
						for k in 4:
							b.box(Vector3(0.004, 0.05, 0.004), PartBuilder.xf(Vector3.ZERO, Vector3(45.0 * k, 0, 0)), Color("#9AA3B0"), PB.CHROME)), hw_mat)
					_mi(fly, _mesh("flycore", func(b: PartBuilder) -> void:
						b.sphere(0.012, PartBuilder.xf(Vector3.ZERO), Color.WHITE, PB.FLAT, 0.0, 8)), glow_mat)
					spinners.append([fly, Vector3.RIGHT, 9.0])
		ArmoryItemDef.Socket.FRAME:
			var n := t + 1  # count = tier
			if crystal:
				_mi(root, _mesh("frame_c|%s|%d" % [item.id, t], func(b: PartBuilder) -> void:
					for k in n:
						if item.id == &"flux_coil":
							b.torus(0.022, 0.028, PartBuilder.xf(Vector3(0, -0.01, -0.03 + k * 0.03), Vector3(80, 0, 20)), Color.WHITE, PB.FLAT, 0.0, 12, 4)
						else:
							b.capsule(0.009, 0.05, PartBuilder.xf(Vector3(-0.004, 0.0, -0.035 + k * 0.03), Vector3(90, 0, 0)), Color.WHITE)), glow_mat)
			else:
				_mi(root, _mesh("frame_chip|%d" % t, func(b: PartBuilder) -> void:
					for k in n:
						b.box(Vector3(0.008, 0.03, 0.026), PartBuilder.xf(Vector3(-0.004, 0.0, -0.03 + k * 0.03)), Color("#262A31"))
						b.box(Vector3(0.004, 0.036, 0.004), PartBuilder.xf(Vector3(-0.002, 0.0, -0.043 + k * 0.03)), Color("#9AA3B0"), PB.CHROME)), hw_mat)
				_mi(root, _mesh("frame_chip_led|%d" % t, func(b: PartBuilder) -> void:
					for k in n:
						b.box(Vector3(0.004, 0.006, 0.006), PartBuilder.xf(Vector3(-0.009, 0.01, -0.03 + k * 0.03)), Color.WHITE)), glow_mat)
		ArmoryItemDef.Socket.BARREL:
			_mi(root, _mesh("barrel|%s|%d" % [crystal, t], func(b: PartBuilder) -> void:
				for k in t + 1:  # lens rings / shroud rings = tier
					b.torus(0.026 + 0.004 * t, 0.032 + 0.004 * t, PartBuilder.xf(Vector3(0, 0, -0.02 - k * 0.022), Vector3(90, 0, 0)), Color.WHITE, PB.FLAT, 0.0, 16, 4)),
				glow_mat if crystal else hw_mat)
		ArmoryItemDef.Socket.CHAMBER:
			_mi(root, _mesh("chamber_cap", func(b: PartBuilder) -> void:
				b.cyl(0.012, 0.014, 0.012, PartBuilder.xf(Vector3(0, 0.006, 0)), Color.WHITE, PB.FLAT, 0.0, 6)), glow_mat)
	root.set_meta(&"spinners", spinners)
	return root


static func _cut(id: StringName) -> String:
	var s := String(id)
	for c in ["ember_heart", "tempest", "prism_eye", "wellspring"]:
		if s.begins_with(c):
			return c
	return "gem"


## Crystal cut shapes (colour-blind backup, art bible §7.2), base ~2-4 cm.
static func _crystal_cut(b: PartBuilder, cut: String, s: float) -> void:
	var w := Color.WHITE
	match cut:
		"ember_heart":
			b.sphere(0.014 * s, PartBuilder.xf(Vector3(-0.009 * s, 0.012 * s, 0), Vector3.ZERO, Vector3(1, 1.1, 0.8)), w, PB.FLAT, 0.0, 6)
			b.sphere(0.014 * s, PartBuilder.xf(Vector3(0.009 * s, 0.012 * s, 0), Vector3.ZERO, Vector3(1, 1.1, 0.8)), w, PB.FLAT, 0.0, 6)
			b.prism(Vector3(0.042 * s, 0.03 * s, 0.022 * s), PartBuilder.xf(Vector3(0, -0.004 * s, 0), Vector3(0, 0, 180)), w)
		"tempest":
			b.prism(Vector3(0.02 * s, 0.06 * s, 0.02 * s), PartBuilder.xf(Vector3(0, 0.02 * s, 0), Vector3(0, 0, 12)), w, PB.FLAT, 0.0, 0.2)
			b.prism(Vector3(0.016 * s, 0.035 * s, 0.016 * s), PartBuilder.xf(Vector3(0.006 * s, -0.012 * s, 0), Vector3(0, 0, 160)), w)
		"prism_eye":
			b.sphere(0.018 * s, PartBuilder.xf(Vector3.ZERO), w, PB.FLAT, 0.0, 8)
		"wellspring":
			b.sphere(0.016 * s, PartBuilder.xf(Vector3(0, -0.004 * s, 0)), w, PB.FLAT, 0.0, 8)
			b.cyl(0.0, 0.015 * s, 0.03 * s, PartBuilder.xf(Vector3(0, 0.018 * s, 0)), w, PB.FLAT, 0.0, 8)
		_:
			b.sphere(0.018 * s, PartBuilder.xf(Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 1.7, 0.9)), w, PB.FLAT, 0.0, 6)


static func _mesh(k: String, fill: Callable) -> ArrayMesh:
	if not _mesh_cache.has(k):
		var b := PartBuilder.new()
		fill.call(b)
		_mesh_cache[k] = b.commit()
	return _mesh_cache[k]


static func _mi(parent: Node3D, mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
