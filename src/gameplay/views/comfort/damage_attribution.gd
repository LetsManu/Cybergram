class_name DamageAttribution
extends RefCounted
## Client-side "who hurt me" for the damage direction indicator (W16-COMFORT).
## The client never receives damage events for itself, so an HP drop is matched
## to what it already knows from events and snapshots, in this priority:
##   1 HERO_SHOT  an enemy hero's SHOT whose impact stopped at our body
##   2 BOLT       a Wardling / hero mana bolt (snapshot bolts) that ended at us
##   3 AOE        an enemy ability circle / burst covering us (direction = centre)
##   4 LINE       an enemy trail / charge path crossing us (nearest point)
##   5 PROJECTILE an enemy thread projectile close to us (its position)
##   6 MELEE      the nearest enemy Wardling in combat within melee range
##   7 CAST       the nearest enemy hero that just cast a skill (instant / hitscan)
## NONE = true environment damage (fall, Sudden Death ring, Leyfall): the HUD
## shows a non-directional ring. No protocol change: every input is already sent.
##
## `obs` (all optional arrays, entries are Dictionaries, positions are Vector3):
##   shots {pos: shooter, impact}, bolts {from, to}, fx {kind, team, pos, pos2},
##   wardlings {pos, team, combat: bool}, casts {pos}.
## Enemy filtering for hero shots / casts is done by the caller (it knows teams).

enum Kind { NONE, HERO_SHOT, BOLT, AOE, LINE, PROJECTILE, MELEE, CAST }


## Returns {kind: Kind, pos: Vector3} (kind NONE = environment, pos unused).
static func resolve(own: Vector3, own_team: int, obs: Dictionary, rules: ComfortRulesDef) -> Dictionary:
	var hit := _nearest(obs.get("shots", []), own, "impact", "pos", rules.attribution_radius_m)
	if hit.ok:
		return _r(Kind.HERO_SHOT, hit.pos)
	var bolt := _nearest(obs.get("bolts", []), own, "to", "from", rules.bolt_hit_radius_m)
	if bolt.ok:
		return _r(Kind.BOLT, bolt.pos)
	var aoe := _fx(own, own_team, obs.get("fx", []), rules)
	if aoe.kind != Kind.NONE:
		return aoe
	var melee: Dictionary = {"ok": false}
	var best := rules.melee_range_m
	for w in obs.get("wardlings", []):
		if int(w.team) == own_team or not bool(w.combat):
			continue
		var d := _flat(own, w.pos)
		if d <= best:
			best = d
			melee = {"ok": true, "pos": w.pos}
	if melee.ok:
		return _r(Kind.MELEE, melee.pos)
	var cast: Dictionary = {"ok": false}
	best = rules.cast_max_range_m
	for c in obs.get("casts", []):
		var d := _flat(own, c.pos)
		if d <= best:
			best = d
			cast = {"ok": true, "pos": c.pos}
	if cast.ok:
		return _r(Kind.CAST, cast.pos)
	return {"kind": Kind.NONE, "pos": Vector3.ZERO}


static func _r(kind: int, pos: Vector3) -> Dictionary:
	return {"kind": kind, "pos": pos}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Entry whose `near_key` point is closest to `own` (within `radius`); the result
## position is its `src_key` point.
static func _nearest(list: Array, own: Vector3, near_key: String, src_key: String, radius: float) -> Dictionary:
	var best := radius
	var out := {"ok": false, "pos": Vector3.ZERO}
	for e in list:
		var d := (e[near_key] as Vector3).distance_to(own)
		if d <= best:
			best = d
			out = {"ok": true, "pos": e[src_key]}
	return out


static func _fx(own: Vector3, own_team: int, list: Array, rules: ComfortRulesDef) -> Dictionary:
	var res := {"kind": Kind.NONE, "pos": Vector3.ZERO}
	var rank := 99
	var best := INF
	for f in list:
		if int(f.team) == own_team:
			continue
		var kind := Kind.NONE
		var src := Vector3.ZERO
		var dist := INF
		match int(f.kind):
			AbilityWorld.FX_CIRCLE, AbilityWorld.FX_BURST:
				var d := _flat(own, f.pos)
				if d <= (f.pos2 as Vector3).x + rules.attribution_fx_margin_m and absf(own.y - (f.pos as Vector3).y) <= 4.0:
					kind = Kind.AOE
					src = f.pos
					dist = d
			AbilityWorld.FX_TRAIL, AbilityWorld.FX_ARROW:
				var a := Vector2(f.pos.x, f.pos.z)
				var b := Vector2(f.pos2.x, f.pos2.z)
				var q := Geometry2D.get_closest_point_to_segment(Vector2(own.x, own.z), a, b)
				var d := q.distance_to(Vector2(own.x, own.z))
				if d <= rules.attribution_line_halfwidth_m:
					kind = Kind.LINE
					src = Vector3(q.x, (f.pos as Vector3).y, q.y)
					dist = d
			AbilityWorld.FX_THREAD:
				var d := (f.pos as Vector3).distance_to(own)
				if d <= rules.attribution_projectile_radius_m:
					kind = Kind.PROJECTILE
					src = f.pos
					dist = d
		if kind == Kind.NONE:
			continue
		if kind < rank or (kind == rank and dist < best):
			rank = kind
			best = dist
			res = {"kind": kind, "pos": src}
	return res
