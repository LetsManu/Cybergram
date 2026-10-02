class_name WeaponModelBuilder
extends RefCounted
## Builds the 7 signature weapons as chunky, invented mana-tech guns from
## shaped primitives (art bible §7: oversized receivers, clear grips and
## conduits, chrome mount hardware, one Accent-tier team neon trim, story
## marks from the hero). Origin = right-hand grip, forward = -Z, metres.
## The same blueprint serves the first-person viewmodel and the 3P model.

const K := PartBuilder.Kind
const C_CHROME := Color("#B9C3D0")
const C_INK := Color("#1D1F25")
const C_GUN := Color("#30343C")
const C_GUN_L := Color("#474C57")
const C_RUBBER := Color("#202125")
const C_BRASS := Color("#B48A4E")

static var _cache: Dictionary = {}


static func build(model_key: StringName, first_person: bool, team: int) -> WeaponModel:
	var m := WeaponModel.new()
	m.build_from(blueprint(model_key), first_person, team)
	return m


static func blueprint(model_key: StringName) -> Dictionary:
	if _cache.has(model_key):
		return _cache[model_key]
	var bp := ModelBlueprint.new(model_key)
	bp.data["mana"] = true
	match model_key:
		&"threadcaster":
			_threadcaster(bp)
		&"whisperfang":
			_whisperfang(bp)
		&"tackhammer":
			_tackhammer(bp)
		&"breakline":
			_breakline(bp)
		&"ironmaw":
			_ironmaw(bp)
		&"halo_repeater":
			_halo_repeater(bp)
		&"glitchcaster":
			_glitchcaster(bp)
		_:
			_breakline(bp)
	var out := bp.finish()
	_cache[model_key] = out
	return out


