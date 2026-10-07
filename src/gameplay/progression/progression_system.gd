class_name ProgressionSystem
extends RefCounted
## E13 + E15 server economy and progression (wardlings-and-economy.md Part 2,
## §12 Cores; heroes.md §3.3, §3.5, §11; weapons-and-mods.md §3.6, §3.10;
## match-flow-and-map.md §3.5 Forward Beacon). Owned by ServerWorld and
## stepped once per tick after objectives; listens to the server's kill,
## damage, objective and Wardling-removal signals.
##
## Income: starting purse, trickle (match clock, from 1:00), Wardling bounties
## (share list S(n): 75% instant + 25% Lumen Mote), hero kills / assists
## (Shutdown, catch-up C, deficit D), captures and defences (cooldowns, Recap).
## Resonance: Wardlings, hero kills / assists / allies in 25 m, captures,
## defences, individual catch-up ×1.2. Levels 1–15 apply SRC_LEVEL modifiers.
##
## Bot / server API (all return HeroProgress.Result):
##   learn(hero, slot, kind = -1)   buy(hero, item_id, tier = 0)   sell(hero, socket)
##   use_medpack(hero)   set_spawn_choice(hero, HeroProgress.SPAWN_*)
## Read-only helpers: progress_of(hero), can_learn(hero, slot), price_of(hero, item_id, tier).

signal leveled_up(net_id: int, level: int)

## A Wardling Core's Lumen Mote (§12): paid to the frozen share list when an
## ally of the killing team touches it; an enemy touch destroys it.
class Mote:
	var pos: Vector3
	var team: int = 0
	## Hero net id -> Lumen.
	var shares: Dictionary = {}
	## Unwitnessed kill (empty share list): paid to the allied hero who touches it.
	var unwitnessed: float = 0.0
	var expires_tick: int = 0

var server: ServerWorld
var rules: EconomyRulesDef
var catalog: ArmoryCatalogDef
## Cached is_v2() (-1 = not computed).
var _v2: int = -1
var map_def: MapDef
var progress: Dictionary = {}  # hero net id -> HeroProgress
var motes: Array[Mote] = []
## Debug / tests: Armory zone ignored (buy anywhere while alive).
var debug_shop_anywhere: bool = false
## Structured Armory log lines (armory.buy / sell / undo / reject; OpsLog
## format, hero net id only - never account data). Off in tests that buy a lot.
var armory_log: bool = true
## Thresholds of the BuildAdvisor signals (SIG_*) sent to each hero's client.
var advice_rules: AdviceRulesDef

var _unlock_node: SkillNodeDef
var _hooked_wardlings: bool = false
var _last_s: float = 0.0
var _last_capture: Dictionary = {}  # "id:team" -> match seconds
var _last_defence: Dictionary = {}  # id -> match seconds
## Forward Beacon state of a Mid for its owner (SnapshotData.HardpointState.beacon).
enum Beacon { NONE, ATTUNING, READY, UNDER_ATTACK }

## Forward Beacons (§3.5): every Mid hardpoint (1 on the slice, 3 on the full
## map), its last seen owner and when that owner took it.
var _mids: Array[HardpointSim] = []
var _sentinel_deaths: Dictionary = {}  # HardpointSim -> match seconds of the last Sentinel death
var _mid_owner: Dictionary = {}  # HardpointSim -> owner
var _mid_since: Dictionary = {}  # HardpointSim -> match seconds


func _init(world: ServerWorld, rules_: EconomyRulesDef, catalog_: ArmoryCatalogDef, map: MapDef) -> void:
	server = world
	rules = rules_ if rules_ != null else EconomyRulesDef.new()
	catalog = catalog_ if catalog_ != null else ArmoryCatalogDef.new()
	map_def = map
	_unlock_node = SkillNodeDef.new()
	_unlock_node.kind = SkillNodeDef.Kind.UNLOCK
	_unlock_node.required_level = 1
	server.hero_died.connect(_on_hero_died)
	server.hero_damaged.connect(_on_hero_damaged)
	server.hero_damage_taken.connect(_on_damage_taken)
	server.objective_event.connect(_on_objective_event)
	advice_rules = load(AdviceRulesDef.DEFAULT_PATH) as AdviceRulesDef
	if advice_rules == null:
		advice_rules = AdviceRulesDef.new()
	_last_s = server.match_seconds()


# --- Per tick ----------------------------------------------------------------------

func step() -> void:
	if not _hooked_wardlings and server.wardlings != null:
		server.wardlings.wardling_removed.connect(_on_wardling_removed)
		_hooked_wardlings = true
	var t := server.tick
	var now_s := server.match_seconds()
	var over := server.match_flow != null and server.match_flow.is_over()
	var trickle := 0.0
	if not over and now_s > rules.trickle_start_s:
		trickle = rules.trickle_per_min / 60.0 * maxf(0.0, now_s - maxf(_last_s, rules.trickle_start_s))
	_last_s = now_s
	for h in heroes():
		var p := progress_of(h)
		if trickle > 0.0:
			p.add_lumen(trickle, &"trickle")
		_armory_visit(h, p)
		_medpack_tick(h, p, t)
	_step_motes(t)
	_track_mid(now_s)


