class_name WardlingModelBuilder
extends RefCounted
## Builds the Picket Wardling (art bible §5.3-5.4): a 0.9 m chibi hover-biped
## toy-soldier — rounded shell (faction value: porcelain / iron), gold or brass
## trim, single holo-LED visor eye, mana core in a chrome cage (front + back),
## back fin with tier pips. Tiers add silhouette (II: shoulder plates + crest;
## III: crown of three crystal shards in claws + ribbon). Class markings:
## owner sash (personal), pennant (Vanguard). Every mesh is shared by all
## Wardlings (one toon material per team), so ~100 on screen stay cheap.

const K := PartBuilder.Kind
const SCALE_BY_TIER: Array[float] = [1.0, 1.08, 1.15]
const ELITE_SCALE: float = 1.3

static var _meshes: Dictionary = {}


static func build(model_key: StringName, tier: int, team: int) -> WardlingModel:
	var m := WardlingModel.new()
	m.setup(model_key, tier, team)
	return m


static func _x(p: Vector3, r: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return PartBuilder.xf(p, r, s)


## Shared mesh `part` ("body1".."body3", "leg", "sash", "sash_own", "pennant", "elite", "ring").
static func mesh(part: String) -> ArrayMesh:
	if _meshes.has(part):
		return _meshes[part]
	var b := PartBuilder.new()
	match part:
		"body1", "body2", "body3":
			_body(b, int(part.right(1)))
		"leg":
			b.capsule(0.062, 0.22, _x(Vector3(0, -0.09, 0)), Color.WHITE, K.TRIM)
			b.box(Vector3(0.12, 0.06, 0.16), _x(Vector3(0, -0.2, -0.02)), ModelPalette.GUNMETAL, K.FLAT, 0.0, Vector2(0.85, 0.85))
			b.box(Vector3(0.1, 0.012, 0.1), _x(Vector3(0, -0.235, -0.02)), Color.WHITE, K.NEON, 0.6)
		"sash", "sash_own":
			var e := 1.0 if part == "sash_own" else 0.75
			b.torus(0.255, 0.3, _x(Vector3(0, 0.42, 0), Vector3(0, 0, 18), Vector3(1.0, 1.4, 0.9)), Color.WHITE, K.NEON, e, 20, 4)
			b.box(Vector3(0.06, 0.16, 0.02), _x(Vector3(-0.2, 0.3, 0.2), Vector3(10, 0, 20)), Color.WHITE, K.NEON, e)
			if part == "sash_own":  # owner-only marker: knot + owner ground ring
				b.sphere(0.04, _x(Vector3(-0.25, 0.36, 0.16)), ModelPalette.ELITE_GOLD, K.GLOW, 0.9, 8)
				b.torus(0.5, 0.56, _x(Vector3(0, 0.01, 0), Vector3.ZERO, Vector3(1, 0.05, 1)), Color.WHITE, K.NEON, 0.7, 28, 3)
		"pennant":
			b.cyl(0.012, 0.012, 0.85, _x(Vector3(0.0, 0.95, 0.24)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 6)
			# narrow flag angled off the pole so it reads from front and side
			b.box(Vector3(0.02, 0.24, 0.34), _x(Vector3(0.1, 1.2, 0.36), Vector3(0, -40, 0)), Color.WHITE, K.NEON, 0.8, Vector2(1.0, 0.35))
			b.box(Vector3(0.026, 0.11, 0.11), _x(Vector3(0.08, 1.2, 0.33), Vector3(45, -40, 0)), Color.WHITE, K.TRIM)  # faction glyph
			b.box(Vector3(0.05, 0.05, 0.25), _x(Vector3(0.26, 0.63, 0.0), Vector3(0, 0, -20)), Color.WHITE, K.NEON, 0.7)  # shoulder stripe
		"elite":
			# Vesper's rewritten Elite: gold thread lines + a second floating spindle.
			for k in 3:
				b.torus(0.27 - k * 0.03, 0.28 - k * 0.03, _x(Vector3(0, 0.42 + k * 0.13, 0), Vector3(0, 0, 0), Vector3(1.0, 0.25, 0.9)), ModelPalette.ELITE_GOLD, K.GLOW, 0.9, 20, 3)
			b.box(Vector3(0.02, 0.24, 0.02), _x(Vector3(0, 1.12, 0)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, Vector2(0.5, 0.5))
			b.cyl(0.03, 0.03, 0.02, _x(Vector3(0, 1.0, 0)), ModelPalette.ELITE_GOLD, K.METAL, 0.0, 8)
			b.sphere(0.04, _x(Vector3(0, 1.27, 0), Vector3.ZERO, Vector3(0.8, 1.6, 0.8)), ModelPalette.LEYFALL_VIOLET, K.GLOW, 1.0, 6)
		"ring":
			b.torus(0.48, 0.55, _x(Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.05, 1)), ModelPalette.LEYFALL_VIOLET, K.GLOW, 1.0, 28, 3)
	var m := b.commit()
	_meshes[part] = m
	return m


static func _body(b: PartBuilder, tier: int) -> void:
	var gold := Color.WHITE
	# rounded shell torso/head (faction value), hovering above the legs
	b.sphere(0.27, _x(Vector3(0, 0.53, 0), Vector3.ZERO, Vector3(1.0, 1.12, 0.92)), Color.WHITE, K.TRIM, 0.0, 14)
	b.torus(0.25, 0.285, _x(Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.92)), gold, K.METAL, 0.0, 18, 4)
	b.box(Vector3(0.3, 0.1, 0.22), _x(Vector3(0, 0.27, 0)), ModelPalette.GUNMETAL, K.FLAT, 0.0, Vector2(1.2, 1.2))
	# visor band + single holo-LED eye
	b.box(Vector3(0.3, 0.09, 0.08), _x(Vector3(0, 0.68, -0.205), Vector3(-8, 0, 0)), ModelPalette.NIGHT_INK, K.FLAT, 0.0, Vector2(0.9, 1.0))
	b.sphere(0.04, _x(Vector3(0.0, 0.68, -0.245), Vector3.ZERO, Vector3(1.5, 0.75, 0.6)), Color.WHITE, K.NEON, 1.0, 8)
	# mana core in a chrome cage — visible front and back (the team signal)
	var core_e := [1.3, 1.8, 2.6][tier - 1] as float
	for z in [-1.0, 1.0]:
		b.sphere(0.065 + 0.008 * tier, _x(Vector3(0, 0.46, 0.215 * z)), Color.WHITE, K.SIGNAL, core_e, 10)
		b.torus(0.07 + 0.008 * tier, 0.085 + 0.008 * tier, _x(Vector3(0, 0.46, 0.22 * z), Vector3(90, 0, 0)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 12, 4)
		for k in 3:
			b.box(Vector3(0.012, 0.15, 0.012), _x(Vector3(-0.04 + k * 0.04, 0.46, 0.25 * z)), ModelPalette.CHROME_COOL, K.CHROME)
		if tier >= 2:
			b.torus(0.095, 0.105, _x(Vector3(0, 0.46, 0.235 * z), Vector3(90, 0, 0)), Color.WHITE, K.NEON, 1.0, 14, 3)
	# printed serial / crew tag (fine detail)
	b.box(Vector3(0.08, 0.025, 0.01), _x(Vector3(0.14, 0.58, -0.2), Vector3(0, 30, 0)), ModelPalette.GREY)
	# stubby arms + emitter hand
	for s in [1.0, -1.0]:
		b.capsule(0.06, 0.2, _x(Vector3(0.29 * s, 0.44, -0.02), Vector3(25, 0, -18 * s)), Color.WHITE, K.TRIM)
		b.sphere(0.05, _x(Vector3(0.32 * s, 0.34, -0.08)), ModelPalette.GUNMETAL, K.FLAT, 0.0, 8)
	b.cyl(0.022, 0.03, 0.12, _x(Vector3(0.33, 0.34, -0.15), Vector3(90, 0, 0)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 8)
	# short back fin with tier pips
	b.prism(Vector3(0.04, 0.24, 0.2), _x(Vector3(0, 0.78, 0.13), Vector3(-35, 0, 0)), Color.WHITE, K.TRIM, 0.0, 0.8)
	for k in tier:
		b.box(Vector3(0.046, 0.024, 0.024), _x(Vector3(0, 0.66 + k * 0.05, 0.25), Vector3(-35, 0, 0)), gold, K.METAL)
	if tier >= 2:
		# shoulder armour plates + head crest
		for s in [1.0, -1.0]:
			b.box(Vector3(0.16, 0.06, 0.18), _x(Vector3(0.27 * s, 0.6, -0.01), Vector3(0, 0, -28 * s)), gold, K.METAL, 0.0, Vector2(0.8, 0.9))
		b.prism(Vector3(0.05, 0.14, 0.26), _x(Vector3(0, 0.88, -0.03)), gold, K.METAL)
	if tier >= 3:
		# crown of three crystal shards in chrome claws + short mana ribbon
		for k in 3:
			var a := deg_to_rad(-35.0 + 35.0 * k)
			var p := Vector3(sin(a) * 0.13, 0.98 - absf(sin(a)) * 0.05, -0.02)
			b.cyl(0.03, 0.02, 0.05, _x(p + Vector3(0, -0.06, 0), Vector3(0, 0, -rad_to_deg(a) * 0.6)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 6)
			b.sphere(0.035, _x(p + Vector3(0, 0.02, 0), Vector3(0, 0, -rad_to_deg(a) * 0.6), Vector3(0.7, 2.0, 0.7)), Color.WHITE, K.SIGNAL, 2.0, 6)
		b.box(Vector3(0.05, 0.3, 0.01), _x(Vector3(0.0, 0.62, 0.34), Vector3(-60, 0, 0)), Color.WHITE, K.NEON, 1.0, Vector2(0.4, 1.0))
