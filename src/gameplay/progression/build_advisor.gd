class_name BuildAdvisor
extends RefCounted
## Armory recommendations (docs/armory.md; plan docs/plans/armory-build-system.md
## §C). Deterministic and transparent: reads a RecommendedBuildDef and a
## BuildState (what the hero owns, Lumen, gun family, match time, mode, server
## signals, enemy / ally tags) and ranks what to buy next, with a reason and a
## debug trace. Pure: never buys anything. Used by ShopModel (client) and bots
## (server), so both follow the same guide.
##
## Simple builds (no nodes) behave exactly like the old ordered list: the first
## step not yet owned whose item fits the gun.
##
## Example:
##   var st := BuildState.from_progress(client.progress, catalog, hero_def, econ)
##   var r := BuildAdvisor.evaluate(build, st, advice_rules)
##   if not r.advice.is_empty(): print(r.advice[0].item_index, " ", r.advice[0].reason_key)

## Rule ids a BuildNodeDef.conditions entry may name (AdviceRulesDef.bonus keys).
const RULES: Array[String] = [
	"core_tier_ready", "affordable_now", "counters_enemy",
	"taking_weapon_damage", "taking_skill_damage", "died_often", "low_health",
	"team_behind", "team_ahead", "objective_soon",
	"enemy_cc", "enemy_burst", "enemy_sustain", "enemy_weapon_dps", "enemy_skill_dps",
	"enemy_mobility", "enemy_zone", "enemy_squad", "enemy_frontline",
	"team_lacks_sustain", "team_lacks_frontline",
]
## Reason key per rule ("Recommended because ...").
const RULE_REASON_PREFIX := "HUD_ADVICE_R_"
## Automatic rules that reorder but rarely make the best headline.
const GENERIC_RULES := ["affordable_now", "core_tier_ready", "counters_enemy"]
const SIGNAL_RULES := {
	"taking_weapon_damage": SnapshotData.ProgressState.SIG_WEAPON_DAMAGE,
	"taking_skill_damage": SnapshotData.ProgressState.SIG_SKILL_DAMAGE,
	"died_often": SnapshotData.ProgressState.SIG_DIED_OFTEN,
	"low_health": SnapshotData.ProgressState.SIG_LOW_HEALTH,
	"team_behind": SnapshotData.ProgressState.SIG_TEAM_BEHIND,
	"team_ahead": SnapshotData.ProgressState.SIG_TEAM_AHEAD,
	"objective_soon": SnapshotData.ProgressState.SIG_OBJECTIVE_SOON,
}
## Generic reason per guide section when neither node nor rule names one.
const SECTION_REASONS := ["HUD_ADVICE_S_OPENING", "HUD_ADVICE_S_EARLY", "HUD_ADVICE_S_SPIKE", "HUD_ADVICE_S_CORE",
	"HUD_ADVICE_S_SQUAD", "HUD_ADVICE_S_CONSUMABLE", "HUD_ADVICE_S_DEFENSIVE", "HUD_ADVICE_S_OFFENSIVE", "HUD_ADVICE_S_UTILITY",
	"HUD_ADVICE_S_COUNTER", "HUD_ADVICE_S_LATE"]


## One recommendation.
class Advice:
	var node: BuildNodeDef
	## The item to buy now. Armory v2: the next part toward `goal_index`
	## (items-and-armory.md §3.10 rule 2); v1: the node's item.
	var item_index: int = -1
	## Armory v2: the finished item this advice builds toward (-1 = v1).
	var goal_index: int = -1
	var target: int = 1
	var section: int = BuildNodeDef.Section.CORE
	## Lumen to reach `target` now (after swap credit), and whether it fits the wallet.
	var cost: int = 0
	var affordable: bool = false
	## Reachable within AdviceRulesDef.affordable_soon_s of expected income.
	var soon: bool = false
	var score: float = 0.0
	## Main reason key, then every matched rule id.
	var reason_key: String = ""
	var rules: PackedStringArray = PackedStringArray()
	## Catalog indices that satisfy the node instead (buyable by this hero).
	var alternatives: Array[int] = []
	var situational: bool = false