func heroes() -> Array[HeroBody]:
	var out: Array[HeroBody] = []
	for id in server.registry.ids():
		var h := server.registry.get_node_by_id(id) as HeroBody
		if h != null and h.combat != null:
			out.append(h)
	return out


## The hero's progression state (created on first use: purse, tree on, L1).
func progress_of(h: HeroBody) -> HeroProgress:
	var p: HeroProgress = progress.get(h.net_id)
	if p == null:
		p = HeroProgress.new(h.net_id)
		p.lumen = rules.starting_purse
		p.earned[&"purse"] = rules.starting_purse
		progress[h.net_id] = p
		h.combat.abilities.tree_enabled = true
		h.combat.apply_level(1, rules.hp_per_level)
	return p


# --- Resonance and levels ----------------------------------------------------------

## Awards Resonance (individual catch-up applied); returns the amount given.
func award_exp(h: HeroBody, amount: float, source: StringName = &"other") -> float:
	if amount <= 0.0:
		return 0.0
	var p := progress_of(h)
	if p.level <= team_avg_level(h.combat.team) - rules.individual_catchup_levels:
		amount *= rules.individual_catchup_mult
	p.exp += amount
	p.exp_by[source] = float(p.exp_by.get(source, 0.0)) + amount
	_sync_level(h, p)
	return amount


func _sync_level(h: HeroBody, p: HeroProgress) -> void:
	var l := EconomyMath.level_for_exp(rules, floori(p.exp + 1e-4))
	if l != p.level:
		p.level = l
		h.combat.apply_level(l, rules.hp_per_level)
		leveled_up.emit(h.net_id, l)


func team_avg_level(team: int) -> float:
	var n := 0
	var sum := 0
	for id in progress:
		var h := server.hero(id)
		if h != null and h.combat.team == team:
			sum += (progress[id] as HeroProgress).level
			n += 1
	return float(sum) / n if n > 0 else 1.0


## §16.1 team deficit D for `team` (kills and captures only).
func deficit(team: int) -> float:
	var res := [0.0, 0.0]
	for id in progress:
		var h := server.hero(id)
		if h != null and h.combat.team >= 0 and h.combat.team <= 1:
			res[h.combat.team] += (progress[id] as HeroProgress).exp
	if team < 0 or team > 1:
		return 1.0
	return EconomyMath.deficit(rules, res[team], maxf(res[0], res[1]))


## Debug / tests: sets the hero's Resonance to the start of `level`.
func debug_set_level(h: HeroBody, level: int) -> void:
	var p := progress_of(h)
	p.exp = EconomyMath.exp_for_level(rules, level)
	_sync_level(h, p)


# --- Skill tree (heroes.md §3.5, §11 reduced tree) ----------------------------------

## Learns the next node of `slot` (basics: Unlock -> Boost -> Fork A|B ->
## Mastery; ultimate: rank 1 -> 2 -> 3). `kind` (SkillNodeDef.Kind) must match
## the next node when given; at the Fork stage it is REQUIRED (FORK_A or
## FORK_B, W10-T1: the choice is player input and permanent for the match).
func learn(h: HeroBody, slot: int, kind: int = -1) -> int:
	return _learn(h, slot, kind, false)


## Dry run of learn() (HUD "+" markers, bots). At the Fork stage with no
## `kind` it returns Result.FORK_CHOICE when a point could be spent.
func can_learn(h: HeroBody, slot: int, kind: int = -1) -> int:
	return _learn(h, slot, kind, true)


