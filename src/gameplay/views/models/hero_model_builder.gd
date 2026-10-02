class_name HeroModelBuilder
extends RefCounted
## Builds the 7 heroes as articulated stylised figures from shaped primitives
## (design/art-bible.md §3.3, §4.7, §5.1-5.2). ~7.5 heads tall, 3-5 flat zones:
## signature colour (<= 30%), faction trim (15-25%, value key via the team
## material), neutrals, one chrome cyberware piece, skin. Each hero has its
## silhouette hook, its cyberware and three story props. Blueprints (meshes)
## are built once per hero and shared by every instance and both teams.

const K := PartBuilder.Kind

static var _cache: Dictionary = {}


static func build(model_key: StringName, team: int) -> HeroModel:
	var m := HeroModel.new()
	m.build_from(blueprint(model_key), team)
	return m


static func blueprint(model_key: StringName) -> Dictionary:
	if _cache.has(model_key):
		return _cache[model_key]
	var bp := ModelBlueprint.new(model_key)
	match model_key:
		&"vesper":
			_vesper(bp)
		&"sable":
			_sable(bp)
		&"juniper":
			_juniper(bp)
		&"brannoc":
			_brannoc(bp)
		&"liora":
			_liora(bp)
		&"hex":
			_hex(bp)
		_:
			_ryker(bp)
	bp.data["weapon_key"] = ModelCatalog.HERO_WEAPON.get(model_key, &"breakline")
	var out := bp.finish()
	_cache[model_key] = out
	return out


static func _x(p: Vector3, r: Vector3 = Vector3.ZERO, s: Vector3 = Vector3.ONE) -> Transform3D:
	return PartBuilder.xf(p, r, s)


## Shared humanoid: pivots, proportions and base body. `o` keys (all optional):
## h, sw (shoulder half-width / H), hw (hip half-width / H), chest (depth / H),
## limb (limb thickness mult), torso/torso_k, belly/belly_k, legs/legs_k,
## boots/boots_k, sleeves/sleeves_k, gloves/gloves_k, skin, hair, head (scale),
## lean, crouch_base, aim (spine-space grip / H), stride, foot (mult).
static func _body(bp: ModelBlueprint, o: Dictionary) -> void:
	var h: float = o.get("h", 1.85)
	var thigh := 0.245 * h
	var shin := 0.215 * h
	var foot_h := 0.035 * h
	var L := thigh + shin + foot_h
	var sw: float = o.get("sw", 0.115) * h
	var hw: float = o.get("hw", 0.055) * h
	var depth: float = o.get("chest", 0.12) * h
	var lt: float = o.get("limb", 1.0) * 1.18
	var upper := 0.175 * h
	var fore := 0.19 * h
	bp.data["height"] = h
	bp.data["hips_y"] = L
	bp.data["thigh"] = thigh
	bp.data["shin"] = shin + foot_h * 0.5
	bp.data["upper_arm"] = upper
	bp.data["forearm"] = fore
	bp.data["lean"] = o.get("lean", 0.0)
	bp.data["crouch_base"] = o.get("crouch_base", 0.0)
	bp.data["stride"] = o.get("stride", 1.0) * h * 0.55
	var aim: Vector3 = o.get("aim", Vector3(0.04, 0.17, -0.13)) * h
	bp.data["aim_pos"] = aim
	bp.data["weapon_scale"] = o.get("weapon_scale", 1.2)
	bp.pivot(&"hips", &"root", Vector3(0, L, 0))
	bp.pivot(&"spine", &"hips", Vector3(0, 0.04 * h, 0))
	bp.pivot(&"head", &"spine", Vector3(0, 0.30 * h, 0))
	bp.pivot(&"aim", &"spine", aim)
	for s in [1.0, -1.0]:
		var side := "r" if s > 0.0 else "l"
		bp.pivot(StringName("arm_" + side), &"spine", Vector3(sw * s, 0.265 * h, 0))
		bp.pivot(StringName("fore_" + side), StringName("arm_" + side), Vector3(0, -upper, 0))
		bp.pivot(StringName("leg_" + side), &"hips", Vector3(hw * s, 0, 0))
		bp.pivot(StringName("shin_" + side), StringName("leg_" + side), Vector3(0, -thigh, 0))
	bp.marker(&"HAND_R_weapon", &"aim", Vector3.ZERO)
	bp.marker(&"HEAD_nameplate", &"head", Vector3(0, 0.22 * h, 0))
	bp.marker(&"BACK_attach", &"spine", Vector3(0, 0.2 * h, depth * 0.6))
	var skin: Color = o.get("skin", ModelPalette.SKIN_A)
	var torso: Color = o.get("torso", ModelPalette.GREY)
	var torso_k: int = o.get("torso_k", K.FLAT)
	var legs: Color = o.get("legs", ModelPalette.INK)
	var legs_k: int = o.get("legs_k", K.FLAT)
	# Pelvis + belly
	var hp := bp.at(&"hips")
	hp.box(Vector3(hw * 2.0 + 0.07 * h * lt, 0.08 * h, depth * 0.85), _x(Vector3(0, 0.0, 0)), o.get("belly", legs), o.get("belly_k", legs_k), 0.0, Vector2(1.08, 1.0))
	# Torso: V-taper box from waist to shoulders
	var sp := bp.at(&"spine")
	var waist_w := hw * 2.0 + 0.05 * h
	sp.box(Vector3(waist_w, 0.30 * h, depth), _x(Vector3(0, 0.15 * h, 0)), torso, torso_k, 0.0,
		Vector2((sw * 2.0 * 0.92) / waist_w, 1.12))
	sp.cyl(0.03 * h, 0.034 * h, 0.06 * h, _x(Vector3(0, 0.3 * h, 0)), skin, K.SKIN, 0.0, 8)
	# Head
	var hd := bp.at(&"head")
	var hs: float = o.get("head", 1.0)
	if not o.get("no_face", false):
		hd.sphere(0.068 * h * hs, _x(Vector3(0, 0.085 * h, 0), Vector3.ZERO, Vector3(0.92, 1.05, 1.0)), skin, K.SKIN, 0.0, 12)
		for s in [1.0, -1.0]:
			hd.box(Vector3(0.022 * h * hs, 0.026 * h * hs, 0.01), _x(Vector3(0.026 * h * hs * s, 0.088 * h, -0.063 * h * hs)), ModelPalette.INK)
			hd.box(Vector3(0.007 * h, 0.007 * h, 0.006), _x(Vector3((0.026 * h * hs + 0.004 * h) * s, 0.094 * h, -0.067 * h * hs)), Color.WHITE)
	# Arms
	var sleeves: Color = o.get("sleeves", torso)
	var sleeves_k: int = o.get("sleeves_k", torso_k)
	var gloves: Color = o.get("gloves", ModelPalette.RUBBER)
	var gloves_k: int = o.get("gloves_k", K.FLAT)
	for side in ["l", "r"]:
		var a := bp.at(StringName("arm_" + side))
		a.sphere(0.044 * h * lt, _x(Vector3(0, -0.01 * h, 0)), sleeves, sleeves_k, 0.0, 10)
		a.limb(0.034 * h * lt, 0.028 * h * lt, upper, Vector3.ZERO, sleeves, sleeves_k)
		var f := bp.at(StringName("fore_" + side))
		if not o.get("custom_fore_" + side, false):
			f.limb(0.028 * h * lt, 0.024 * h * lt, fore - 0.035 * h, Vector3.ZERO, sleeves, sleeves_k)
			f.box(Vector3(0.05 * h * lt, 0.07 * h, 0.034 * h * lt), _x(Vector3(0, -fore + 0.01 * h, 0)), gloves, gloves_k)
	# Legs
	var boots: Color = o.get("boots", ModelPalette.RUBBER)
	var boots_k: int = o.get("boots_k", K.FLAT)
	var fm: float = o.get("foot", 1.0)
	for side in ["l", "r"]:
		var lg := bp.at(StringName("leg_" + side))
		lg.limb(0.052 * h * lt, 0.04 * h * lt, thigh, Vector3.ZERO, legs, legs_k)
		var sh := bp.at(StringName("shin_" + side))
		sh.limb(0.038 * h * lt, 0.03 * h * lt, shin - 0.04 * h, Vector3.ZERO, legs, legs_k)
		sh.box(Vector3(0.075 * h * lt, 0.085 * h, 0.08 * h), _x(Vector3(0, -shin + 0.06 * h, 0.0)), boots, boots_k, 0.0, Vector2(0.9, 0.9))
		sh.box(Vector3(0.07 * h * fm, 0.045 * h, 0.15 * h * fm), _x(Vector3(0, -shin - 0.01 * h, -0.03 * h * fm)), boots, boots_k)