## Outcome of one evaluation.
class Result:
	## Offered recommendations, best first.
	var advice: Array[Advice] = []
	## Node ids done (owned or satisfied by an alternative).
	var done: PackedStringArray = PackedStringArray()
	## Core nodes done / total (build progress).
	var core_done: int = 0
	var core_total: int = 0
	## Human-readable evaluation log (debug overlay, --debug-advisor, bots).
	var trace: PackedStringArray = PackedStringArray()

	func best() -> Advice:
		return advice[0] if not advice.is_empty() else null


static func rule_ids() -> PackedStringArray:
	return PackedStringArray(RULES)


## Ranks the open recommendations of `build` for `st`.
static func evaluate(build: RecommendedBuildDef, st: BuildState, ar: AdviceRulesDef = null) -> Result:
	var res := Result.new()
	if build == null or st == null or st.catalog == null:
		return res
	if ar == null:
		ar = AdviceRulesDef.new()
	var nodes: Array[BuildNodeDef] = build.nodes if build.is_guide() else simple_nodes(build)
	var by_id := {}
	for n in nodes:
		if n != null:
			by_id[n.id] = n
	var memo := {}
	for n in nodes:
		if n == null:
			continue
		var done := _done(n, st)
		if done:
			res.done.append(String(n.id))
		if n.core and not n.optional and not n.fallback:
			res.core_total += 1
			if done:
				res.core_done += 1
		if done:
			continue
		var why := _offer_check(n, st, ar, by_id, memo)
		if why != "":
			res.trace.append("skip %s (%s): %s" % [n.id, n.item_id, why])
			continue
		var a := _advise(n, st, ar)
		res.advice.append(a)
		res.trace.append("offer %s (%s) score %.0f rules [%s] cost %d%s" % [n.id, n.item_id, a.score,
			", ".join(a.rules), a.cost, "" if a.affordable else " (short)"])
	# Stable sort: score, then data order.
	var order := {}
	for i in res.advice.size():
		order[res.advice[i]] = i
	res.advice.sort_custom(func(x: Advice, y: Advice) -> bool:
		return x.score > y.score if not is_equal_approx(x.score, y.score) else int(order[x]) < int(order[y]))
	if not res.advice.is_empty():
		res.trace.append("pick %s (%s): %s" % [res.advice[0].node.id, res.advice[0].node.item_id, res.advice[0].reason_key])
	return res


## The ordered list of a simple build as a chain of nodes (step i requires i-1).
static func simple_nodes(build: RecommendedBuildDef) -> Array[BuildNodeDef]:
	var out: Array[BuildNodeDef] = []
	for s in build.steps():
		var n := BuildNodeDef.new()
		n.id = StringName("s%d" % s)
		n.item_id = build.item_at(s)
		n.target = build.target_at(s)
		n.priority = 1000 - s
		if s > 0:
			n.requires = PackedStringArray(["s%d" % (s - 1)])
		out.append(n)
	return out


## Lumen `st` needs to own `index` at `target` from what it holds now.
static func cost_to(st: BuildState, index: int, target: int) -> int:
	var it := st.catalog.at(index)
	if it == null:
		return -1
	var held := st.held(index)
	if st.v2 and it.tier != ArmoryItemDef.Tier.NONE:
		return int(RecipeMath.resolve(st.catalog, st.pool, index)["cost"])
	if st.v2 and (it.kind == ArmoryItemDef.Kind.AMMO or it.kind == ArmoryItemDef.Kind.AMMO_MOD):
		return 0 if held > 0 else it.price(1)
	match it.kind:
		ArmoryItemDef.Kind.CONSUMABLE:
			return it.price(1) * maxi(0, target - held)
		ArmoryItemDef.Kind.SQUAD:
			return 0 if held > 0 else it.price(1)
	var t := clampi(target, 1, it.tiers())
	if held >= t:
		return 0
	if held > 0:
		return EconomyMath.upgrade_cost(it, t, held)
	return maxi(0, it.price(t) - st.swap_credit(index))


# --- node state -------------------------------------------------------------------

static func _satisfied(st: BuildState, item_id: StringName, target: int, keep: bool = false) -> bool:
	var i := st.catalog.index_of(item_id)
	if i < 0:
		return false
	var it := st.catalog.at(i)
	if st.v2 and it.tier != ArmoryItemDef.Tier.NONE:
		# Owned, or already built into an owned item (a used-up part stays done).
		return st.held(i) > 0 or (not keep and st.built_into(i))
	var t := target if it.kind == ArmoryItemDef.Kind.CONSUMABLE else mini(target, it.tiers())
	return st.held(i) >= t