func _learn(h: HeroBody, slot: int, kind: int, dry: bool) -> int:
	var p := progress_of(h)
	var s := h.combat.abilities.skill(slot)
	if s == null:
		return HeroProgress.Result.NO_SKILL
	var node: SkillNodeDef
	var fork_stage := false
	if s.def.ultimate:
		if kind == SkillNodeDef.Kind.FORK_A or kind == SkillNodeDef.Kind.FORK_B or kind == SkillNodeDef.Kind.MASTERY:
			return HeroProgress.Result.NOT_IN_SLICE  # ultimates have ranks, not forks
		if s.rank >= 3:
			return HeroProgress.Result.MAXED
		node = s.node_of(SkillNodeDef.Kind.ULT_RANK, s.rank + 1)
		if node == null:
			return HeroProgress.Result.MAXED
	elif not s.unlocked:
		if kind == SkillNodeDef.Kind.FORK_A or kind == SkillNodeDef.Kind.FORK_B or kind == SkillNodeDef.Kind.MASTERY:
			return HeroProgress.Result.REQUIRES
		node = _unlock_node
	elif not s.has_node(SkillNodeDef.Kind.BOOST):
		if kind == SkillNodeDef.Kind.FORK_A or kind == SkillNodeDef.Kind.FORK_B or kind == SkillNodeDef.Kind.MASTERY:
			return HeroProgress.Result.REQUIRES  # Fork needs the Boost
		node = s.node_of(SkillNodeDef.Kind.BOOST)
		if node == null:
			return HeroProgress.Result.MAXED
	elif s.fork() == 0:
		if kind == SkillNodeDef.Kind.MASTERY:
			return HeroProgress.Result.REQUIRES  # Mastery needs a Fork
		fork_stage = true
		node = s.node_of(kind if kind == SkillNodeDef.Kind.FORK_B else SkillNodeDef.Kind.FORK_A)
		if node == null:
			return HeroProgress.Result.MAXED  # no fork data authored
		if kind >= 0 and kind != SkillNodeDef.Kind.FORK_A and kind != SkillNodeDef.Kind.FORK_B:
			return HeroProgress.Result.REQUIRES
	elif not s.has_node(SkillNodeDef.Kind.MASTERY):
		if kind == SkillNodeDef.Kind.FORK_A or kind == SkillNodeDef.Kind.FORK_B:
			return HeroProgress.Result.FORK_LOCKED  # the choice is permanent
		node = s.node_of(SkillNodeDef.Kind.MASTERY)
		if node == null:
			return HeroProgress.Result.MAXED
	else:
		return HeroProgress.Result.MAXED
	if kind >= 0 and not fork_stage and kind != node.kind:
		return HeroProgress.Result.REQUIRES
	if p.skill_points() < 1:
		return HeroProgress.Result.NO_POINTS
	if p.level < node.required_level:
		return HeroProgress.Result.LEVEL_GATE
	if fork_stage and kind < 0:
		return HeroProgress.Result.FORK_CHOICE
	if not dry:
		s.learn(node, h.combat.stats)
		p.spent += 1
	return HeroProgress.Result.OK


# --- Armory --------------------------------------------------------------------------

## Buys `item_id` (tier 1..3; 0 = next tier of a held line).
func buy(h: HeroBody, item_id: StringName, tier: int = 0) -> int:
	return buy_index(h, catalog.index_of(item_id), tier)


## `tier` is ignored (v1 mount tiers are gone; kept for the wire format).
func buy_index(h: HeroBody, index: int, tier: int = 0) -> int:
	var p := progress_of(h)
	if debug_shop_anywhere and not h.combat.dead:
		p.at_armory = true
	var before := p.lumen
	var r := ItemShop.buy(p, h.combat, catalog, index, rules)
	_log_armory(h, "buy", index, tier, r, before, p.lumen)
	return r


## True when the catalog is the Armory v2 recipe catalog (items-and-armory.md):
## purchases go through ItemShop and the inventory is replicated.
func is_v2() -> bool:
	if _v2 < 0:
		_v2 = 0
		if catalog != null:
			for it in catalog.items:
				if it != null and it.tier != ArmoryItemDef.Tier.NONE:
					_v2 = 1
					break
	return _v2 == 1


## v2: sells the item at inventory place `loc` (ItemInventory.LOC_*).
func sell_at(h: HeroBody, loc: int) -> int:
	var p := progress_of(h)
	if debug_shop_anywhere and not h.combat.dead:
		p.at_armory = true
	var index := p.inv.index_at(loc)
	var before := p.lumen
	var r := ItemShop.sell(p, h.combat, catalog, loc, rules)
	_log_armory(h, "sell", index, loc, r, before, p.lumen)
	return r


## v2: undoes the purchase at `loc`, a squad upgrade / Med-Pack (`row_index`
## >= 0), or the last change of the visit (`loc` < 0 and `row_index` < 0).
func undo(h: HeroBody, loc: int, row_index: int = -1) -> int:
	var p := progress_of(h)
	if debug_shop_anywhere and not h.combat.dead:
		p.at_armory = true
	var before := p.lumen
	var index := row_index if row_index >= 0 else p.inv.index_at(loc) if loc >= 0 else -1
	var r: int
	if row_index >= 0:
		r = ItemShop.undo_row(p, h.combat, catalog, row_index, rules)
	elif loc >= 0:
		r = ItemShop.undo_at(p, h.combat, catalog, loc, rules)
	else:
		r = ItemShop.undo_last(p, h.combat, catalog, rules)
	_log_armory(h, "undo", index, loc, r, before, p.lumen)
	return r


func _log_armory(h: HeroBody, op: String, index: int, arg: int, r: int, before: int, after: int) -> void:
	if not armory_log:
		return
	var item := catalog.at(index) if catalog != null else null
	var ok := r == HeroProgress.Result.OK
	var event := "armory." + (op if ok else "reject")
	OpsLog.emit(OpsLog.record("armory", "info" if ok else "warn", event,
		"%s %s %s hero=%d lumen %d->%d" % [op, item.id if item != null else "#%d" % index,
			"ok" if ok else HeroProgress.Result.keys()[r], h.net_id, before, after],
		{"op": op, "hero": h.net_id, "hero_def": String(h.combat.def.id) if h.combat != null and h.combat.def != null else "",
		 "item": String(item.id) if item != null else str(index), "arg": arg,
		 "result": HeroProgress.Result.keys()[r] if r >= 0 and r < HeroProgress.Result.size() else str(r),
		 "lumen_before": before, "lumen_after": after}))