static func _x(p: Vector3, r: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return PartBuilder.xf(p, r, s)


## Grip (tilted back 14 deg) hanging from the origin.
static func _grip(b: PartBuilder, col: Color, w: float = 0.034, h: float = 0.12) -> void:
	b.box(Vector3(w, h, 0.045), _x(Vector3(0, -h * 0.5 + 0.01, 0.012), Vector3(-14, 0, 0)), col)
	b.box(Vector3(w + 0.006, 0.014, 0.05), _x(Vector3(0, -h + 0.012, 0.03), Vector3(-14, 0, 0)), col.darkened(0.3))
	# trigger guard
	b.torus(0.02, 0.026, _x(Vector3(0, -0.012, -0.04), Vector3(0, 0, 90)), C_GUN_L, K.FLAT, 0.0, 10, 4)


## Mana socket: open chrome claw with brass knuckles (art bible §7.1).
static func _claw(b: PartBuilder, p: Vector3, up: Vector3 = Vector3(0, 0, 0), r: float = 0.022) -> void:
	b.cyl(r * 1.1, r * 1.25, 0.012, _x(p, up), C_CHROME, K.CHROME, 0.0, 8)
	b.torus(r * 0.75, r * 1.0, _x(p + Basis.from_euler(up * PI / 180.0) * Vector3(0, 0.007, 0), up), C_BRASS, K.METAL, 0.0, 10, 4)
	for k in 3:
		var a := TAU * k / 3.0
		var off := Vector3(cos(a), 0, sin(a)) * r * 0.95
		b.box(Vector3(0.006, 0.03, 0.008), _x(p + Basis.from_euler(up * PI / 180.0) * (off + Vector3(0, 0.017, 0)),
			up + Vector3(cos(a) * -18.0, 0, sin(a) * 18.0)), C_CHROME, K.CHROME)


## Mechanical socket: empty chip slot with a dark LED.
static func _chip_slot(b: PartBuilder, p: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	b.box(Vector3(0.048, 0.012, 0.064), _x(p, rot), C_INK)
	b.box(Vector3(0.054, 0.006, 0.07), _x(p + Vector3(0, -0.006, 0), rot), C_CHROME, K.CHROME)
	b.box(Vector3(0.006, 0.006, 0.006), _x(p + Basis.from_euler(rot * PI / 180.0) * Vector3(0.026, 0.006, 0.026), rot), Color("#2A1A14"))


## Single continuous Accent-tier team neon trim along a seam.
static func _trim(b: PartBuilder, p: Vector3, size: Vector3) -> void:
	b.box(size, _x(p), Color.WHITE, K.NEON, 0.9)


static func _sockets(bp: ModelBlueprint, core: Vector3, barrel: Vector3, frame: Vector3, chamber: Vector3,
		muzzle: Vector3, grip_l: Vector3) -> void:
	bp.marker(&"socket_core", &"root", core)
	bp.marker(&"socket_barrel", &"root", barrel)
	bp.marker(&"socket_frame", &"root", frame)
	bp.marker(&"socket_chamber", &"root", chamber)
	bp.marker(&"fx_muzzle", &"root", muzzle)
	bp.marker(&"grip_l", &"root", grip_l)


# ------------------------------------------------------------------ Mana guns

## Vesper — long-barrelled semi-auto mana carbine, chrome receiver, spindle drum.
static func _threadcaster(bp: ModelBlueprint) -> void:
	var b := bp.at(&"root")
	var plum := ModelPalette.signature(&"vesper")
	var gold := ModelPalette.secondary(&"vesper")
	_grip(b, C_INK)
	b.box(Vector3(0.064, 0.09, 0.30), _x(Vector3(0, 0.05, -0.07)), C_CHROME, K.CHROME)
	b.box(Vector3(0.07, 0.04, 0.24), _x(Vector3(0, 0.105, -0.06)), plum, K.FLAT, 0.0, Vector2(0.8, 1.0))
	b.box(Vector3(0.05, 0.075, 0.24), _x(Vector3(0, 0.045, 0.17), Vector3(8, 0, 0)), plum, K.FLAT, 0.0, Vector2(1.0, 0.85))
	b.box(Vector3(0.056, 0.095, 0.022), _x(Vector3(0, 0.03, 0.29), Vector3(8, 0, 0)), gold, K.METAL)
	b.box(Vector3(0.056, 0.05, 0.26), _x(Vector3(0, 0.055, -0.33)), plum, K.FLAT, 0.0, Vector2(0.85, 1.0))
	b.cyl(0.016, 0.016, 0.34, _x(Vector3(0, 0.055, -0.58), Vector3(90, 0, 0)), C_GUN, K.FLAT, 0.0, 8)
	for k in 3:
		b.torus(0.016, 0.024, _x(Vector3(0, 0.055, -0.48 - k * 0.06), Vector3(90, 0, 0)), gold, K.METAL, 0.0, 10, 4)
	b.cyl(0.026, 0.02, 0.05, _x(Vector3(0, 0.055, -0.74), Vector3(90, 0, 0)), C_CHROME, K.CHROME, 0.0, 10)
	_trim(b, Vector3(-0.034, 0.07, -0.12), Vector3(0.004, 0.006, 0.36))
	b.box(Vector3(0.03, 0.06, 0.04), _x(Vector3(0, -0.02, -0.33)), C_RUBBER)  # foregrip
	_claw(b, Vector3(0, 0.13, -0.13))
	_claw(b, Vector3(-0.035, 0.05, 0.14), Vector3(0, 0, 90), 0.018)
	# story marks: two brass name-tags on a cord
	b.box(Vector3(0.002, 0.04, 0.002), _x(Vector3(0.034, 0.0, 0.05)), C_INK)
	b.box(Vector3(0.004, 0.02, 0.014), _x(Vector3(0.036, -0.03, 0.05)), C_BRASS, K.METAL)
	b.box(Vector3(0.004, 0.018, 0.012), _x(Vector3(0.036, -0.03, 0.07)), C_BRASS, K.METAL)
	# spindle drum conduit (Chamber), spins
	bp.pivot(&"drum", &"root", Vector3(0, 0.0, -0.16), Vector3.ZERO, [&"spin_z", 1.2, 0.0])
	bp.at(&"drum", "conduit").cyl(0.032, 0.032, 0.09, _x(Vector3.ZERO, Vector3(90, 0, 0)), Color.WHITE, K.FLAT, 0.0, 8)
	var d := bp.at(&"drum")
	for k in 2:
		d.cyl(0.04, 0.04, 0.012, _x(Vector3(0, 0, -0.05 + k * 0.1), Vector3(90, 0, 0)), gold, K.METAL, 0.0, 8)
	for k in 4:
		var a := TAU * k / 4.0
		d.box(Vector3(0.006, 0.006, 0.1), _x(Vector3(cos(a), sin(a), 0) * 0.036), C_CHROME, K.CHROME)
	_sockets(bp, Vector3(0, 0.15, -0.13), Vector3(0, 0.055, -0.76), Vector3(-0.042, 0.05, 0.14), Vector3(0, 0.0, -0.16),
		Vector3(0, 0.055, -0.78), Vector3(0, -0.04, -0.33))


## Sable — compact twin-grip mana SMG with an underslung tanto blade.
static func _whisperfang(bp: ModelBlueprint) -> void:
	var b := bp.at(&"root")
	var ink := ModelPalette.signature(&"sable")
	var jade := ModelPalette.secondary(&"sable")
	_grip(b, C_RUBBER)
	for k in 4:  # courier tally notches on the grip
		b.box(Vector3(0.036, 0.004, 0.006), _x(Vector3(0, -0.03 - k * 0.014, 0.036), Vector3(-14, 0, 0)), Color("#C9CCD2"))
	b.box(Vector3(0.068, 0.10, 0.26), _x(Vector3(0, 0.05, -0.07)), ink, K.FLAT, 0.0, Vector2(0.9, 0.95))
	b.box(Vector3(0.072, 0.03, 0.18), _x(Vector3(0, 0.115, -0.04)), C_GUN_L)
	b.box(Vector3(0.074, 0.012, 0.2), _x(Vector3(0, 0.02, -0.08)), jade, K.GLOW, 0.7)
	b.cyl(0.03, 0.034, 0.14, _x(Vector3(0, 0.06, -0.27), Vector3(90, 0, 0)), C_GUN, K.FLAT, 0.0, 6)
	b.cyl(0.02, 0.02, 0.06, _x(Vector3(0, 0.06, -0.36), Vector3(90, 0, 0)), C_CHROME, K.CHROME, 0.0, 8)
	_trim(b, Vector3(-0.035, 0.085, -0.08), Vector3(0.004, 0.006, 0.22))
	# second (front) grip
	b.box(Vector3(0.03, 0.09, 0.036), _x(Vector3(0, -0.04, -0.2), Vector3(10, 0, 0)), C_RUBBER)
	# tanto blade underslung
	b.box(Vector3(0.006, 0.03, 0.2), _x(Vector3(0, -0.005, -0.33)), C_CHROME, K.CHROME, 0.0, Vector2(1.0, 0.7))
	b.prism(Vector3(0.006, 0.05, 0.05), _x(Vector3(0, -0.005, -0.445), Vector3(-90, 0, 0)), C_CHROME, K.CHROME, 0.0, 0.0)
	# folded wire stock
	for s in [-1.0, 1.0]:
		b.box(Vector3(0.006, 0.006, 0.18), _x(Vector3(0.028 * s, 0.06, 0.13)), C_CHROME, K.CHROME)
	b.box(Vector3(0.062, 0.05, 0.012), _x(Vector3(0, 0.05, 0.22)), C_RUBBER)
	_claw(b, Vector3(0, 0.13, -0.1), Vector3.ZERO, 0.02)
	_claw(b, Vector3(-0.036, 0.05, 0.02), Vector3(0, 0, 90), 0.016)
	b.box(Vector3(0.012, 0.03, 0.12), _x(Vector3(0.04, 0.05, -0.08)), C_CHROME, K.CHROME)
	bp.at(&"root", "conduit").capsule(0.012, 0.11, _x(Vector3(0.046, 0.05, -0.08), Vector3(90, 0, 0)), Color.WHITE)
	_sockets(bp, Vector3(0, 0.14, -0.1), Vector3(0, 0.06, -0.39), Vector3(-0.044, 0.05, 0.02), Vector3(0.046, 0.05, -0.08),
		Vector3(0, 0.06, -0.4), Vector3(0, -0.03, -0.2))


## Liora — full-auto mana rifle, rounded, a glass bulb conduit, halo muzzle ring.
static func _halo_repeater(bp: ModelBlueprint) -> void:
	var b := bp.at(&"root")
	var ivory := ModelPalette.signature(&"liora")
	var sage := ModelPalette.secondary(&"liora")
	_grip(b, sage.darkened(0.35))
	b.capsule(0.05, 0.40, _x(Vector3(0, 0.055, -0.1), Vector3(90, 0, 0)), ivory)
	b.capsule(0.036, 0.22, _x(Vector3(0, 0.05, 0.18), Vector3(96, 0, 0)), ivory)
	b.cyl(0.05, 0.05, 0.14, _x(Vector3(0, 0.055, -0.18), Vector3(90, 0, 0)), sage, K.FLAT, 0.0, 12)
	b.cyl(0.022, 0.026, 0.26, _x(Vector3(0, 0.055, -0.42), Vector3(90, 0, 0)), sage.darkened(0.2), K.FLAT, 0.0, 10)
	b.torus(0.045, 0.06, _x(Vector3(0, 0.055, -0.56), Vector3(90, 0, 0)), C_CHROME, K.CHROME, 0.0, 20, 5)
	b.torus(0.03, 0.036, _x(Vector3(0, 0.055, -0.58), Vector3(90, 0, 0)), Color.WHITE, K.NEON, 0.9, 16, 4)
	_trim(b, Vector3(-0.05, 0.06, -0.12), Vector3(0.004, 0.006, 0.26))
	# leaf-in-ring glyph (Liora's original medical emblem)
	b.torus(0.012, 0.016, _x(Vector3(0.05, 0.06, 0.0), Vector3(0, 0, 90)), sage, K.FLAT, 0.0, 12, 4)
	b.prism(Vector3(0.002, 0.016, 0.008), _x(Vector3(0.051, 0.06, 0.0)), sage)
	b.box(Vector3(0.03, 0.06, 0.04), _x(Vector3(0, -0.015, -0.3)), sage.darkened(0.35))
	_claw(b, Vector3(0, 0.11, -0.2), Vector3.ZERO, 0.022)
	_claw(b, Vector3(-0.04, 0.05, 0.16), Vector3(0, 0, 90), 0.016)
	b.cyl(0.04, 0.05, 0.03, _x(Vector3(0, 0.1, 0.03)), C_CHROME, K.CHROME, 0.0, 10)
	bp.at(&"root", "conduit").sphere(0.045, _x(Vector3(0, 0.14, 0.03)), Color.WHITE, K.FLAT, 0.0, 12)
	_sockets(bp, Vector3(0, 0.125, -0.2), Vector3(0, 0.055, -0.58), Vector3(-0.046, 0.05, 0.16), Vector3(0, 0.14, 0.03),
		Vector3(0, 0.055, -0.6), Vector3(0, -0.04, -0.3))


## Hex — chunky pistol-SMG; barrel = stack of offset hex rings that misalign.
static func _glitchcaster(bp: ModelBlueprint) -> void:
	var b := bp.at(&"root")
	var lime := ModelPalette.signature(&"hex")
	_grip(b, C_INK, 0.04, 0.13)
	b.box(Vector3(0.08, 0.12, 0.24), _x(Vector3(0, 0.055, -0.05)), C_INK, K.FLAT, 0.0, Vector2(0.9, 0.9))
	b.box(Vector3(0.084, 0.03, 0.16), _x(Vector3(0, 0.125, -0.02)), C_GUN_L)
	b.box(Vector3(0.05, 0.11, 0.06), _x(Vector3(0, -0.06, -0.12)), lime)  # chunky lime mag
	# stickers (story marks)
	b.box(Vector3(0.002, 0.03, 0.03), _x(Vector3(0.041, 0.07, -0.02), Vector3(0, 0, 0)), Color("#E255B5"))
	b.box(Vector3(0.002, 0.024, 0.036), _x(Vector3(0.041, 0.04, -0.09), Vector3(15, 0, 0)), Color("#34D8C4"))
	b.box(Vector3(0.002, 0.028, 0.028), _x(Vector3(0.041, 0.085, -0.13), Vector3(-10, 0, 0)), lime)
	_trim(b, Vector3(-0.041, 0.09, -0.05), Vector3(0.004, 0.006, 0.2))
	b.box(Vector3(0.034, 0.05, 0.05), _x(Vector3(0, -0.01, -0.2)), C_RUBBER)
	_claw(b, Vector3(0, 0.14, -0.08), Vector3.ZERO, 0.022)
	_claw(b, Vector3(-0.042, 0.055, 0.03), Vector3(0, 0, 90), 0.016)
	bp.at(&"root", "conduit").cyl(0.012, 0.012, 0.26, _x(Vector3(0, 0.06, -0.3), Vector3(90, 0, 0)), Color.WHITE, K.FLAT, 0.0, 6)
	for k in 4:
		var pn := StringName("ring%d" % k)
		bp.pivot(pn, &"root", Vector3(0.004 * (k % 2), 0.06 + 0.004 * ((k + 1) % 2), -0.2 - k * 0.055), Vector3(90, 0, 15.0 * k),
			[&"wobble_z", 3.0 + k, 0.18])
		bp.at(pn).torus(0.032, 0.05 - 0.003 * k, _x(Vector3.ZERO), C_GUN_L if k % 2 == 0 else lime, K.FLAT, 0.0, 6, 3)
	_sockets(bp, Vector3(0, 0.155, -0.08), Vector3(0, 0.06, -0.4), Vector3(-0.05, 0.055, 0.03), Vector3(0, 0.06, -0.3),
		Vector3(0, 0.06, -0.44), Vector3(0, -0.035, -0.2))


# ------------------------------------------------------------ Mechanical guns

## Juniper — lever-action rail-tack rifle, box magazine, tripwire spool.
static func _tackhammer(bp: ModelBlueprint) -> void:
	bp.data["mana"] = false
	var b := bp.at(&"root")
	var mustard := ModelPalette.signature(&"juniper")
	var olive := ModelPalette.secondary(&"juniper")
	_grip(b, olive.darkened(0.3))
	b.box(Vector3(0.066, 0.1, 0.34), _x(Vector3(0, 0.05, -0.08)), mustard)
	b.box(Vector3(0.07, 0.02, 0.3), _x(Vector3(0, 0.005, -0.08)), C_GUN)
	b.box(Vector3(0.052, 0.07, 0.26), _x(Vector3(0, 0.035, 0.19), Vector3(6, 0, 0)), olive, K.FLAT, 0.0, Vector2(1.0, 0.8))
	b.box(Vector3(0.058, 0.09, 0.02), _x(Vector3(0, 0.02, 0.32), Vector3(6, 0, 0)), C_RUBBER)
	# twin rails (rail-tack barrel) with coil rings
	for s in [-1.0, 1.0]:
		b.box(Vector3(0.012, 0.03, 0.5), _x(Vector3(0.018 * s, 0.06, -0.48)), C_CHROME, K.CHROME)
	for k in 4:
		b.box(Vector3(0.066, 0.05, 0.022), _x(Vector3(0, 0.06, -0.3 - k * 0.1)), C_GUN_L if k % 2 == 0 else olive)
	_trim(b, Vector3(0, 0.06, -0.48), Vector3(0.006, 0.006, 0.46))
	# lever loop
	b.torus(0.024, 0.032, _x(Vector3(0, -0.035, 0.02), Vector3(0, 0, 90), Vector3(1, 1.3, 1)), C_CHROME, K.CHROME, 0.0, 12, 4)
	# scope
	b.cyl(0.022, 0.022, 0.16, _x(Vector3(0, 0.135, 0.05), Vector3(90, 0, 0)), C_INK, K.FLAT, 0.0, 10)
	b.cyl(0.028, 0.028, 0.02, _x(Vector3(0, 0.135, -0.03), Vector3(90, 0, 0)), C_INK, K.FLAT, 0.0, 10)
	# tripwire spool on the left + wire along the frame
	b.cyl(0.045, 0.045, 0.024, _x(Vector3(-0.048, 0.03, 0.02), Vector3(0, 0, 90)), olive, K.FLAT, 0.0, 12)
	b.cyl(0.02, 0.02, 0.03, _x(Vector3(-0.05, 0.03, 0.02), Vector3(0, 0, 90)), C_CHROME, K.CHROME, 0.0, 8)
	b.box(Vector3(0.003, 0.003, 0.36), _x(Vector3(-0.04, 0.075, -0.17)), ModelPalette.secondary(&"ryker"))
	# stickers + "do not touch" hazard stripe
	b.box(Vector3(0.002, 0.03, 0.03), _x(Vector3(0.034, 0.06, -0.03), Vector3(20, 0, 0)), Color("#E255B5"))
	for k in 3:
		b.box(Vector3(0.002, 0.012, 0.026), _x(Vector3(0.027, 0.04, 0.13 + k * 0.04), Vector3(30, 0, 0)), C_INK)
	b.box(Vector3(0.03, 0.06, 0.04), _x(Vector3(0, -0.02, -0.28)), C_RUBBER)
	_chip_slot(b, Vector3(0, 0.106, -0.14))
	_chip_slot(b, Vector3(-0.034, 0.03, 0.17), Vector3(0, 0, 90))
	# box magazine with a team-lit window (Chamber)
	b.box(Vector3(0.04, 0.09, 0.07), _x(Vector3(0, -0.045, -0.13)), C_INK)
	bp.at(&"root", "conduit").box(Vector3(0.042, 0.05, 0.012), _x(Vector3(0, -0.045, -0.09)), Color.WHITE)
	_sockets(bp, Vector3(0, 0.115, -0.14), Vector3(0, 0.06, -0.74), Vector3(-0.04, 0.03, 0.17), Vector3(0, -0.045, -0.09),
		Vector3(0, 0.06, -0.75), Vector3(0, -0.04, -0.28))


## Ryker — bulky full-auto rifle, top rail, big receiver carrying the chip rack.
static func _breakline(bp: ModelBlueprint) -> void:
	bp.data["mana"] = false
	var b := bp.at(&"root")
	var olive := ModelPalette.signature(&"ryker")
	var bone := ModelPalette.secondary(&"ryker")
	_grip(b, C_RUBBER)
	b.box(Vector3(0.078, 0.13, 0.36), _x(Vector3(0, 0.05, -0.08)), olive)
	b.box(Vector3(0.08, 0.05, 0.2), _x(Vector3(0, 0.04, 0.0)), bone)
	for k in 9:  # top rail teeth
		b.box(Vector3(0.05, 0.012, 0.014), _x(Vector3(0, 0.122, -0.22 + k * 0.03)), C_GUN)
	b.box(Vector3(0.03, 0.006, 0.28), _x(Vector3(0, 0.118, -0.1)), C_GUN)
	b.box(Vector3(0.064, 0.072, 0.24), _x(Vector3(0, 0.05, -0.36)), C_GUN, K.FLAT, 0.0, Vector2(0.9, 1.0))
	b.cyl(0.016, 0.016, 0.2, _x(Vector3(0, 0.05, -0.56), Vector3(90, 0, 0)), C_INK, K.FLAT, 0.0, 8)
	b.box(Vector3(0.044, 0.044, 0.07), _x(Vector3(0, 0.05, -0.68)), C_GUN_L)
	for s in [-1.0, 1.0]:
		b.box(Vector3(0.004, 0.02, 0.012), _x(Vector3(0.023 * s, 0.05, -0.68)), C_INK)
	b.box(Vector3(0.052, 0.07, 0.24), _x(Vector3(0, 0.04, 0.2), Vector3(4, 0, 0)), C_GUN, K.FLAT, 0.0, Vector2(1.0, 0.7))
	b.box(Vector3(0.056, 0.1, 0.03), _x(Vector3(0, 0.03, 0.33), Vector3(4, 0, 0)), bone)
	_trim(b, Vector3(-0.04, 0.09, -0.08), Vector3(0.004, 0.006, 0.3))
	b.box(Vector3(0.002, 0.012, 0.06), _x(Vector3(0.04, 0.09, -0.02)), bone)  # scuffed unit serial
	b.box(Vector3(0.03, 0.07, 0.035), _x(Vector3(0, -0.03, -0.34), Vector3(8, 0, 0)), C_RUBBER)
	b.box(Vector3(0.044, 0.14, 0.07), _x(Vector3(0, -0.07, -0.15), Vector3(14, 0, 0)), C_INK)
	_chip_slot(b, Vector3(-0.044, 0.065, -0.15), Vector3(0, 0, 90))
	_chip_slot(b, Vector3(0, 0.13, -0.2))
	bp.at(&"root", "conduit").box(Vector3(0.046, 0.06, 0.012), _x(Vector3(0, -0.07, -0.11), Vector3(14, 0, 0)), Color.WHITE)
	_sockets(bp, Vector3(0, 0.135, -0.2), Vector3(0, 0.05, -0.72), Vector3(-0.05, 0.065, -0.15), Vector3(0, -0.07, -0.11),
		Vector3(0, 0.05, -0.73), Vector3(0, -0.05, -0.34))


## Brannoc — short, fat pump scattergun with a jaw-shaped muzzle.
static func _ironmaw(bp: ModelBlueprint) -> void:
	bp.data["mana"] = false
	bp.data["mount_scale"] = 1.15
	var b := bp.at(&"root")
	var teal := ModelPalette.signature(&"brannoc")
	var soot := ModelPalette.secondary(&"brannoc")
	_grip(b, C_RUBBER, 0.044, 0.13)
	b.box(Vector3(0.11, 0.13, 0.3), _x(Vector3(0, 0.06, -0.08)), teal)
	b.box(Vector3(0.114, 0.03, 0.3), _x(Vector3(0, 0.125, -0.08)), soot)
	for s in [-1.0, 1.0]:
		for k in 3:
			b.sphere(0.006, _x(Vector3(0.056 * s, 0.1, -0.2 + k * 0.1)), C_BRASS, K.METAL, 0.0, 6)
	b.cyl(0.045, 0.045, 0.26, _x(Vector3(0, 0.07, -0.34), Vector3(90, 0, 0)), C_GUN, K.FLAT, 0.0, 10)
	b.cyl(0.03, 0.03, 0.26, _x(Vector3(0, 0.0, -0.3), Vector3(90, 0, 0)), C_GUN_L, K.FLAT, 0.0, 8)
	# pump forend
	b.box(Vector3(0.08, 0.06, 0.14), _x(Vector3(0, 0.0, -0.3)), C_RUBBER)
	for k in 4:
		b.box(Vector3(0.084, 0.01, 0.012), _x(Vector3(0, 0.0, -0.36 + k * 0.04)), soot)
	# jaw muzzle: upper + lower jaw with teeth
	b.box(Vector3(0.13, 0.045, 0.12), _x(Vector3(0, 0.115, -0.5), Vector3(-8, 0, 0)), teal, K.FLAT, 0.0, Vector2(1.0, 0.7))
	b.box(Vector3(0.12, 0.04, 0.11), _x(Vector3(0, 0.02, -0.5), Vector3(10, 0, 0)), teal, K.FLAT, 0.0, Vector2(0.8, 1.0))
	for k in 4:
		var x := -0.045 + k * 0.03
		b.prism(Vector3(0.018, 0.028, 0.018), _x(Vector3(x, 0.083, -0.54), Vector3(180, 0, 0)), C_CHROME, K.CHROME)
		b.prism(Vector3(0.018, 0.024, 0.018), _x(Vector3(x, 0.048, -0.54)), C_CHROME, K.CHROME)
	b.box(Vector3(0.004, 0.006, 0.26), _x(Vector3(-0.057, 0.08, -0.08)), Color.WHITE, K.NEON, 0.9)
	# side-saddle shells (brass)
	for k in 4:
		b.cyl(0.011, 0.011, 0.05, _x(Vector3(0.062, 0.04, -0.17 + k * 0.03)), Color("#B33A2A"), K.FLAT, 0.0, 6)
		b.cyl(0.012, 0.012, 0.012, _x(Vector3(0.062, 0.012, -0.17 + k * 0.03)), C_BRASS, K.METAL, 0.0, 6)
	# stubby stock
	b.box(Vector3(0.07, 0.08, 0.16), _x(Vector3(0, 0.04, 0.14), Vector3(5, 0, 0)), soot, K.FLAT, 0.0, Vector2(1.0, 0.8))
	# charm (story mark)
	b.torus(0.008, 0.012, _x(Vector3(0.06, -0.02, 0.06), Vector3(0, 0, 90)), C_BRASS, K.METAL, 0.0, 8, 3)
	_chip_slot(b, Vector3(0, 0.145, -0.12))
	_chip_slot(b, Vector3(-0.058, 0.05, 0.0), Vector3(0, 0, 90))
	bp.at(&"root", "conduit").box(Vector3(0.012, 0.04, 0.12), _x(Vector3(-0.057, 0.045, -0.15)), Color.WHITE)
	_sockets(bp, Vector3(0, 0.15, -0.12), Vector3(0, 0.07, -0.58), Vector3(-0.064, 0.05, 0.0), Vector3(-0.058, 0.045, -0.15),
		Vector3(0, 0.07, -0.6), Vector3(0, -0.02, -0.3))