static func _done(n: BuildNodeDef, st: BuildState) -> bool:
	if _satisfied(st, n.item_id, n.target_or_one(), n.keep):
		return true
	for a in n.alternatives:
		if _satisfied(st, StringName(a), n.target_or_one(), n.keep):
			return true
	return false


## True when this hero can never buy the node's item (unknown, disabled, wrong family).
static func _item_unavailable(st: BuildState, item_id: StringName) -> bool:
	var it := st.catalog.find(item_id)
	return it == null or it.disabled or not st.fits(it)


static func _unavailable(n: BuildNodeDef, st: BuildState) -> bool:
	if not _item_unavailable(st, n.item_id):
		return false
	for a in n.alternatives:
		if not _item_unavailable(st, StringName(a)):
			return false
	return true


static func _fallback_active(n: BuildNodeDef, st: BuildState, by_id: Dictionary) -> bool:
	for r in n.requires:
		var p: BuildNodeDef = by_id.get(StringName(r))
		if p != null and _unavailable(p, st):
			return true
	return n.requires.is_empty()


## Matched rule ids of `n` (conditions only).
static func _matched_conditions(n: BuildNodeDef, st: BuildState, ar: AdviceRulesDef) -> PackedStringArray:
	var out := PackedStringArray()
	for c in n.conditions:
		if _rule_matches(c, n, st, ar):
			out.append(c)
	return out


## True when node `id` no longer holds later nodes back.
static func _passed(id: StringName, st: BuildState, ar: AdviceRulesDef, by_id: Dictionary, memo: Dictionary) -> bool:
	if memo.has(id):
		return memo[id]
	memo[id] = false  # cycle guard (the validator reports cycles)
	var n: BuildNodeDef = by_id.get(id)
	var ok := true
	if n != null and not _done(n, st) and not n.optional and not _unavailable(n, st):
		if n.fallback and not _fallback_active(n, st, by_id):
			ok = true
		elif n.skippable and (not n.in_window(st.time_s)
				or (not n.conditions.is_empty() and _matched_conditions(n, st, ar).is_empty())):
			ok = true
		else:
			ok = false
	memo[id] = ok
	return ok


## "" when `n` is offered now, else why not (trace text).
static func _offer_check(n: BuildNodeDef, st: BuildState, ar: AdviceRulesDef, by_id: Dictionary, memo: Dictionary) -> String:
	if _unavailable(n, st):
		return "not available for this hero"
	if n.fallback and not _fallback_active(n, st, by_id):
		return "fallback not needed"
	for r in n.requires:
		if not _passed(StringName(r), st, ar, by_id, memo):
			return "waits for %s" % r
	if not n.in_window(st.time_s):
		return "outside %d..%d s" % [n.min_s, n.max_s]
	if not n.conditions.is_empty() and _matched_conditions(n, st, ar).is_empty():
		return "conditions [%s] not met" % ", ".join(n.conditions)
	var idx := _buy_index(n, st)
	if st.v2 and idx < 0:
		return "blocked (Signature limit, Ammo Type, slots)"
	var it := st.catalog.at(idx)
	if it != null and it.requires != &"" and st.held(st.catalog.index_of(it.requires)) <= 0:
		return "needs %s first" % it.requires
	return ""


# --- Armory v2 (items-and-armory.md §3.10) ------------------------------------------

## The node choice to build toward: among the node's item and its
## alternatives (the step's 2-3 choices), the buyable one with the most Lumen
## of parts already owned (Total - remaining cost); ties keep data order, so
## with nothing owned the guide's first choice wins. -1 when all are blocked.
static func _goal_v2(n: BuildNodeDef, st: BuildState) -> int:
	var best := -1
	var best_owned := -1
	for id in [n.item_id] + Array(n.alternatives):
		var i := st.catalog.index_of(StringName(id))
		if i < 0 or _item_unavailable(st, StringName(id)) or _blocked_v2(st, i) != "":
			continue
		var owned := RecipeMath.total(st.catalog, i) - cost_to(st, i, 1)
		if owned > best_owned:
			best = i
			best_owned = owned
	return best