## Price the hero would pay now for `item_id` at `tier` (0 = next): upgrade
## cost for a held line, list price otherwise (bots' buy planning); -1 when the
## purchase cannot happen (owned squad upgrade, missing requirement, carry
## limit, maxed line, disabled or unknown item).
func price_of(h: HeroBody, item_id: StringName, tier: int = 0) -> int:
	var item := catalog.find(item_id)
	if item == null:
		return -1
	var p := progress_of(h)
	if item.disabled:
		return -1
	if item.kind == ArmoryItemDef.Kind.SQUAD and (p.owned.has(item.id)
			or (item.requires != &"" and not p.owned.has(item.requires))):
		return -1
	if item.kind == ArmoryItemDef.Kind.CONSUMABLE and p.medpacks >= item.carry_limit:
		return -1
	var held := p.mount(item.socket) if item.socket != ArmoryItemDef.Socket.NONE else null
	if held != null and held.item == item:
		var nt := tier if tier > 0 else held.tier + 1
		return EconomyMath.upgrade_cost(item, nt, held.tier) if nt <= item.tiers() and nt > held.tier else -1
	return item.price(maxi(tier, 1))


func is_at_armory(h: HeroBody) -> bool:
	if h.combat.dead:
		return false
	if debug_shop_anywhere:
		return true
	if map_def == null:
		return false
	var hq := map_def.hq(h.combat.team)
	if hq == null:
		return false
	if rules.shop_in_sanctum and _flat(h.state.position, hq.sanctum) <= hq.sanctum_radius:
		return true
	return _flat(h.state.position, hq.armory) <= rules.armory_radius_m


func _armory_visit(h: HeroBody, p: HeroProgress) -> void:
	var at := is_at_armory(h)
	if p.at_armory and not at:
		p.end_visit()
	p.at_armory = at


## §19 Med-Pack: 40% of max HP over 3 s; firing cancels.
func use_medpack(h: HeroBody) -> int:
	var p := progress_of(h)
	if h.combat.dead:
		return HeroProgress.Result.DEAD
	if p.medpacks <= 0:
		return HeroProgress.Result.NOT_OWNED
	if p.heal_until_tick >= 0 and server.tick < p.heal_until_tick:
		return HeroProgress.Result.HEALING
	p.medpacks -= 1
	# A pack bought this visit and then used can no longer be undone.
	var med := catalog.find(&"med_pack") if catalog != null else null
	if med != null and p.visit_count(med.id) > p.medpacks:
		p._visit_add(med.id, p.medpacks - p.visit_count(med.id))
	var ticks := maxi(1, roundi(rules.medpack_duration_s * server.net.tick_rate_hz))
	p.heal_until_tick = server.tick + ticks
	p.heal_per_tick = h.combat.health.max_hp * rules.medpack_heal_frac / ticks
	p.heal_shots = h.combat.weapon.shots_fired if h.combat.weapon != null else 0
	return HeroProgress.Result.OK


func _medpack_tick(h: HeroBody, p: HeroProgress, t: int) -> void:
	if p.heal_until_tick < 0:
		return
	var shots := h.combat.weapon.shots_fired if h.combat.weapon != null else 0
	if h.combat.dead or shots != p.heal_shots or t >= p.heal_until_tick:
		p.heal_until_tick = -1
		return
	h.combat.health.heal(p.heal_per_tick)


# --- Spawn choice (Mid Forward Beacon) ---------------------------------------------

func set_spawn_choice(h: HeroBody, choice: int) -> int:
	progress_of(h).spawn_choice = clampi(choice, HeroProgress.SPAWN_SANCTUM, HeroProgress.SPAWN_BEACON)
	return HeroProgress.Result.OK


## True if any Mid Beacon of `team` is ready (held, attuned 15 s, not under attack).
func beacon_ready(team: int) -> bool:
	return not ready_beacons(team).is_empty()


## The Mid hardpoints whose Forward Beacon `team` can spawn at now.
func ready_beacons(team: int) -> Array[HardpointSim]:
	var out: Array[HardpointSim] = []
	for m in _mids:
		if _mid_ready(m, team):
			out.append(m)
	return out


func _mid_ready(m: HardpointSim, team: int) -> bool:
	return m.owner == team and beacon_state(m) == Beacon.READY


