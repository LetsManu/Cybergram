class_name SupplyCacheSystem
extends RefCounted
## Supply Caches of held hardpoints (C5; match-flow-and-map.md §3.5,
## weapons-and-mods.md §3.5). Server only; owned by ServerWorld.
##
## Each hardpoint with a cache spot (HardpointDef.supply_cache) has one Cache.
## It serves the team that holds the hardpoint, switching supply_switch_delay_s
## after a flip (owner_at(), pure, shared with the client view and sounds).
##   Mechanical heroes of that team within supply_refill_radius_m refill
##   supply_refill_frac_s of their max reserve per second (x1.5 with Deep Reserve).
##   Mana heroes of that team who touch it (supply_touch_radius_m) get their
##   regen delay cut by supply_mana_delay_cut for supply_mana_buff_s, at most
##   once per supply_mana_cooldown_s.
## Dead heroes get nothing. A neutral hardpoint's Cache serves nobody.

## The crate's collider (tools/art/world/supply_cache.py: 1.3 x 1.0 m, 1.0 m
## high; the cartridge tray above it is not solid). Server and client both add
## it (add_bodies), so movement prediction agrees.
const BODY_SIZE := Vector3(1.3, 0.95, 1.0)

## Modifier source of the Mana buff (one per hero, replaced on each touch).
const BUFF_SOURCE: int = (Modifier.SRC_ZONE << 24) | 0x5C

var rules: MatchRulesDef
## One entry per cache: {hp: HardpointSim, at: Vector3, owner: int, seen: int, since_s: float}.
var caches: Array = []
## net id -> match seconds of the last Mana touch.
var _touched: Dictionary = {}
## net id -> fractional reserve rounds carried between ticks.
var _carry: Dictionary = {}


func _init(objectives: ObjectiveSystem, rules_: MatchRulesDef) -> void:
	rules = rules_ if rules_ != null else MatchRulesDef.new()
	if objectives == null:
		return
	for h in objectives.all:
		if h.def.supply_cache.is_finite():
			caches.append({"hp": h, "at": h.def.supply_cache, "owner": MapDef.TEAM_NEUTRAL, "seen": h.owner,
				"since_s": -1e9})


## Adds one static box collider per cache spot of `md` under `parent` (world
## layer, like the map). Returns the bodies.
static func add_bodies(parent: Node, md: MapDef) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	if md == null:
		return out
	for lane: LaneDef in md.lanes:
		for d: HardpointDef in lane.hardpoints:
			if not d.supply_cache.is_finite():
				continue
			var b := StaticBody3D.new()
			b.name = "SupplyCacheBody_%s" % d.id
			b.collision_layer = PlacementKit.WORLD_MASK
			b.collision_mask = 0
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = BODY_SIZE
			cs.shape = box
			cs.position.y = BODY_SIZE.y * 0.5
			b.add_child(cs)
			b.position = d.supply_cache  # `parent` sits at the map origin (ServerWorld / ClientWorld)
			parent.add_child(b)
			out.append(b)
	return out


## The team a Cache serves (pure): the hardpoint owner once `switch_s` has
## passed since it took the hardpoint at `since_s`; neutral before that.
static func owner_at(hp_owner: int, since_s: float, now_s: float, switch_s: float) -> int:
	if hp_owner == MapDef.TEAM_NEUTRAL or now_s - since_s < switch_s:
		return MapDef.TEAM_NEUTRAL
	return hp_owner


## Advances every Cache by `dt` at match time `now_s` for `heroes`.
func step(dt: float, now_s: float, tick: int, tick_rate: int, heroes: Array) -> void:
	if not rules.supply_caches_enabled:
		return
	for c: Dictionary in caches:
		var hp: HardpointSim = c.hp
		if hp.owner != int(c.seen):
			c.seen = hp.owner
			c.since_s = now_s
		c.owner = owner_at(hp.owner, float(c.since_s), now_s, rules.supply_switch_delay_s)
		if int(c.owner) == MapDef.TEAM_NEUTRAL:
			continue
		for h: HeroBody in heroes:
			if h.combat == null or h.combat.dead or h.combat.team != int(c.owner) or h.combat.weapon == null:
				continue
			var d := _flat(h.state.position, c.at)
			var feed := h.combat.weapon.feed
			if feed is MagazineFeed:
				if d <= rules.supply_refill_radius_m:
					_refill(h.net_id, feed as MagazineFeed, dt * _refill_mult(h))
			elif d <= rules.supply_touch_radius_m:
				_mana_touch(h, now_s, tick, tick_rate)


## Deep Reserve (Reservoir Frame, items-and-armory.md §3.5.3): Mech refills
## from Supply Caches +50% (SignatureRulesDef). Ammo Sparks do not exist yet.
static func _refill_mult(h: HeroBody) -> float:
	return h.combat.passives.refill_mult() if h.combat.passives != null else 1.0


## True while `h` carries the Mana regen buff.
static func has_buff(h: HeroBody) -> bool:
	return h.combat != null and h.combat.stats != null and h.combat.stats.has_source(BUFF_SOURCE)


func _refill(id: int, feed: MagazineFeed, dt: float) -> void:
	var carry: float = float(_carry.get(id, 0.0)) + feed.def.reserve * rules.supply_refill_frac_s * dt
	var whole := floori(carry)
	if whole > 0:
		feed.add_reserve(whole)
		carry -= whole
	_carry[id] = carry if feed.reserve_count() < feed.def.reserve else 0.0


func _mana_touch(h: HeroBody, now_s: float, tick: int, tick_rate: int) -> void:
	if now_s - float(_touched.get(h.net_id, -1e9)) < rules.supply_mana_cooldown_s:
		return
	_touched[h.net_id] = now_s
	var st := h.combat.stats
	st.remove_by_source(BUFF_SOURCE)
	st.add_modifier(Modifier.make(StatCatalog.REGEN_DELAY_MULT, Modifier.Op.PCT, -rules.supply_mana_delay_cut,
		BUFF_SOURCE, tick + ceili(rules.supply_mana_buff_s * tick_rate)))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