## Why the server would refuse buying `index` outright ("" = it would not).
static func _blocked_v2(st: BuildState, index: int) -> String:
	var it := st.catalog.at(index)
	if it == null:
		return "unknown"
	if it.tier == ArmoryItemDef.Tier.SIGNATURE and st.held(index) <= 0 \
			and st.signature_count() >= st.signature_limit:
		return "signature limit"
	if it.tier != ArmoryItemDef.Tier.NONE and it.recipe.is_empty() and st.slots_used >= st.open_slots:
		return "no free open slot"
	if it.kind == ArmoryItemDef.Kind.AMMO_MOD:
		var ammo := st.catalog.at(st.chamber(ItemInventory.LOC_AMMO))
		if ammo == null:
			return "needs an Ammo Type"
		if not it.fits_ammo.is_empty() and not it.fits_ammo.has(ammo.ammo_type):
			return "does not fit the loaded ammo"
	return ""


## Open slots after buying `index` with `take` used up.
static func _slots_after(st: BuildState, index: int, take: Array) -> int:
	var used := st.slots_used
	for t in take:
		if int(t["loc"]) >= ItemInventory.LOC_SLOT:
			used -= 1
	var it := st.catalog.at(index)
	return used + (1 if it != null and it.uses_open_slot() else 0)


## The next purchase toward `goal` (§3.10 rule 2): the goal itself when it is
## affordable and fits; else the largest affordable missing Assembly; else the
## cheapest missing component that gives stats now (not a spare) and fits a
## slot; else the goal (shown as "save for"). Returns {index, cost, fits}:
## `fits` is false when buying it now would overflow the open slots.
static func next_part(st: BuildState, goal: int) -> Dictionary:
	var it := st.catalog.at(goal)
	var full_cost := cost_to(st, goal, 1)
	if it == null or it.tier == ArmoryItemDef.Tier.NONE or it.recipe.is_empty():
		return {"index": goal, "cost": full_cost, "fits": _blocked_v2(st, goal) == ""}
	var full := RecipeMath.resolve(st.catalog, st.pool, goal)
	var goal_fits := _slots_after(st, goal, full["take"]) <= st.open_slots
	if full_cost <= st.lumen and goal_fits:
		return {"index": goal, "cost": full_cost, "fits": true}
	var missing := RecipeMath.missing(st.catalog, st.pool, goal)
	var best := -1
	var best_total := -1
	var best_cost := 0
	for m in missing:
		var mit := st.catalog.at(m)
		if mit == null or mit.tier != ArmoryItemDef.Tier.ASSEMBLY:
			continue
		var r := RecipeMath.resolve(st.catalog, st.pool, m)
		var total := RecipeMath.total(st.catalog, m)
		if int(r["cost"]) <= st.lumen and _slots_after(st, m, r["take"]) <= st.open_slots and total > best_total:
			best = m
			best_total = total
			best_cost = int(r["cost"])
	if best >= 0:
		return {"index": best, "cost": best_cost, "fits": true}
	var cheapest := -1
	var cheapest_cost := 1 << 30
	for m in missing:
		var mit := st.catalog.at(m)
		if mit == null or mit.tier != ArmoryItemDef.Tier.COMPONENT or st.held(m) > 0:
			continue  # an owned id would only be a spare
		if st.slots_used + 1 > st.open_slots:
			break
		if mit.price(1) < cheapest_cost:
			cheapest = m
			cheapest_cost = mit.price(1)
	if cheapest >= 0:
		return {"index": cheapest, "cost": cheapest_cost, "fits": true}
	return {"index": goal, "cost": full_cost, "fits": goal_fits}


## The item actually recommended for `n`: a line the hero already holds
## (its own item first, then an alternative: never suggest swapping a held
## line out), else its own item, else the first buyable alternative.
static func _buy_index(n: BuildNodeDef, st: BuildState) -> int:
	if st.v2:
		return _goal_v2(n, st)
	for id in [n.item_id] + Array(n.alternatives):
		var hi := st.catalog.index_of(StringName(id))
		if hi >= 0 and st.held(hi) > 0 and not _item_unavailable(st, StringName(id)):
			return hi
	if not _item_unavailable(st, n.item_id):
		return st.catalog.index_of(n.item_id)
	for a in n.alternatives:
		if not _item_unavailable(st, StringName(a)):
			return st.catalog.index_of(StringName(a))
	return -1