## Forward Beacon state of Mid `m` for its owner (replicated, ForwardBeaconView).
func beacon_state(m: HardpointSim) -> int:
	if m.owner == MapDef.TEAM_NEUTRAL or not _mid_since.has(m):
		return Beacon.NONE
	if beacon_attune(m) < 1.0:
		return Beacon.ATTUNING
	if m.capturing_team == 1 - m.owner and m.progress > 0.0:
		return Beacon.UNDER_ATTACK
	for h in heroes():
		if h.combat.team != m.owner and not h.combat.dead \
				and _flat(h.state.position, m.def.position) <= rules.beacon_threat_radius_m:
			return Beacon.UNDER_ATTACK
	return Beacon.READY


## Attunement of Mid `m` in [0, 1] (1 = attuned; the 15 s start at the capture).
func beacon_attune(m: HardpointSim) -> float:
	if rules.beacon_attune_s <= 0.0:
		return 1.0
	return clampf((server.match_seconds() - float(_mid_since.get(m, -1e9))) / rules.beacon_attune_s, 0.0, 1.0)


## Where `team`'s heroes spawn at the Mid at `at` (zone `zone_radius`): half way
## to the zone edge on the side toward the team's Sanctum. Shared with the pad
## view (ForwardBeaconView) and the placement audit.
static func beacon_spot(at: Vector3, sanctum: Vector3, zone_radius: float) -> Vector3:
	var toward := Vector3(sanctum.x - at.x, 0.0, sanctum.z - at.z)
	toward = toward.normalized() if toward.length_squared() > 1e-6 else Vector3.BACK
	return at + toward * zone_radius * 0.5


## Beacon spawn point of `team`: inside a ready Mid zone, on the side toward the
## team's HQ. With several ready Mids (full map) the one in `lane` wins (the
## lane the hero fell in), else the Center Mid, else the first ready one.
func beacon_point(team: int, lane: int = -1) -> Vector3:
	var ready := ready_beacons(team)
	var m: HardpointSim = null
	for r in ready:
		if r.lane == lane:
			m = r
	if m == null and not ready.is_empty():
		m = ready[0]
		var centre := (server.objectives.lanes.size() - 1) / 2 if server.objectives != null else 0
		for r in ready:
			if r.lane == centre:
				m = r
	if m == null:
		m = _mids[0] if not _mids.is_empty() else null
	if m == null:
		return Vector3.ZERO
	var at := m.def.position
	var hq := map_def.hq(team) if map_def != null else null
	var sanctum := hq.sanctum if hq != null else at + Vector3.BACK
	return beacon_spot(at, sanctum, m.def.zone_radius) + Vector3(0.0, 0.05, 0.0)


## Respawn position for `h`, or null for the Sanctum (also when the Beacon
## fell or came under attack during the countdown: match-flow §5 edge case).
func respawn_point(h: HeroBody) -> Variant:
	var p := progress_of(h)
	if p.spawn_choice == HeroProgress.SPAWN_BEACON and beacon_ready(h.combat.team):
		var lane := map_def.nearest_lane(h.state.position) if map_def != null else -1
		return beacon_point(h.combat.team, lane)
	return null


func _track_mid(now_s: float) -> void:
	if _mids.is_empty() and server.objectives != null:
		for hp in server.objectives.all:
			if hp.def.tier == HardpointDef.Tier.MID:
				_mids.append(hp)
				_mid_owner[hp] = hp.owner
				_mid_since[hp] = -1e9
	for m in _mids:
		if m.owner != int(_mid_owner.get(m, -2)):
			_mid_owner[m] = m.owner
			_mid_since[m] = now_s


# --- Input actions ------------------------------------------------------------------

## ACTION_LEARN `action_arg`: bits 0-1 = slot, bits 2-3 = Fork choice
## (0 = none / next node, 1 = Fork A, 2 = Fork B). W10-T1, no wire change.
static func learn_arg(slot: int, fork_choice: int = 0) -> int:
	return (slot & 3) | ((fork_choice & 3) << 2)


## SkillNodeDef.Kind encoded in an ACTION_LEARN arg (-1 = next node).
static func learn_kind_of_arg(arg: int) -> int:
	match (arg >> 2) & 3:
		1:
			return SkillNodeDef.Kind.FORK_A
		2:
			return SkillNodeDef.Kind.FORK_B
	return -1


## Applies an InputCommand ACTION_* (called by ServerWorld before movement; also
## while dead: points can be spent and the spawn chosen any time).
func handle_action(h: HeroBody, cmd: InputCommand) -> int:
	match cmd.action:
		InputCommand.ACTION_LEARN:
			return learn(h, cmd.action_arg & 3, learn_kind_of_arg(cmd.action_arg))
		InputCommand.ACTION_BUY:
			return _shop_result(h, buy_index(h, cmd.action_arg & 0xFF, cmd.action_arg >> 8))
		InputCommand.ACTION_SELL:
			return _shop_result(h, _sell_v2(h, cmd.action_arg))
		InputCommand.ACTION_USE_MEDPACK:
			return use_medpack(h)
		InputCommand.ACTION_SPAWN_CHOICE:
			return set_spawn_choice(h, cmd.action_arg)
	return HeroProgress.Result.OK