# ------------------------------------------------------------------- Vesper

## Minionmancer: tall, slender; long asymmetric plum coat with ribbon tails;
## the floating 4-spindle Loom halo; chrome thimble fingertips (cyberware).
static func _vesper(bp: ModelBlueprint) -> void:
	var h := 1.86
	var plum := ModelPalette.signature(&"vesper")
	var gold := ModelPalette.secondary(&"vesper")
	_body(bp, {"h": h, "sw": 0.118, "hw": 0.046, "chest": 0.1, "limb": 0.88, "torso": plum, "sleeves": plum,
		"legs": ModelPalette.INK, "boots": ModelPalette.INK, "boots_k": K.TRIM, "gloves": ModelPalette.INK,
		"skin": ModelPalette.SKIN_A, "belly": ModelPalette.INK, "belly_k": K.TRIM, "stride": 1.05})
	var sp := bp.at(&"spine")
	# High wide collar (inverted triangle) + corseted waist (faction trim)
	sp.box(Vector3(0.36, 0.13, 0.22), _x(Vector3(0, 0.56, 0.0)), plum, K.FLAT, 0.0, Vector2(1.35, 1.2))
	sp.box(Vector3(0.38, 0.03, 0.24), _x(Vector3(0, 0.63, 0.0)), Color.WHITE, K.TRIM, 0.0, Vector2(1.35, 1.2))
	sp.box(Vector3(0.21, 0.14, 0.175), _x(Vector3(0, 0.08, 0)), Color.WHITE, K.TRIM, 0.0, Vector2(1.15, 1.0))
	sp.box(Vector3(0.215, 0.012, 0.18), _x(Vector3(0, 0.16, 0)), Color.WHITE, K.NEON, 0.8)
	for k in 3:  # corset lacing (gold thread)
		sp.box(Vector3(0.06, 0.006, 0.004), _x(Vector3(0, 0.04 + k * 0.035, -0.09)), gold, K.METAL)
	# Coat body over the chest: open front lapels
	for s in [1.0, -1.0]:
		sp.box(Vector3(0.07, 0.34, 0.03), _x(Vector3(0.07 * s, 0.33, -0.1), Vector3(0, 0, -10 * s)), plum.darkened(0.15))
		sp.box(Vector3(0.11, 0.06, 0.14), _x(Vector3(0.2 * s, 0.5, 0)), plum, K.FLAT, 0.0, Vector2(0.8, 1.0))
	# Coat skirt: asymmetric — short on the left, long on the right, ribbon tails behind
	var hp := bp.at(&"hips")
	hp.box(Vector3(0.24, 0.42, 0.06), _x(Vector3(0.1, -0.2, 0.06), Vector3(0, 0, 6)), plum, K.FLAT, 0.0, Vector2(0.85, 1.0))
	hp.box(Vector3(0.2, 0.2, 0.06), _x(Vector3(-0.1, -0.08, 0.06), Vector3(0, 0, -6)), plum, K.FLAT, 0.0, Vector2(0.85, 1.0))
	hp.box(Vector3(0.12, 0.5, 0.04), _x(Vector3(0.15, -0.24, -0.06), Vector3(0, 0, 4)), plum.darkened(0.1))
	for k in 3:
		var tail := StringName("tail%d" % k)
		bp.pivot(tail, &"hips", Vector3(-0.08 + k * 0.08, 0.02, 0.11), Vector3(12, 0, 0), [&"sway", 2.4 + k * 0.4, 0.5])
		var tb := bp.at(tail)
		var ln := 0.62 + 0.12 * k
		tb.box(Vector3(0.07, ln, 0.012), _x(Vector3(0, -ln * 0.5, 0)), plum, K.FLAT, 0.0, Vector2(1.3, 1.0))
		tb.box(Vector3(0.071, 0.02, 0.014), _x(Vector3(0, -ln + 0.01, 0)), gold, K.METAL)
		for t in 2:  # lining name-tags (story prop: one per rebuilt Wardling)
			tb.box(Vector3(0.016, 0.022, 0.004), _x(Vector3(-0.015 + t * 0.03, -0.15 - t * 0.12, -0.009)), ModelPalette.SYNDICATE_BRASS, K.METAL)
	# Head: sharp bob + long gold-wrapped braid
	var hd := bp.at(&"head")
	hd.sphere(0.135, _x(Vector3(0, 0.175, 0.012), Vector3.ZERO, Vector3(1.0, 0.82, 1.02)), ModelPalette.INK)
	hd.box(Vector3(0.25, 0.1, 0.22), _x(Vector3(0, 0.12, 0.02)), ModelPalette.INK, K.FLAT, 0.0, Vector2(1.1, 1.1))
	hd.box(Vector3(0.2, 0.05, 0.03), _x(Vector3(0, 0.215, -0.11), Vector3(-20, 0, 0)), ModelPalette.INK)
	bp.pivot(&"braid", &"head", Vector3(0.08, 0.1, 0.08), Vector3(14, 0, -8), [&"sway", 2.0, 0.3])
	var br := bp.at(&"braid")
	br.cyl(0.022, 0.016, 0.62, _x(Vector3(0, -0.31, 0)), ModelPalette.INK, K.FLAT, 0.0, 6)
	for k in 4:
		br.cyl(0.026, 0.026, 0.025, _x(Vector3(0, -0.08 - k * 0.15, 0)), gold, K.METAL, 0.0, 6)
	# Cyberware: chrome thimble fingertips (both hands) + spool on the belt (prop)
	for side in ["l", "r"]:
		var f := bp.at(StringName("fore_" + side))
		for k in 3:
			f.cyl(0.008, 0.011, 0.035, _x(Vector3(-0.018 + k * 0.018, -0.36, -0.006)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 6)
		f.box(Vector3(0.056, 0.006, 0.04), _x(Vector3(0, -0.31, 0)), Color.WHITE, K.NEON, 0.7)
	hp.cyl(0.035, 0.035, 0.05, _x(Vector3(-0.13, -0.02, -0.06), Vector3(0, 0, 90)), gold, K.METAL, 0.0, 8)
	hp.cyl(0.026, 0.026, 0.052, _x(Vector3(-0.13, -0.02, -0.06), Vector3(0, 0, 90)), ModelPalette.AETHER_VIOLET, K.GLOW, 0.6, 8)
	# Hook: the Loom halo — spine rig + 4 chrome spindle arms in a semicircle,
	# violet crystals in claw sockets, linked by glowing threads.
	sp.box(Vector3(0.05, 0.42, 0.04), _x(Vector3(0, 0.36, 0.11)), ModelPalette.CHROME_COOL, K.CHROME)
	sp.box(Vector3(0.006, 0.4, 0.006), _x(Vector3(0, 0.36, 0.132)), Color.WHITE, K.NEON, 0.8)
	bp.pivot(&"halo", &"spine", Vector3(0, 0.6, 0.2), Vector3.ZERO, [&"bob", 1.6, 0.025])
	var hb := bp.at(&"halo")
	var vi := ModelPalette.LEYFALL_VIOLET
	var cr := bp.at(&"halo", "mana:%s:1.8" % vi.to_html(false))
	for k in 4:
		var a := deg_to_rad(-75.0 + 50.0 * k)
		var tip := Vector3(sin(a) * 0.5, cos(a) * 0.42 + 0.08, 0.06)
		var root := Vector3(sin(a) * 0.12, cos(a) * 0.1, 0.0)
		var mid := (tip + root) * 0.5
		var ln := (tip - root).length()
		var rz := -rad_to_deg(atan2(tip.x - root.x, tip.y - root.y))
		hb.box(Vector3(0.026, ln, 0.026), _x(mid, Vector3(0, 0, rz)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, Vector2(0.5, 0.5))
		hb.cyl(0.03, 0.03, 0.02, _x(tip - Vector3(sin(a), cos(a), 0) * 0.04, Vector3(0, 0, rz)), ModelPalette.SYNDICATE_BRASS, K.METAL, 0.0, 8)
		for c in 3:  # claw prongs
			var ca := TAU * c / 3.0
			hb.box(Vector3(0.008, 0.06, 0.008), _x(tip + Basis.from_euler(Vector3(0, 0, deg_to_rad(rz))) * Vector3(cos(ca) * 0.03, -0.01, sin(ca) * 0.03), Vector3(0, 0, rz)), ModelPalette.CHROME_COOL, K.CHROME)
		cr.sphere(0.045, _x(tip + Vector3(sin(a), cos(a), 0) * 0.025, Vector3(0, 0, rz), Vector3(0.75, 1.6, 0.75)), Color.WHITE, K.FLAT, 0.0, 6)
	hb.sphere(0.06, _x(Vector3(0, 0.0, -0.02)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 10)
	var th := bp.at(&"halo", "holo:%s" % gold.to_html(false))
	for k in 3:  # glowing threads between spindle tips
		var a0 := deg_to_rad(-75.0 + 50.0 * k)
		var a1 := deg_to_rad(-75.0 + 50.0 * (k + 1))
		var p0 := Vector3(sin(a0) * 0.5, cos(a0) * 0.42 + 0.08, 0.06)
		var p1 := Vector3(sin(a1) * 0.5, cos(a1) * 0.42 + 0.08, 0.06)
		th.box(Vector3(0.008, (p1 - p0).length(), 0.008), _x((p0 + p1) * 0.5, Vector3(0, 0, -rad_to_deg(atan2(p1.x - p0.x, p1.y - p0.y)))), Color.WHITE)


# -------------------------------------------------------------------- Sable

## Infiltrator: smallest (1.70 m), forward-leaning crouch-ready; long split
## scarf trailing 1.5 m, single swept-back hood horn, slit visor; chrome calf
## struts (cyberware) with jade hinges.
static func _sable(bp: ModelBlueprint) -> void:
	var h := 1.70
	var ink := ModelPalette.signature(&"sable")
	var jade := ModelPalette.secondary(&"sable")
	_body(bp, {"h": h, "sw": 0.105, "hw": 0.048, "chest": 0.1, "limb": 0.85, "torso": ink, "sleeves": ink,
		"legs": ink.lightened(0.05), "boots": ModelPalette.INK, "gloves": Color.WHITE, "gloves_k": K.TRIM,
		"skin": ModelPalette.SKIN_C, "lean": -0.32, "crouch_base": 0.28, "stride": 0.9,
		"aim": Vector3(0.03, 0.16, -0.15)})
	var sp := bp.at(&"spine")
	sp.box(Vector3(0.26, 0.16, 0.18), _x(Vector3(0, 0.36, -0.005)), Color.WHITE, K.TRIM, 0.0, Vector2(1.1, 1.0))
	sp.box(Vector3(0.18, 0.012, 0.172), _x(Vector3(0, 0.12, 0)), jade, K.GLOW, 0.5)
	sp.box(Vector3(0.24, 0.05, 0.16), _x(Vector3(0, 0.03, 0)), ModelPalette.INK)
	# courier satchel (prop) across the back
	sp.box(Vector3(0.18, 0.13, 0.07), _x(Vector3(0.04, 0.22, 0.11), Vector3(0, 0, 12)), ModelPalette.GREY)
	sp.box(Vector3(0.02, 0.38, 0.012), _x(Vector3(0.0, 0.3, -0.09), Vector3(0, 0, 35)), ModelPalette.RUBBER)
	# Head: hood + single swept-back horn + matte half-mask with slit visor
	var hd := bp.at(&"head")
	hd.sphere(0.13, _x(Vector3(0, 0.17, 0.02), Vector3.ZERO, Vector3(1.0, 1.0, 1.1)), ink)
	hd.box(Vector3(0.18, 0.1, 0.06), _x(Vector3(0, 0.12, -0.085)), ModelPalette.RUBBER, K.FLAT, 0.0, Vector2(0.8, 1.0))
	hd.box(Vector3(0.15, 0.014, 0.02), _x(Vector3(0, 0.15, -0.11)), Color.WHITE, K.NEON, 1.0)
	hd.prism(Vector3(0.075, 0.52, 0.09), _x(Vector3(0.08, 0.34, 0.16), Vector3(-58, 0, -18)), ink, K.FLAT, 0.0, 0.2)
	hd.box(Vector3(0.012, 0.3, 0.012), _x(Vector3(0.09, 0.35, 0.15), Vector3(-58, 0, -18)), jade, K.GLOW, 0.6)
	# Hook: split scarf, two tails trailing ~1.5 m behind (phase-weave, patched
	# with banner scraps from both factions — the trophies).
	for k in 2:
		var s := 1.0 if k == 0 else -1.0
		var tail := StringName("scarf%d" % k)
		bp.pivot(tail, &"spine", Vector3(0.05 * s, 0.31, 0.08), Vector3(-32 + 8 * k, 10 * s, 0), [&"sway", 3.0 + k, 0.8])
		var tb := bp.at(tail)
		var ln := 1.45 - 0.2 * k
		tb.box(Vector3(0.15, ln, 0.014), _x(Vector3(0, -ln * 0.5, 0)), ink.lightened(0.1), K.FLAT, 0.0, Vector2(0.75, 1.0))
		tb.box(Vector3(0.152, ln * 0.96, 0.004), _x(Vector3(0, -ln * 0.5, 0.01)), jade, K.FLAT, 0.0, Vector2(0.75, 1.0))
		tb.box(Vector3(0.06, 0.08, 0.016), _x(Vector3(0.02, -0.45, 0)), ModelPalette.AZURE_LIGHT if k == 0 else ModelPalette.SYNDICATE_IRON)
		tb.box(Vector3(0.05, 0.06, 0.016), _x(Vector3(-0.02, -0.8, 0)), ModelPalette.EMBER_DARK if k == 0 else ModelPalette.CONCORD_GOLD)
		tb.box(Vector3(0.112, 0.03, 0.014), _x(Vector3(0, -ln + 0.015, 0)), Color.WHITE, K.NEON, 0.8)
	sp.torus(0.06, 0.1, _x(Vector3(0, 0.31, 0.0), Vector3(0, 0, 0), Vector3(1, 0.7, 1)), ink.lightened(0.08), K.FLAT, 0.0, 12, 6)
	# Cyberware: chrome calf struts with a jade-lit ankle hinge
	for side in ["l", "r"]:
		var sh := bp.at(StringName("shin_" + side))
		sh.box(Vector3(0.02, 0.3, 0.02), _x(Vector3(0, -0.18, 0.05)), ModelPalette.CHROME_COOL, K.CHROME)
		sh.box(Vector3(0.016, 0.24, 0.016), _x(Vector3(0, -0.2, 0.075), Vector3(-8, 0, 0)), ModelPalette.CHROME_COOL, K.CHROME)
		sh.cyl(0.026, 0.026, 0.07, _x(Vector3(0, -0.34, 0.05), Vector3(0, 0, 90)), jade, K.GLOW, 0.8, 8)
		var lg := bp.at(StringName("leg_" + side))
		lg.box(Vector3(0.11, 0.12, 0.11), _x(Vector3(0, -0.05, 0)), Color.WHITE, K.TRIM, 0.0, Vector2(0.9, 0.9))
	# chalk tally marks on the left bracer (prop)
	var fl := bp.at(&"fore_l")
	fl.box(Vector3(0.056, 0.1, 0.05), _x(Vector3(0, -0.12, 0)), Color.WHITE, K.TRIM)
	for k in 4:
		fl.box(Vector3(0.004, 0.05, 0.004), _x(Vector3(-0.012 + k * 0.008, -0.12, -0.027)), jade, K.GLOW, 0.4)


# ------------------------------------------------------------------ Juniper

## Trapper: medium build under a huge square mustard tool-pack taller than
## her head; chrome multi-tool prosthetic LEFT forearm (cyberware).
static func _juniper(bp: ModelBlueprint) -> void:
	var h := 1.74
	var mustard := ModelPalette.signature(&"juniper")
	var olive := ModelPalette.secondary(&"juniper")
	_body(bp, {"h": h, "sw": 0.11, "hw": 0.052, "chest": 0.11, "torso": olive, "sleeves": olive.darkened(0.1),
		"legs": olive.darkened(0.25), "boots": ModelPalette.RUBBER, "boots_k": K.TRIM, "gloves": ModelPalette.GREY,
		"skin": ModelPalette.SKIN_B, "custom_fore_l": true, "belly": olive.darkened(0.3), "stride": 0.95})
	var sp := bp.at(&"spine")
	sp.box(Vector3(0.3, 0.18, 0.2), _x(Vector3(0, 0.36, -0.01)), Color.WHITE, K.TRIM, 0.0, Vector2(1.05, 1.0))
	sp.box(Vector3(0.024, 0.4, 0.02), _x(Vector3(0.08, 0.3, -0.105)), ModelPalette.RUBBER)
	sp.box(Vector3(0.024, 0.4, 0.02), _x(Vector3(-0.08, 0.3, -0.105)), ModelPalette.RUBBER)
	# Hook: the tool-pack (salvaged pump housing), top well above the head
	sp.box(Vector3(0.6, 0.98, 0.42), _x(Vector3(0, 0.56, 0.32)), mustard)
	sp.box(Vector3(0.62, 0.06, 0.44), _x(Vector3(0, 1.06, 0.32)), ModelPalette.GREY)
	sp.box(Vector3(0.62, 0.04, 0.44), _x(Vector3(0, 0.1, 0.32)), ModelPalette.GREY)
	for k in 5:  # "do not touch" hazard stripe
		sp.box(Vector3(0.05, 0.12, 0.006), _x(Vector3(-0.2 + k * 0.1, 0.85, 0.534), Vector3(0, 0, 30)), ModelPalette.INK)
	sp.box(Vector3(0.006, 0.08, 0.1), _x(Vector3(0.302, 0.75, 0.35), Vector3(14, 0, 0)), Color("#E255B5"))  # sticker
	sp.box(Vector3(0.006, 0.07, 0.07), _x(Vector3(0.302, 0.55, 0.22), Vector3(-10, 0, 0)), Color("#34D8C4"))
	sp.box(Vector3(0.14, 0.06, 0.006), _x(Vector3(0.12, 0.4, 0.534)), ModelPalette.AZURE_LIGHT)  # hand-written label
	sp.box(Vector3(0.5, 0.01, 0.006), _x(Vector3(0, 0.98, 0.534)), Color.WHITE, K.NEON, 0.8)
	# cable spool wheel (right side) + folded mine-launcher arm (left side)
	sp.cyl(0.17, 0.17, 0.06, _x(Vector3(0.33, 0.5, 0.3), Vector3(0, 0, 90)), olive, K.FLAT, 0.0, 14)
	sp.cyl(0.07, 0.07, 0.08, _x(Vector3(0.34, 0.5, 0.3), Vector3(0, 0, 90)), ModelPalette.CHROME_WARM, K.CHROME, 0.0, 10)
	sp.box(Vector3(0.08, 0.5, 0.1), _x(Vector3(-0.34, 0.62, 0.36), Vector3(0, 0, -6)), ModelPalette.GUNMETAL)
	sp.box(Vector3(0.1, 0.14, 0.14), _x(Vector3(-0.35, 0.9, 0.36)), ModelPalette.GUNMETAL)
	sp.cyl(0.04, 0.04, 0.12, _x(Vector3(-0.35, 0.98, 0.28), Vector3(-90, 0, 0)), ModelPalette.INK, K.FLAT, 0.0, 8)
	# utility belt of trap canisters, each with a stripe (props)
	var hp := bp.at(&"hips")
	hp.box(Vector3(0.3, 0.04, 0.2), _x(Vector3(0, 0.03, 0)), ModelPalette.RUBBER)
	var stripes := [Color("#E255B5"), Color("#34D8C4"), ModelPalette.AZURE_LIGHT, mustard]
	for k in 4:
		var a := deg_to_rad(-60.0 + 40.0 * k)
		var p := Vector3(sin(a) * 0.16, 0.0, -cos(a) * 0.11)
		hp.cyl(0.026, 0.026, 0.08, _x(p), ModelPalette.GUNMETAL, K.FLAT, 0.0, 8)
		hp.cyl(0.027, 0.027, 0.015, _x(p + Vector3(0, 0.015, 0)), stripes[k], K.FLAT, 0.0, 8)
	# Head: messy bun with quill-darts + brass goggles pushed up
	var hd := bp.at(&"head")
	hd.sphere(0.13, _x(Vector3(0, 0.165, 0.015), Vector3.ZERO, Vector3(1.04, 0.86, 1.04)), Color("#7A3E22"))
	hd.sphere(0.07, _x(Vector3(0, 0.27, 0.07)), Color("#7A3E22"), K.FLAT, 0.0, 8)
	for k in 3:
		hd.cyl(0.006, 0.006, 0.18, _x(Vector3(-0.03 + k * 0.03, 0.31, 0.07), Vector3(-30 + 25 * k, 0, 20 - 20 * k)), ModelPalette.INK, K.FLAT, 0.0, 4)
	hd.box(Vector3(0.24, 0.03, 0.2), _x(Vector3(0, 0.205, -0.0), Vector3(-15, 0, 0)), ModelPalette.RUBBER)
	for s in [1.0, -1.0]:
		hd.cyl(0.035, 0.035, 0.03, _x(Vector3(0.045 * s, 0.22, -0.1), Vector3(-75, 0, 0)), ModelPalette.SYNDICATE_BRASS, K.METAL, 0.0, 10)
	hd.cyl(0.026, 0.026, 0.032, _x(Vector3(0.045, 0.22, -0.1), Vector3(-75, 0, 0)), Color("#34D8C4"), K.GLOW, 0.5, 10)  # cracked holo-lens
	# Cyberware: chrome multi-tool prosthetic LEFT forearm, fold-out pliers finger, neon "for luck"
	var fl := bp.at(&"fore_l")
	fl.limb(0.03, 0.026, 0.27, Vector3.ZERO, ModelPalette.CHROME_COOL, K.CHROME)
	fl.box(Vector3(0.075, 0.075, 0.05), _x(Vector3(0, -0.31, 0)), ModelPalette.CHROME_COOL, K.CHROME)
	fl.box(Vector3(0.012, 0.07, 0.012), _x(Vector3(0.02, -0.36, -0.02), Vector3(20, 0, 10)), ModelPalette.CHROME_WARM, K.CHROME)
	fl.box(Vector3(0.012, 0.07, 0.012), _x(Vector3(-0.02, -0.36, -0.02), Vector3(20, 0, -10)), ModelPalette.CHROME_WARM, K.CHROME)
	fl.torus(0.03, 0.036, _x(Vector3(0, -0.12, 0)), Color.WHITE, K.NEON, 0.8, 12, 4)


# -------------------------------------------------------------------- Ryker

## Soldier: upright V-taper baseline; oversized LEFT pauldron with a rising
## antenna fin and kill-tally tape; visor-bar helmet; chrome stim-port RIGHT
## forearm (cyberware); grenade bandolier.
static func _ryker(bp: ModelBlueprint) -> void:
	var h := 1.86
	var olive := ModelPalette.signature(&"ryker")
	var bone := ModelPalette.secondary(&"ryker")
	_body(bp, {"h": h, "sw": 0.125, "hw": 0.056, "chest": 0.125, "torso": olive, "sleeves": olive.darkened(0.15),
		"legs": olive.darkened(0.3), "legs_k": K.FLAT, "boots": Color.WHITE, "boots_k": K.TRIM, "gloves": ModelPalette.RUBBER,
		"custom_fore_r": true, "no_face": true, "belly": olive.darkened(0.35)})
	var sp := bp.at(&"spine")
	sp.box(Vector3(0.38, 0.22, 0.25), _x(Vector3(0, 0.39, -0.01)), Color.WHITE, K.TRIM, 0.0, Vector2(1.08, 1.0))
	sp.box(Vector3(0.2, 0.08, 0.02), _x(Vector3(0.02, 0.36, -0.14)), bone)  # unit patch
	sp.box(Vector3(0.3, 0.18, 0.12), _x(Vector3(0, 0.3, 0.15)), olive.darkened(0.2))  # back pack
	# grenade bandolier, diagonal across the chest
	sp.box(Vector3(0.05, 0.5, 0.02), _x(Vector3(0.0, 0.3, -0.135), Vector3(0, 0, -38)), ModelPalette.RUBBER)
	for k in 4:
		var t := -0.15 + k * 0.1
		sp.sphere(0.03, _x(Vector3(t * 0.62, 0.3 + t * 0.79, -0.155)), olive.lightened(0.15), K.FLAT, 0.0, 8)
	# Helmet with a horizontal visor bar
	var hd := bp.at(&"head")
	hd.sphere(0.14, _x(Vector3(0, 0.15, 0.0), Vector3.ZERO, Vector3(0.95, 1.02, 1.05)), Color.WHITE, K.TRIM, 0.0, 12)
	hd.box(Vector3(0.22, 0.08, 0.16), _x(Vector3(0, 0.08, -0.04)), olive.darkened(0.2), K.FLAT, 0.0, Vector2(1.1, 1.0))
	hd.box(Vector3(0.24, 0.036, 0.05), _x(Vector3(0, 0.16, -0.12)), ModelPalette.INK)
	hd.box(Vector3(0.21, 0.02, 0.02), _x(Vector3(0, 0.16, -0.145)), Color.WHITE, K.NEON, 1.0)
	# dog tags (prop)
	sp.box(Vector3(0.02, 0.03, 0.004), _x(Vector3(0.03, 0.47, -0.14)), ModelPalette.CHROME_COOL, K.CHROME)
	# Hook: oversized LEFT pauldron + antenna fin + kill-tally tape
	var al := bp.at(&"arm_l")
	al.box(Vector3(0.36, 0.22, 0.36), _x(Vector3(-0.08, 0.05, 0), Vector3(0, 0, 16)), Color.WHITE, K.TRIM, 0.0, Vector2(0.65, 0.8))
	al.box(Vector3(0.38, 0.06, 0.38), _x(Vector3(-0.1, -0.07, 0), Vector3(0, 0, 16)), olive)
	al.box(Vector3(0.025, 0.46, 0.09), _x(Vector3(-0.13, 0.36, 0.05), Vector3(-10, 0, 12)), ModelPalette.GUNMETAL, K.FLAT, 0.0, Vector2(1.0, 0.35))
	al.cyl(0.011, 0.011, 0.7, _x(Vector3(-0.16, 0.5, 0.1), Vector3(-8, 0, 12)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 5)
	al.sphere(0.02, _x(Vector3(-0.23, 0.84, 0.15)), Color.WHITE, K.NEON, 1.0, 6)
	al.box(Vector3(0.28, 0.045, 0.004), _x(Vector3(-0.09, 0.04, -0.182), Vector3(0, 0, 16)), bone)
	for k in 6:
		al.box(Vector3(0.005, 0.03, 0.004), _x(Vector3(-0.19 + k * 0.035, 0.012 + k * 0.01, -0.185), Vector3(0, 0, 16)), ModelPalette.INK)
	bp.at(&"arm_r").box(Vector3(0.12, 0.09, 0.14), _x(Vector3(0.02, 0.0, 0)), Color.WHITE, K.TRIM, 0.0, Vector2(0.8, 0.9))
	# Cyberware: chrome RIGHT forearm with a stim port and its neon ring
	var fr := bp.at(&"fore_r")
	fr.limb(0.05, 0.044, 0.3, Vector3.ZERO, ModelPalette.CHROME_COOL, K.CHROME)
	fr.box(Vector3(0.09, 0.13, 0.065), _x(Vector3(0, -0.34, 0)), ModelPalette.RUBBER)
	fr.torus(0.022, 0.032, _x(Vector3(0.0, -0.13, -0.045), Vector3(90, 0, 0)), Color.WHITE, K.NEON, 1.0, 12, 4)
	fr.box(Vector3(0.06, 0.006, 0.07), _x(Vector3(0, -0.22, 0)), ModelPalette.GUNMETAL)


# ------------------------------------------------------------------ Brannoc

## Tank: 2.2 m slab, small head sunk between huge square shoulders; RIGHT arm
## shield generator with charms; chest furnace-heart glowing behind a grille
## (cyberware) and a back vent.
static func _brannoc(bp: ModelBlueprint) -> void:
	var h := 2.2
	var teal := ModelPalette.signature(&"brannoc")
	var soot := ModelPalette.secondary(&"brannoc")
	_body(bp, {"h": h, "sw": 0.15, "hw": 0.07, "chest": 0.17, "limb": 1.45, "torso": teal, "sleeves": soot,
		"legs": soot, "boots": teal, "boots_k": K.FLAT, "gloves": Color.WHITE, "gloves_k": K.TRIM, "head": 0.9,
		"skin": ModelPalette.SKIN_B, "belly": Color.WHITE, "belly_k": K.TRIM, "stride": 1.15, "foot": 1.15,
		"custom_fore_r": true, "aim": Vector3(0.12, 0.05, -0.11)})
	var sp := bp.at(&"spine")
	# slab chest plate + huge square shoulders
	sp.box(Vector3(0.6, 0.38, 0.4), _x(Vector3(0, 0.44, -0.01)), teal, K.FLAT, 0.0, Vector2(1.12, 1.0))
	sp.box(Vector3(0.62, 0.04, 0.42), _x(Vector3(0, 0.25, -0.01)), Color.WHITE, K.TRIM)
	for s in [1.0, -1.0]:
		sp.box(Vector3(0.3, 0.26, 0.42), _x(Vector3(0.36 * s, 0.6, 0)), teal, K.FLAT, 0.0, Vector2(0.88, 0.9))
		sp.box(Vector3(0.31, 0.04, 0.43), _x(Vector3(0.36 * s, 0.47, 0)), Color.WHITE, K.TRIM)
		sp.box(Vector3(0.05, 0.27, 0.43), _x(Vector3(0.5 * s, 0.6, 0)), Color.WHITE, K.TRIM, 0.0, Vector2(1.0, 0.9))
	# Cyberware hook: furnace-heart behind a chest grille
	bp.at(&"spine", "mana_team").sphere(0.1, _x(Vector3(0, 0.46, -0.2), Vector3.ZERO, Vector3(1.2, 1.0, 0.6)), Color.WHITE, K.FLAT, 0.0, 10)
	sp.box(Vector3(0.3, 0.24, 0.03), _x(Vector3(0, 0.46, -0.205)), ModelPalette.GUNMETAL, K.FLAT, 0.0, Vector2(1.0, 1.0))
	bp.at(&"spine", "mana_team").box(Vector3(0.26, 0.2, 0.01), _x(Vector3(0, 0.46, -0.222)), Color.WHITE)
	for k in 5:
		sp.box(Vector3(0.28, 0.018, 0.03), _x(Vector3(0, 0.37 + k * 0.045, -0.235)), ModelPalette.CHROME_WARM, K.CHROME)
	# back vent breathing heat
	sp.box(Vector3(0.36, 0.3, 0.12), _x(Vector3(0, 0.46, 0.24)), soot)
	for k in 3:
		sp.cyl(0.05, 0.05, 0.18, _x(Vector3(-0.1 + k * 0.1, 0.66, 0.26)), ModelPalette.GUNMETAL, K.FLAT, 0.0, 8)
		sp.cyl(0.035, 0.035, 0.01, _x(Vector3(-0.1 + k * 0.1, 0.755, 0.26)), Color.WHITE, K.SIGNAL, 1.2, 8)
	# Small head sunk between the shoulders: helmet ridge + miner's headlamp (prop)
	var hd := bp.at(&"head")
	hd.box(Vector3(0.24, 0.12, 0.24), _x(Vector3(0, 0.15, 0.01)), soot, K.FLAT, 0.0, Vector2(0.9, 0.9))
	hd.box(Vector3(0.26, 0.05, 0.08), _x(Vector3(0, 0.08, -0.08)), teal)
	hd.cyl(0.03, 0.035, 0.04, _x(Vector3(0, 0.19, -0.12), Vector3(-90, 0, 0)), ModelPalette.SYNDICATE_BRASS, K.METAL, 0.0, 8)
	hd.cyl(0.024, 0.024, 0.01, _x(Vector3(0, 0.19, -0.142), Vector3(-90, 0, 0)), Color("#FFF3C8"), K.GLOW, 0.9, 8)
	# Hook: RIGHT arm shield generator (slab emitter) with charms on the rim
	var fr := bp.at(&"fore_r")
	fr.limb(0.07, 0.065, 0.3, Vector3.ZERO, soot)
	fr.box(Vector3(0.1, 0.12, 0.08), _x(Vector3(0, -0.4, 0)), Color.WHITE, K.TRIM)
	# slab emitter standing on the OUTER side of the forearm: a vertical wall
	# along the arm (local Y = arm, local Z = elbow-out/down pole).
	fr.box(Vector3(0.12, 0.56, 0.46), _x(Vector3(0.12, -0.2, 0.0)), teal)
	fr.box(Vector3(0.13, 0.58, 0.03), _x(Vector3(0.12, -0.2, -0.23)), Color.WHITE, K.TRIM)
	fr.box(Vector3(0.13, 0.58, 0.03), _x(Vector3(0.12, -0.2, 0.23)), Color.WHITE, K.TRIM)
	fr.box(Vector3(0.13, 0.03, 0.48), _x(Vector3(0.12, 0.08, 0.0)), Color.WHITE, K.TRIM)
	fr.box(Vector3(0.012, 0.38, 0.3), _x(Vector3(0.186, -0.2, 0.0)), ModelPalette.GUNMETAL)
	fr.box(Vector3(0.014, 0.3, 0.012), _x(Vector3(0.19, -0.2, 0.0)), Color.WHITE, K.NEON, 0.9)
	fr.box(Vector3(0.014, 0.012, 0.22), _x(Vector3(0.19, -0.2, 0.0)), Color.WHITE, K.NEON, 0.9)
	var charm_cols := [ModelPalette.CONCORD_GOLD, Color("#E255B5"), ModelPalette.AZURE_LIGHT]
	for k in 3:  # charms / tags from people he has shielded (props)
		fr.box(Vector3(0.003, 0.003, 0.08), _x(Vector3(0.19, -0.42 + k * 0.1, 0.27)), ModelPalette.INK)
		fr.box(Vector3(0.012, 0.03, 0.04), _x(Vector3(0.19, -0.42 + k * 0.1, 0.32)), charm_cols[k])
	# riveted crew tag on the belly plate (prop)
	bp.at(&"hips").box(Vector3(0.1, 0.06, 0.01), _x(Vector3(0.1, 0.0, -0.19)), ModelPalette.SYNDICATE_BRASS, K.METAL)
	for side in ["l", "r"]:
		bp.at(StringName("leg_" + side)).box(Vector3(0.2, 0.26, 0.22), _x(Vector3(0, -0.15, -0.01)), teal, K.FLAT, 0.0, Vector2(1.0, 1.0))
		bp.at(StringName("shin_" + side)).box(Vector3(0.17, 0.26, 0.18), _x(Vector3(0, -0.15, -0.02)), teal, K.FLAT, 0.0, Vector2(1.1, 1.0))
		bp.at(StringName("shin_" + side)).box(Vector3(0.175, 0.03, 0.185), _x(Vector3(0, -0.02, -0.02)), Color.WHITE, K.TRIM)


# -------------------------------------------------------------------- Liora

## Healer: built from circles; ivory round-hemmed long coat with sage panels,
## halo ring orbiting the back with 2 docked Med-Pack drones; holo-lens
## monocle (cyberware) and mana IV lines on the forearms.
static func _liora(bp: ModelBlueprint) -> void:
	var h := 1.78
	var ivory := ModelPalette.signature(&"liora")
	var sage := ModelPalette.secondary(&"liora")
	_body(bp, {"h": h, "sw": 0.11, "hw": 0.05, "chest": 0.11, "limb": 0.92, "torso": ivory, "sleeves": ivory,
		"legs": sage.darkened(0.35), "boots": Color.WHITE, "boots_k": K.TRIM, "gloves": sage.darkened(0.2),
		"skin": ModelPalette.SKIN_A, "belly": sage, "stride": 1.0})
	var sp := bp.at(&"spine")
	# soft rounded armour: round shoulder guards and a chest plate (faction trim)
	for s in [1.0, -1.0]:
		sp.sphere(0.085, _x(Vector3(0.2 * s, 0.47, 0), Vector3.ZERO, Vector3(1.1, 0.8, 1.1)), Color.WHITE, K.TRIM, 0.0, 12)
		sp.box(Vector3(0.05, 0.3, 0.02), _x(Vector3(0.07 * s, 0.25, -0.1)), sage)
	sp.sphere(0.13, _x(Vector3(0, 0.38, -0.03), Vector3.ZERO, Vector3(1.2, 0.8, 0.75)), Color.WHITE, K.TRIM, 0.0, 12)
	sp.cyl(0.11, 0.12, 0.03, _x(Vector3(0, 0.05, 0)), sage, K.FLAT, 0.0, 14)
	# round-hemmed long coat (flared cone from the waist to the shins)
	var hp := bp.at(&"hips")
	hp.cyl(0.13, 0.29, 0.7, _x(Vector3(0, -0.32, 0.01)), ivory, K.FLAT, 0.0, 16)
	hp.torus(0.27, 0.3, _x(Vector3(0, -0.66, 0.01)), sage, K.FLAT, 0.0, 20, 5)
	for s in [1.0, -1.0]:
		hp.box(Vector3(0.06, 0.6, 0.01), _x(Vector3(0.2 * s, -0.3, 0.0), Vector3(0, 0, -14 * s)), sage)
	hp.box(Vector3(0.12, 0.1, 0.06), _x(Vector3(-0.16, -0.02, -0.06)), sage.darkened(0.25))  # med pouch (prop)
	# head: very long hair in a loose ribbon
	var hd := bp.at(&"head")
	hd.sphere(0.13, _x(Vector3(0, 0.17, 0.02), Vector3.ZERO, Vector3(1.04, 0.88, 1.02)), Color("#C9A27A"))
	bp.pivot(&"hair", &"head", Vector3(0, 0.12, 0.09), Vector3(8, 0, 0), [&"sway", 1.6, 0.25])
	var hr := bp.at(&"hair")
	hr.capsule(0.07, 0.75, _x(Vector3(0, -0.34, 0.0), Vector3.ZERO, Vector3(1.2, 1.0, 0.6)), Color("#C9A27A"))
	hr.box(Vector3(0.15, 0.04, 0.06), _x(Vector3(0, -0.12, 0.02)), sage)
	# Cyberware: holo-lens monocle over the right eye
	hd.torus(0.026, 0.034, _x(Vector3(0.03, 0.09, -0.065), Vector3(90, 0, 0)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 12, 4)
	bp.at(&"head", "holo").box(Vector3(0.05, 0.05, 0.004), _x(Vector3(0.03, 0.09, -0.075)), Color.WHITE)
	# mana IV lines along both forearms, field-patched elbows (prop)
	for side in ["l", "r"]:
		var f := bp.at(StringName("fore_" + side))
		f.box(Vector3(0.008, 0.26, 0.008), _x(Vector3(0, -0.14, -0.03)), Color.WHITE, K.NEON, 0.8)
		bp.at(StringName("arm_" + side)).box(Vector3(0.07, 0.06, 0.07), _x(Vector3(0, -0.29, 0.0)), sage.darkened(0.15))
	# Hook: halo ring orbiting the back with 2 docked Med-Pack drones
	bp.pivot(&"halo", &"spine", Vector3(0, 0.52, 0.18), Vector3(80, 0, 0), [&"orbit", 0.5, 0.02])
	var ring := bp.at(&"halo")
	ring.torus(0.38, 0.42, _x(Vector3.ZERO), Color.WHITE, K.TRIM, 0.0, 28, 5)
	ring.torus(0.395, 0.405, _x(Vector3(0, 0.022, 0)), Color.WHITE, K.NEON, 0.9, 28, 3)
	for k in 2:
		var a := PI * 0.5 + PI * k
		var p := Vector3(cos(a) * 0.4, 0, sin(a) * 0.4)
		ring.sphere(0.07, _x(p), ivory, K.FLAT, 0.0, 10)
		ring.torus(0.06, 0.075, _x(p, Vector3(0, 0, 90)), sage, K.FLAT, 0.0, 12, 4)
		bp.at(&"halo", "mana:%s:1.0" % ModelPalette.HEAL_VERDANT.to_html(false)).sphere(0.03, _x(p + Vector3(0, -0.055, 0)), Color.WHITE, K.FLAT, 0.0, 8)
	# leaf-in-ring emblem on the back (original glyph, prop)
	sp.torus(0.05, 0.062, _x(Vector3(0, 0.32, 0.075), Vector3(90, 0, 0)), sage, K.FLAT, 0.0, 14, 4)
	sp.prism(Vector3(0.04, 0.07, 0.01), _x(Vector3(0, 0.32, 0.078)), sage)


# ---------------------------------------------------------------------- Hex

## Hacker: hunched in an oversized black hoodie; cat-ear antenna headset past
## the hood; neural jacks + chrome wrist decks (cyberware) projecting floating
## holo panels; shorts and oversized lime-soled sneakers.
static func _hex(bp: ModelBlueprint) -> void:
	var h := 1.72
	var lime := ModelPalette.signature(&"hex")
	var black := ModelPalette.secondary(&"hex")
	_body(bp, {"h": h, "sw": 0.12, "hw": 0.052, "chest": 0.14, "limb": 1.1, "torso": black, "sleeves": black,
		"legs": ModelPalette.SKIN_B, "legs_k": K.SKIN, "boots": Color.WHITE, "boots_k": K.TRIM, "gloves": ModelPalette.SKIN_B,
		"gloves_k": K.SKIN, "skin": ModelPalette.SKIN_B, "head": 1.12, "lean": -0.2, "foot": 1.35, "belly": black,
		"stride": 0.85, "aim": Vector3(0.03, 0.15, -0.14)})
	var sp := bp.at(&"spine")
	# oversized hoodie: big rounded box + kangaroo pocket + drawstrings + patches
	sp.box(Vector3(0.46, 0.44, 0.32), _x(Vector3(0, 0.22, 0.01)), black, K.FLAT, 0.0, Vector2(1.08, 1.0))
	sp.sphere(0.18, _x(Vector3(0, 0.42, 0.0), Vector3.ZERO, Vector3(1.35, 0.6, 1.0)), black, K.FLAT, 0.0, 12)
	sp.box(Vector3(0.48, 0.05, 0.34), _x(Vector3(0, 0.02, 0.01)), Color.WHITE, K.TRIM)
	sp.box(Vector3(0.26, 0.1, 0.02), _x(Vector3(0, 0.12, -0.16)), black.lightened(0.08))
	for s in [1.0, -1.0]:
		sp.box(Vector3(0.012, 0.16, 0.012), _x(Vector3(0.04 * s, 0.38, -0.17)), lime, K.FLAT)
		sp.sphere(0.014, _x(Vector3(0.04 * s, 0.3, -0.17)), lime, K.FLAT, 0.0, 6)
	sp.box(Vector3(0.08, 0.08, 0.01), _x(Vector3(-0.12, 0.3, -0.165), Vector3(0, 0, 12)), lime)  # patches / stickers
	sp.box(Vector3(0.06, 0.06, 0.01), _x(Vector3(0.13, 0.22, -0.165), Vector3(0, 0, -20)), Color("#E255B5"))
	sp.box(Vector3(0.07, 0.05, 0.01), _x(Vector3(0.0, 0.32, 0.17)), Color("#34D8C4"))
	# shorts
	bp.at(&"hips").box(Vector3(0.3, 0.16, 0.2), _x(Vector3(0, -0.06, 0)), black.lightened(0.12))
	for side in ["l", "r"]:
		bp.at(StringName("leg_" + side)).cyl(0.075, 0.075, 0.2, _x(Vector3(0, -0.1, 0)), black.lightened(0.12), K.FLAT, 0.0, 10)
		var sh := bp.at(StringName("shin_" + side))
		# oversized sneakers: chunky lime soles under the shoe + high socks
		sh.box(Vector3(0.15, 0.05, 0.29), _x(Vector3(0, -0.36 - 0.035 * h, -0.045)), lime)
		sh.box(Vector3(0.12, 0.06, 0.12), _x(Vector3(0, -0.36 + 0.02, 0.02)), Color.WHITE, K.TRIM)
		sh.cyl(0.042, 0.042, 0.12, _x(Vector3(0, -0.25, 0)), Color.WHITE, K.FLAT, 0.0, 8)
		sh.cyl(0.043, 0.043, 0.015, _x(Vector3(0, -0.2, 0)), lime, K.FLAT, 0.0, 8)
	# Head: hood up + cat-ear antenna headset poking past it
	var hd := bp.at(&"head")
	hd.sphere(0.16, _x(Vector3(0, 0.17, 0.035), Vector3.ZERO, Vector3(1.05, 1.0, 1.1)), black, K.FLAT, 0.0, 12)
	hd.box(Vector3(0.2, 0.05, 0.03), _x(Vector3(0, 0.29, -0.13), Vector3(-25, 0, 0)), black)
	hd.box(Vector3(0.14, 0.03, 0.02), _x(Vector3(0, 0.205, -0.115)), ModelPalette.SKIN_C)
	for s in [1.0, -1.0]:
		hd.cyl(0.05, 0.05, 0.04, _x(Vector3(0.15 * s, 0.15, 0.0), Vector3(0, 0, 90)), ModelPalette.GUNMETAL, K.FLAT, 0.0, 10)
		hd.cyl(0.035, 0.035, 0.044, _x(Vector3(0.152 * s, 0.15, 0.0), Vector3(0, 0, 90)), lime, K.FLAT, 0.0, 10)
		hd.prism(Vector3(0.11, 0.17, 0.05), _x(Vector3(0.1 * s, 0.37, 0.02), Vector3(0, 0, -16 * s)), ModelPalette.GUNMETAL)
		hd.prism(Vector3(0.06, 0.1, 0.054), _x(Vector3(0.1 * s, 0.36, 0.02), Vector3(0, 0, -16 * s)), Color.WHITE, K.NEON, 1.0)
		hd.box(Vector3(0.03, 0.03, 0.03), _x(Vector3(0.14 * s, 0.1, 0.07)), ModelPalette.CHROME_COOL, K.CHROME)  # neural jacks
		hd.cyl(0.006, 0.006, 0.12, _x(Vector3(0.12 * s, 0.05, 0.1), Vector3(30, 0, 0)), ModelPalette.INK, K.FLAT, 0.0, 4)
	# Cyberware: chrome wrist decks
	for side in ["l", "r"]:
		var f := bp.at(StringName("fore_" + side))
		f.box(Vector3(0.075, 0.09, 0.07), _x(Vector3(0, -0.22, 0)), ModelPalette.CHROME_COOL, K.CHROME)
		f.box(Vector3(0.05, 0.006, 0.072), _x(Vector3(0, -0.2, 0)), Color.WHITE, K.NEON, 0.9)
	# Hook: floating holo panels orbiting near the wrists (+ streaming cam drone prop)
	for k in 3:
		var pn := StringName("panel%d" % k)
		var pos := [Vector3(-0.36, 0.28, -0.2), Vector3(0.38, 0.4, -0.12), Vector3(-0.3, 0.55, -0.05)][k] as Vector3
		bp.pivot(pn, &"spine", pos, Vector3(0, [35.0, -40.0, 20.0][k], [8.0, -6.0, 4.0][k]), [&"bob", 2.0 + k * 0.7, 0.03])
		var pq := bp.at(pn, "holo_panel")
		pq.quad(Vector2([0.26, 0.22, 0.17][k], [0.17, 0.14, 0.12][k]), _x(Vector3.ZERO), Color.WHITE)
	bp.pivot(&"cam", &"spine", Vector3(0.32, 0.72, 0.1), Vector3.ZERO, [&"bob", 2.6, 0.04])
	var cm := bp.at(&"cam")
	cm.sphere(0.05, _x(Vector3.ZERO), ModelPalette.INK, K.FLAT, 0.0, 10)
	cm.cyl(0.022, 0.022, 0.03, _x(Vector3(0, 0, -0.045), Vector3(90, 0, 0)), lime, K.GLOW, 0.8, 8)
	cm.box(Vector3(0.14, 0.01, 0.03), _x(Vector3(0, 0.05, 0)), ModelPalette.GUNMETAL)


# ------------------------------------------------------------ first person

static var _fp_cache: Dictionary = {}


## First-person forearm + hand of `model_key` on `side` ("l"/"r"), hanging
## along -Y from the elbow (hand at -FP_ARM_LEN), in the hero's sleeve colours
## with its cyberware where it sits on a forearm.
const FP_ARM_LEN: float = 0.4


static func fp_arm_mesh(model_key: StringName, side: String) -> ArrayMesh:
	var ck := "%s|%s" % [model_key, side]
	if _fp_cache.has(ck):
		return _fp_cache[ck]
	var b := PartBuilder.new()
	var sig := ModelPalette.signature(model_key)
	var sleeve := sig
	var sleeve_k := K.FLAT
	var glove := ModelPalette.RUBBER
	var glove_k := K.FLAT
	var r0 := 0.046
	match model_key:
		&"ryker":
			sleeve = sig.darkened(0.15)
		&"brannoc":
			sleeve = ModelPalette.secondary(model_key)
			glove = Color.WHITE
			glove_k = K.TRIM
			r0 = 0.07
		&"liora", &"hex":
			glove = ModelPalette.SKIN_A if model_key == &"liora" else ModelPalette.SKIN_B
			glove_k = K.SKIN
			if model_key == &"hex":
				sleeve = ModelPalette.secondary(model_key)
		&"sable":
			glove = Color.WHITE
			glove_k = K.TRIM
	var chrome_arm := (model_key == &"ryker" and side == "r") or (model_key == &"juniper" and side == "l")
	if chrome_arm:
		sleeve = ModelPalette.CHROME_COOL
		sleeve_k = K.CHROME
	b.cyl(r0 * 0.82, r0, FP_ARM_LEN - 0.06, _x(Vector3(0, -(FP_ARM_LEN - 0.06) * 0.5, 0)), sleeve, sleeve_k, 0.0, 12)
	b.cyl(r0 * 1.05, r0 * 1.05, 0.05, _x(Vector3(0, -FP_ARM_LEN + 0.07, 0)), Color.WHITE, K.TRIM, 0.0, 12)
	b.box(Vector3(0.075, 0.1, 0.05) * (1.3 if model_key == &"brannoc" else 1.0), _x(Vector3(0, -FP_ARM_LEN - 0.01, 0)), glove, glove_k)
	b.box(Vector3(0.022, 0.06, 0.03), _x(Vector3(0.04 if side == "r" else -0.04, -FP_ARM_LEN + 0.0, -0.025), Vector3(0, 0, 25 if side == "r" else -25)), glove, glove_k)
	match model_key:
		&"ryker":
			if side == "r":
				b.torus(0.03, 0.042, _x(Vector3(0, -0.18, -0.045), Vector3(90, 0, 0)), Color.WHITE, K.NEON, 1.0, 12, 4)
		&"juniper":
			if side == "l":
				b.torus(0.044, 0.05, _x(Vector3(0, -0.12, 0)), Color.WHITE, K.NEON, 0.8, 12, 4)
				b.box(Vector3(0.012, 0.07, 0.012), _x(Vector3(0.025, -FP_ARM_LEN - 0.06, -0.02), Vector3(20, 0, 10)), ModelPalette.CHROME_WARM, K.CHROME)
		&"vesper":
			for k in 3:
				b.cyl(0.009, 0.012, 0.04, _x(Vector3(-0.022 + k * 0.022, -FP_ARM_LEN - 0.07, -0.01)), ModelPalette.CHROME_COOL, K.CHROME, 0.0, 6)
		&"hex":
			b.box(Vector3(0.1, 0.1, 0.09), _x(Vector3(0, -0.28, 0)), ModelPalette.CHROME_COOL, K.CHROME)
			b.box(Vector3(0.07, 0.006, 0.092), _x(Vector3(0, -0.26, 0)), Color.WHITE, K.NEON, 0.9)
		&"liora":
			b.box(Vector3(0.008, 0.28, 0.008), _x(Vector3(0, -0.18, -0.045)), Color.WHITE, K.NEON, 0.8)
		&"sable":
			b.box(Vector3(0.1, 0.12, 0.09), _x(Vector3(0, -0.22, 0)), Color.WHITE, K.TRIM)
		&"brannoc":
			if side == "r":
				b.box(Vector3(0.05, 0.3, 0.26), _x(Vector3(0.1, -0.2, 0.0)), sig)
				b.box(Vector3(0.055, 0.3, 0.02), _x(Vector3(0.1, -0.2, -0.13)), Color.WHITE, K.TRIM)
	var m := b.commit()
	_fp_cache[ck] = m
	return m