static func _advise(n: BuildNodeDef, st: BuildState, ar: AdviceRulesDef) -> Advice:
	var a := Advice.new()
	a.node = n
	a.section = n.section
	a.target = n.target_or_one()
	a.item_index = _buy_index(n, st)
	a.situational = not n.conditions.is_empty()
	a.cost = cost_to(st, a.item_index, a.target)
	if st.v2:
		a.goal_index = a.item_index
		var nxt := next_part(st, a.goal_index)
		a.item_index = int(nxt["index"])
		a.cost = int(nxt["cost"])
		if not bool(nxt["fits"]):
			a.cost = 1 << 30  # would overflow the open slots: never "affordable"
	a.affordable = a.cost >= 0 and a.cost <= st.lumen
	a.soon = a.affordable or (a.cost >= 0 and a.cost - st.lumen <= ar.expected_income_per_min * ar.affordable_soon_s / 60.0)
	for alt in n.alternatives:
		var ai := st.catalog.index_of(StringName(alt))
		if ai >= 0 and ai != a.item_index and not _item_unavailable(st, StringName(alt)):
			a.alternatives.append(ai)
	var rules := _matched_conditions(n, st, ar)
	for auto in ["core_tier_ready", "affordable_now", "counters_enemy"]:
		if not rules.has(auto) and _rule_matches(auto, n, st, ar):
			rules.append(auto)
	a.rules = rules
	a.score = float(n.priority)
	var best := ""
	for r in rules:
		a.score += ar.bonus_of(r)
		# Headline reason: the strongest situational rule (never the generic
		# "affordable" / "next tier" bonuses, which only reorder). A named
		# enemy_<tag> rule beats the generic "counters the enemy" line.
		if r not in GENERIC_RULES and (best == "" or ar.bonus_of(r) > ar.bonus_of(best)):
			best = r
	if best == "" and rules.has("counters_enemy"):
		best = "counters_enemy"
	var it := st.catalog.at(a.item_index)
	if best != "":
		a.reason_key = RULE_REASON_PREFIX + best.to_upper()
	elif n.reason_key != "":
		a.reason_key = n.reason_key
	elif rules.has("core_tier_ready"):
		a.reason_key = RULE_REASON_PREFIX + "CORE_TIER_READY"
	elif it != null and it.explain_key != "":
		a.reason_key = it.explain_key
	else:
		a.reason_key = SECTION_REASONS[clampi(n.section, 0, SECTION_REASONS.size() - 1)]
	return a


# --- rules ------------------------------------------------------------------------

static func _rule_matches(rule: String, n: BuildNodeDef, st: BuildState, ar: AdviceRulesDef) -> bool:
	if SIGNAL_RULES.has(rule):
		return (st.signals & int(SIGNAL_RULES[rule])) != 0
	if rule.begins_with("enemy_"):
		var tag := rule.trim_prefix("enemy_")
		return int(st.enemy_tags.get(tag, 0)) >= ar.tag_threshold(st.team_size, tag)
	match rule:
		"core_tier_ready":
			if st.v2:  # every part owned: only the combine is left
				var g := _buy_index(n, st)
				return g >= 0 and st.catalog.at(g).tier != ArmoryItemDef.Tier.NONE \
					and not st.catalog.at(g).recipe.is_empty() \
					and RecipeMath.missing(st.catalog, st.pool, g).is_empty() and cost_to(st, g, 1) <= st.lumen
			var i := _buy_index(n, st)
			var it := st.catalog.at(i)
			return it != null and it.kind == ArmoryItemDef.Kind.MOUNT and st.held(i) > 0 \
				and st.held(i) + 1 == mini(n.target_or_one(), it.tiers()) and cost_to(st, i, n.target_or_one()) <= st.lumen
		"affordable_now":
			var c := cost_to(st, _buy_index(n, st), n.target_or_one())
			return c >= 0 and c <= st.lumen
		"counters_enemy":
			var it := st.catalog.at(_buy_index(n, st))
			if it == null:
				return false
			for t in it.counter_tags:
				if int(st.enemy_tags.get(t, 0)) >= ar.tag_threshold(st.team_size, t):
					return true
			return false
		"team_lacks_sustain":
			return int(st.ally_roles.get("healer", 0)) == 0
		"team_lacks_frontline":
			return int(st.ally_roles.get("tank", 0)) == 0
	return false