## v22 ACTION_SELL arg (InputCommand.UNDO_* layout).
func _sell_v2(h: HeroBody, arg: int) -> int:
	if arg == InputCommand.UNDO_LAST:
		return undo(h, -1)
	var low := arg & 0xFF
	if arg & InputCommand.UNDO_ITEM_FLAG:
		if low & InputCommand.UNDO_ROW_FLAG:
			return undo(h, -1, low & 0x7F)
		if not SnapshotData.ProgressState.INV_LOCS.has(low):
			return HeroProgress.Result.INVALID
		return undo(h, low)
	if arg > 0xFF or not SnapshotData.ProgressState.INV_LOCS.has(low):
		return HeroProgress.Result.INVALID
	return sell_at(h, low)


## Records the outcome of a client Armory request (replicated as
## ProgressState.shop_seq / shop_result so the HUD shows the real reason).
func _shop_result(h: HeroBody, r: int) -> int:
	var p := progress_of(h)
	p.shop_seq = (p.shop_seq + 1) & 0xFF
	p.shop_result = r
	return r


# --- Income events ------------------------------------------------------------------

## §12 / §15.1 / §16.1 / §17: a Wardling killed by the other team.
func _on_wardling_removed(w: WardlingSim, killer_id: int) -> void:
	if killer_id == 0 or w.turned_until_tick > server.tick:
		return  # dissolved, or subverted: no bounty (§21)
	var kt := 1 - w.team
	var pos := w.global_position
	var window := roundi(rules.wardling_contrib_s * server.net.tick_rate_hz)
	var list: Array[HeroBody] = []
	for h in heroes():
		if h.combat.team != kt:
			continue
		var contrib := w.hit_by.has(h.net_id) and server.tick - int(w.hit_by[h.net_id]) <= window
		if contrib or (not h.combat.dead and _flat(h.state.position, pos) <= rules.share_radius_m):
			list.append(h)
	var squad := w.owner_net_id != 0 or w.squad != null or w.garrison != null
	var tier := server.wardlings.tier if server.wardlings != null else 1
	var split := EconomyMath.wardling_lumen_split(rules, squad, tier, list.size())
	var xp := EconomyMath.wardling_exp(rules, squad, tier, list.size())
	if w.garrison != null:  # §11 Sentinel bounty with RepeatDecay per hardpoint
		var m := sentinel_bounty_mult(w.garrison.hp, server.match_seconds())
		split = [split[0] * m, split[1] * m]
		xp *= m
	var mote := Mote.new()
	mote.pos = pos
	mote.team = kt
	mote.expires_tick = server.tick + roundi(rules.mote_life_s * server.net.tick_rate_hz)
	for h in list:
		progress_of(h).add_lumen(split[0], &"wardling")
		award_exp(h, xp, &"wardling")
		mote.shares[h.net_id] = split[1]
	if list.is_empty():
		mote.unwitnessed = split[1]  # §12: the instant 75% is not paid
	motes.append(mote)


## The Sentinel bounty multiplier for a death at `hp` at match time `now_s`
## (1.5, or × 0.5 within 180 s of the last Sentinel death there); records it.
func sentinel_bounty_mult(hp: HardpointSim, now_s: float) -> float:
	var last: float = float(_sentinel_deaths.get(hp, -1e9))
	_sentinel_deaths[hp] = now_s
	var m := rules.sentinel_bounty_mult
	if now_s - last <= rules.sentinel_repeat_window_s:
		m *= rules.sentinel_repeat_mult
	return m


func _step_motes(t: int) -> void:
	if motes.is_empty():
		return
	var hs := heroes()
	for i in range(motes.size() - 1, -1, -1):
		var m := motes[i]
		if t >= m.expires_tick:
			motes.remove_at(i)
			continue
		for h in hs:
			if h.combat.dead or _flat(h.state.position, m.pos) > rules.mote_radius_m \
					or absf(h.state.position.y - m.pos.y) > 2.0:
				continue
			if h.combat.team == m.team:
				if m.shares.is_empty():
					progress_of(h).add_lumen(m.unwitnessed, &"mote")
				for id in m.shares:
					var p: HeroProgress = progress.get(id)
					if p != null:
						p.add_lumen(m.shares[id], &"mote")
			motes.remove_at(i)  # collected, or denied by an enemy touch
			break


func _on_hero_damaged(victim_id: int, attacker_id: int, _amount: float) -> void:
	var v := server.hero(victim_id)
	var a := _hero_for(attacker_id)
	if v != null and a != null and a.combat.team != v.combat.team:
		progress_of(v).damagers[a.net_id] = server.tick


## §16.1 / §17 hero kill: killer K / P, assisters 100 Lumen and 0.5 P, allies
## within 25 m 0.5 P. A Wardling kill credits its owner; else the last hero
## damager within 10 s (§21).
func _on_hero_died(victim_id: int, killer_id: int) -> void:
	var victim := server.hero(victim_id)
	if victim == null:
		return
	var vp := progress_of(victim)
	vp.death_ticks.append(server.tick)
	var t := server.tick
	var kt := 1 - victim.combat.team
	var killer := _hero_for(killer_id)
	if killer == null or killer.combat.team != kt:
		killer = _last_damager(vp, t, roundi(rules.last_damager_s * server.net.tick_rate_hz))
	var win := roundi(rules.hero_contrib_s * server.net.tick_rate_hz)
	var d := deficit(kt)
	var p_killer := -1.0
	if killer != null:
		var kp := progress_of(killer)
		kp.streak += 1
		kp.add_lumen((rules.kill_lumen_base + EconomyMath.shutdown(rules, vp.streak)) * d, &"kill")
		p_killer = EconomyMath.kill_exp(rules, vp.level, kp.level, d)
		award_exp(killer, p_killer, &"kill")
	for h in heroes():
		if h == killer or h.combat.team != kt:
			continue
		var assist := vp.damagers.has(h.net_id) and t - int(vp.damagers[h.net_id]) <= win
		var near := not h.combat.dead and _flat(h.state.position, victim.state.position) <= rules.share_radius_m
		if not assist and not near:
			continue
		var pp := p_killer if p_killer >= 0.0 else EconomyMath.kill_exp(rules, vp.level, progress_of(h).level, d)
		award_exp(h, rules.exp_assist_frac * pp, &"assist")
		if assist or killer == null:
			progress_of(h).add_lumen(rules.assist_lumen * d, &"assist")
	vp.streak = 0
	vp.damagers.clear()
	vp.end_visit()
	vp.heal_until_tick = -1


## §17 / match-flow §3.5 captures and defences (Lumen from the event, D, Recap,
## cooldowns) and §16.1 capture / defence Resonance.
func _on_objective_event(ev: ObjectiveEvent) -> void:
	var now := server.match_seconds()
	var key := String(ev.hardpoint_id)
	if ev.kind == ObjectiveEvent.Kind.DEFENCE:
		if _last_defence.has(key) and now - float(_last_defence[key]) < rules.defence_cooldown_s:
			return
		_last_defence[key] = now
		for id in ev.participants:
			var h := server.hero(id)
			if h != null:
				progress_of(h).add_lumen(ev.lumen_each, &"defence")
				award_exp(h, rules.exp_defence, &"defence")
		return
	var team := ev.new_team
	if team < 0 or team > 1:
		return
	var ck := "%s:%d" % [key, team]
	var cd := 1.0
	if _last_capture.has(ck) and now - float(_last_capture[ck]) < rules.capture_cooldown_s:
		cd = rules.capture_cooldown_mult
	_last_capture[ck] = now
	var hp := server.objectives.find(ev.hardpoint_id) if server.objectives != null else null
	var recap := rules.recap_mult if hp != null and hp.def.initial_owner == team else 1.0
	var d := deficit(team)
	for h in heroes():
		if h.combat.team != team:
			continue
		var p := progress_of(h)
		p.add_lumen(ev.lumen_team * d * cd, &"capture")
		var xp := rules.exp_capture_team * d * cd
		if ev.participants.has(h.net_id):
			p.add_lumen(ev.lumen_each * d * recap * cd, &"capture")
			xp += rules.exp_capture_participant * d * cd
		award_exp(h, xp, &"capture")


func _hero_for(net_id: int) -> HeroBody:
	var n := server.registry.get_node_by_id(net_id) if net_id != 0 else null
	if n is HeroBody:
		return n as HeroBody
	if n is WardlingSim and (n as WardlingSim).owner_net_id != 0:
		return server.hero((n as WardlingSim).owner_net_id)
	return null


func _last_damager(vp: HeroProgress, t: int, window: int) -> HeroBody:
	var best: HeroBody = null
	var best_t := -1
	for id in vp.damagers:
		var at := int(vp.damagers[id])
		if t - at <= window and at > best_t:
			var h := server.hero(id)
			if h != null:
				best = h
				best_t = at
	return best


# --- Armory advice signals ---------------------------------------------------------

func _on_damage_taken(victim_id: int, amount: float, dtype: int) -> void:
	var h := server.hero(victim_id)
	if h == null:
		return
	var p := progress_of(h)
	p.damage_log.append([server.tick, dtype, amount])
	# Bots never read their signals through fill_own: keep the log bounded here.
	var from := server.tick - roundi(advice_rules.damage_window_s * server.net.tick_rate_hz)
	while not p.damage_log.is_empty() and int(p.damage_log[0][0]) < from:
		p.damage_log.pop_front()


## Recomputes `h`'s BuildAdvisor signals (SIG_*) from its recent damage and
## deaths, its HP, the team's standing and the match clock. Prunes the logs.
func refresh_signals(h: HeroBody) -> int:
	var p := progress_of(h)
	var ar := advice_rules
	var hz := float(server.net.tick_rate_hz)
	var t := server.tick
	var dmg_from := t - roundi(ar.damage_window_s * hz)
	while not p.damage_log.is_empty() and int(p.damage_log[0][0]) < dmg_from:
		p.damage_log.pop_front()
	var weapon := 0.0
	var skill := 0.0
	for e in p.damage_log:
		if int(e[1]) == DamageInfo.Type.WEAPON:
			weapon += float(e[2])
		else:
			skill += float(e[2])
	var sig := 0
	var max_hp := h.combat.health.max_hp
	var need := ar.damage_threshold_frac * max_hp
	if weapon >= need and weapon >= skill:
		sig |= SnapshotData.ProgressState.SIG_WEAPON_DAMAGE
	if skill >= need and skill > weapon:
		sig |= SnapshotData.ProgressState.SIG_SKILL_DAMAGE
	var death_from := t - roundi(ar.deaths_window_s * hz)
	var recent := PackedInt32Array()
	for d in p.death_ticks:
		if d >= death_from:
			recent.append(d)
	p.death_ticks = recent
	if recent.size() >= ar.deaths_threshold:
		sig |= SnapshotData.ProgressState.SIG_DIED_OFTEN
	if not h.combat.dead and h.combat.health.hp < max_hp * ar.low_health_frac:
		sig |= SnapshotData.ProgressState.SIG_LOW_HEALTH
	var team := h.combat.team
	if team == 0 or team == 1:
		if deficit(team) >= ar.behind_deficit:
			sig |= SnapshotData.ProgressState.SIG_TEAM_BEHIND
		elif team_avg_level(team) - team_avg_level(1 - team) >= ar.ahead_levels:
			sig |= SnapshotData.ProgressState.SIG_TEAM_AHEAD
	if server.match_flow != null and server.match_flow.def != null:
		var now := server.match_seconds()
		for st in server.match_flow.def.surge_times_s:
			if st > now and st - now <= ar.objective_soon_s:
				sig |= SnapshotData.ProgressState.SIG_OBJECTIVE_SOON
	p.signals = sig
	return sig


# --- Replication --------------------------------------------------------------------

## Own progress block for `h`'s client; also marks learnable skill slots.
## Armory v2 public build (items-and-armory.md §3.8 rule 7): catalog index per
## ProgressState.INV_LOCS place, for SnapshotData.EntityState.build.
func public_build(h: HeroBody) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(SnapshotData.EntityState.BUILD_SIZE)
	out.fill(-1)
	var p := progress_of(h)
	if not is_v2() or p == null:
		return out
	for i in SnapshotData.ProgressState.INV_LOCS.size():
		out[i] = p.inv.index_at(SnapshotData.ProgressState.INV_LOCS[i])
	return out


func fill_own(s: SnapshotData, h: HeroBody) -> void:
	var p := progress_of(h)
	var o := SnapshotData.ProgressState.new()
	o.level = p.level
	o.exp = floori(p.exp + 1e-4)
	o.skill_points = p.skill_points()
	o.lumen = p.lumen
	o.medpacks = p.medpacks
	if p.at_armory:
		o.flags |= SnapshotData.ProgressState.FLAG_AT_ARMORY
	if beacon_ready(h.combat.team):
		o.flags |= SnapshotData.ProgressState.FLAG_BEACON_READY
	if p.spawn_choice == HeroProgress.SPAWN_BEACON:
		o.flags |= SnapshotData.ProgressState.FLAG_SPAWN_BEACON
	if p.heal_until_tick >= 0:
		o.flags |= SnapshotData.ProgressState.FLAG_HEALING
	for id in p.owned:
		var i := catalog.index_of(id)
		if i >= 0 and i < 32:
			o.owned_bits |= 1 << i
			if p.visit_count(id) > 0:
				o.visit_owned_bits |= 1 << i
	o.visit_medpacks = p.visit_count(&"med_pack")
	o.shop_seq = p.shop_seq
	o.shop_result = p.shop_result
	o.signals = refresh_signals(h)
	for i in SnapshotData.ProgressState.MOUNT_SOCKETS.size():
		var m := p.mount(SnapshotData.ProgressState.MOUNT_SOCKETS[i])
		if m != null:
			o.mount_item[i] = m.index
			o.mount_tier[i] = m.tier
			o.mount_paid[i] = m.paid
			o.mount_paid_visit[i] = m.paid_visit
	if is_v2():
		for i in SnapshotData.ProgressState.INV_LOCS.size():
			var loc: int = SnapshotData.ProgressState.INV_LOCS[i]
			o.inv_items[i] = p.inv.index_at(loc)
			var k := p.inv.txn_for(loc)
			if k >= 0 and not p.inv.is_blocked(k):
				o.inv_undo_bits |= 1 << i
		o.inv_txns = p.inv.txns.size()
	for m in motes:
		o.motes.append(m.pos)
	s.progress = o
	if s.own_combat != null:
		for slot in 4:
			var r := can_learn(h, slot)
			if r == HeroProgress.Result.OK or r == HeroProgress.Result.FORK_CHOICE:
				s.own_combat.skill_flags[slot] |= AbilityRunner.FLAG_LEARNABLE


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
