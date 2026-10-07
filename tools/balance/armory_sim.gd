extends RefCounted
## Armory balance report (docs/armory.md "Balance check"). Runs every hero's
## default guide along the average-player Lumen curve (wardlings-and-economy.md
## §18, the model in tests/unit/economy/economy_curve_test.gd) and buys through
## the real server path: BuildState.from_hero -> BuildAdvisor.best() ->
## Armory.buy, the same steps a bot takes (bot_brain.gd _decide_shop).
##
## Reports, per hero and economy (slice .tres / GDD defaults) and visit pattern
## (always on the pad = when the step becomes affordable; one visit every
## VISIT_S = when a player who returns on death or recall buys it):
## the purchase timeline, the first spike and the core path done time, dead
## zones (no purchase for DEAD_ZONE_S while saving), Lumen left unspent;
## then items no guide names, items no simulated hero buys, how different the
## seven builds are, and the tier steps whose Lumen value is out of line.
##
## Observations only, no verdicts: the economy designer reads the file.
##
## Run through tools/balance/armory_report.gd; tests/unit/economy/armory_report_test.gd checks it.

const CurveModel := preload("res://tests/unit/economy/economy_curve_test.gd")
const HEROES_DIR := "res://assets/data/heroes/"
const SLICE_RULES := "res://assets/data/economy/economy_rules_slice.tres"
const MATCH_S := 1800
## A player who walks back on death or recall (GDD §18: 0.17 deaths per minute
## for an average player is one about every 6 minutes; recalls fill the rest).
const VISIT_S := 180
const DEAD_ZONE_S := 240
const HZ := 30

var _cat: ArmoryCatalogDef
var guides: RecommendedBuildsDef
var _ar: AdviceRulesDef
var heroes: Array[HeroDef] = []
var _out := PackedStringArray()


func _init() -> void:
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	guides = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	_ar = load(AdviceRulesDef.DEFAULT_PATH) as AdviceRulesDef
	for f in DirAccess.get_files_at(HEROES_DIR):
		if f.ends_with(".tres"):
			var d := load(HEROES_DIR + f) as HeroDef
			if d != null:
				heroes.append(d)
	heroes.sort_custom(func(a: HeroDef, b: HeroDef) -> bool: return String(a.id) < String(b.id))


## The whole Markdown report.
func report() -> String:
	_out.clear()
	_report()
	return "\n".join(_out) + "\n"


func _p(line: String = "") -> void:
	_out.append(line)


## Earned Lumen after each second of the match (index = second - 1).
static func curve(r: EconomyRulesDef, sentinels: bool) -> Array:
	var s: Array = []
	CurveModel.run_model(r, sentinels, 900.0, s)
	return s


## Spends `guide` along `earned`. visit_s 0 = always on the pad. `enemies`
## gives the threat tags (situational nodes); returns the purchases
## [{t, id, target, cost, node, section}] plus "left" and "spent".
func simulate(hero: HeroDef, guide: RecommendedBuildDef, r: EconomyRulesDef, earned: Array, visit_s: int,
		enemies: Array[HeroDef]) -> Dictionary:
	var p := HeroProgress.new(1)
	var c := HeroCombat.new(hero, 0, HZ, 1)
	var buys: Array = []
	var prev := 0
	for sec in range(0, MATCH_S + 1):
		var total := int(r.starting_purse) if sec == 0 else floori(earned[sec - 1])
		p.lumen += total - prev
		prev = total
		var on_pad := visit_s <= 0 or sec % visit_s == 0
		if not on_pad:
			continue
		p.at_armory = true
		for _guard in 40:
			var st := BuildState.from_hero(p, _cat, hero.weapon, r)
			st.time_s = sec
			st.mode = &"5v5"
			for e in enemies:
				st.add_enemy(e)
			st.add_ally(hero)
			var a := BuildAdvisor.evaluate(guide, st, _ar).best()
			if a == null or not a.affordable or a.item_index < 0:
				break
			var it := _cat.at(a.item_index)
			var tier := a.target if it.kind == ArmoryItemDef.Kind.MOUNT else 0
			var before := p.lumen
			if Armory.buy(p, c, _cat, a.item_index, tier, r) != HeroProgress.Result.OK:
				break
			buys.append({"t": sec, "id": String(it.id), "target": a.target, "cost": before - p.lumen,
				"node": String(a.node.id) if a.node != null else "", "section": a.section if a.node != null else -1,
				"core": a.node.core if a.node != null else false})
		p.end_visit()
		p.at_armory = false
	return {"buys": buys, "left": p.lumen, "spent": p.spent_lumen}


static func mmss(t: int) -> String:
	return "%d:%02d" % [t / 60, t % 60]


## First time each section is reached and when the last core step lands.
static func milestones(buys: Array) -> Dictionary:
	var spike := -1
	var core_done := -1
	for b in buys:
		if spike < 0 and int(b["section"]) == BuildNodeDef.Section.SPIKE:
			spike = int(b["t"])
		if bool(b["core"]):
			core_done = int(b["t"])
	return {"spike": spike, "core": core_done}


## Gaps longer than DEAD_ZONE_S between purchases (start and end included).
static func dead_zones(buys: Array) -> Array:
	var out: Array = []
	var last := 0
	for b in buys:
		if int(b["t"]) - last > DEAD_ZONE_S:
			out.append([last, int(b["t"])])
		last = int(b["t"])
	if MATCH_S - last > DEAD_ZONE_S:
		out.append([last, MATCH_S])
	return out


func _report() -> void:
	var slice := load(SLICE_RULES) as EconomyRulesDef
	var gdd := EconomyRulesDef.new()
	var econs := [["slice", slice, curve(slice, false)], ["gdd", gdd, curve(gdd, true)]]
	_p("# Armory balance report (generated)")
	_p()
	_p("Generated by `tools/balance/armory_report.gd` (do not edit by hand; rerun it).")
	_p("Lumen: the §18 average-player model (`economy_curve_test.gd`), slice rules = %s (trickle %d/min, no Sentinels), gdd = EconomyRulesDef defaults (trickle %d/min, Sentinels)." % [
		SLICE_RULES.get_file(), int(slice.trickle_per_min), int(gdd.trickle_per_min)])
	_p("Purchases go BuildState.from_hero -> BuildAdvisor.best() -> Armory.buy (the bot path). \"pad\" = always on the Armory pad (the step's affordable time); \"visit %ds\" = on the pad once every %d s." % [VISIT_S, VISIT_S])
	_p("Enemy picture: \"neutral\" = no threat tags; \"all\" = the other six heroes' tags (situational nodes can fire).")
	_p("Catalog: %d items. Guides: %d." % [_cat.items.size(), guides.builds.size()])
	_p()
	_p("Earned Lumen (model): " + ", ".join(econs.map(func(e: Array) -> String:
		var s: Array = e[2]
		return "%s %d / %d / %d / %d at 5/10/20/30 min" % [e[0], s[299], s[599], s[1199], s[1799]])))
	_p()
	var bought_any := {}
	var sets := {}
	var summary: Array = []
	for hero in heroes:
		var guide := guides.for_hero(hero.id)
		if guide == null:
			_p("## %s: NO GUIDE" % hero.display_name)
			continue
		var others: Array[HeroDef] = []
		for o in heroes:
			if o != hero:
				others.append(o)
		_p("## %s (%s)" % [hero.display_name, guide.display_name])
		_p()
		for e in econs:
			for vs in [["neutral", [] as Array[HeroDef]], ["all", others]]:
				for v in [0, VISIT_S]:
					var res := simulate(hero, guide, e[1], e[2], v, vs[1])
					var buys: Array = res["buys"]
					var ms := milestones(buys)
					var dz := dead_zones(buys)
					var tag := "%s / %s / %s" % [e[0], "pad" if v == 0 else "visit %ds" % v, vs[0]]
					summary.append([hero.display_name, tag, ms["spike"], ms["core"], int(res["left"]), buys.size(), dz.size()])
					var ids := {}
					for b in buys:
						ids[b["id"]] = true
						bought_any[b["id"]] = true
					if e[0] == "slice" and v == VISIT_S and vs[0] == "neutral":
						sets[hero.display_name] = ids
					# Full timeline only for the shipped economy; the rest are summarized.
					if e[0] != "slice" or vs[0] != "neutral":
						continue
					_p("### %s" % tag)
					_p()
					_p("| time | item | tier/count | Lumen | node | section |")
					_p("|---|---|---|---|---|---|")
					for b in buys:
						_p("| %s | %s | %d | %d | %s | %s |" % [mmss(b["t"]), b["id"], b["target"], b["cost"], b["node"],
							BuildNodeDef.Section.keys()[b["section"]] if int(b["section"]) >= 0 else "-"])
					_p()
					_p("First spike %s, core path done %s, %d Lumen unspent at 30:00, spent %d." % [
						mmss(ms["spike"]) if ms["spike"] >= 0 else "never", mmss(ms["core"]) if ms["core"] >= 0 else "never",
						res["left"], res["spent"]])
					if not dz.is_empty():
						_p("Dead zones (> %d s without a purchase): %s." % [DEAD_ZONE_S, ", ".join(dz.map(func(z: Array) -> String:
							return "%s-%s" % [mmss(z[0]), mmss(z[1])]))])
					_p()
	_p("## Summary (all runs)")
	_p()
	_p("| hero | run | first spike | core done | unspent 30:00 | purchases | dead zones |")
	_p("|---|---|---|---|---|---|---|")
	for s in summary:
		_p("| %s | %s | %s | %s | %d | %d | %d |" % [s[0], s[1], mmss(s[2]) if s[2] >= 0 else "never",
			mmss(s[3]) if s[3] >= 0 else "never", s[4], s[5], s[6]])
	_p()
	_report_coverage(bought_any)
	_report_diversity(sets)
	_report_tier_value()


func _report_coverage(bought_any: Dictionary) -> void:
	var named := {}
	for g in guides.builds:
		for n in g.nodes:
			named[String(n.item_id)] = true
			for alt in n.alternatives:
				named[String(alt)] = true
		for id in g.item_ids:
			named[String(id)] = true
	var unnamed: Array = []
	var unbought: Array = []
	for it in _cat.items:
		if it == null:
			continue
		if not named.has(String(it.id)):
			unnamed.append(String(it.id))
		if not bought_any.has(String(it.id)):
			unbought.append(String(it.id))
	_p("## Coverage")
	_p()
	_p("Items no guide names (node or alternative): %s." % (", ".join(unnamed) if not unnamed.is_empty() else "none"))
	_p("Items no simulated run buys: %s." % (", ".join(unbought) if not unbought.is_empty() else "none"))
	_p()


func _report_diversity(sets: Dictionary) -> void:
	_p("## Build diversity (slice, visit %ds, neutral)" % VISIT_S)
	_p()
	var names := sets.keys()
	var total := 0.0
	var pairs := 0
	var closest := ["", "", -1.0]
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Dictionary = sets[names[i]]
			var b: Dictionary = sets[names[j]]
			var inter := 0
			for id in a:
				if b.has(id):
					inter += 1
			var uni := a.size() + b.size() - inter
			var jac := float(inter) / maxf(uni, 1.0)
			total += jac
			pairs += 1
			if jac > closest[2]:
				closest = [names[i], names[j], jac]
	var distinct := {}
	for n in names:
		for id in sets[n]:
			distinct[id] = true
	_p("Distinct items bought across heroes: %d of %d. Mean pairwise overlap (Jaccard): %.2f. Closest pair: %s / %s (%.2f)." % [
		distinct.size(), _cat.items.size(), total / maxf(pairs, 1.0), closest[0], closest[1], closest[2]])
	_p()


## Lumen per unit of the primary stat, per tier step, against the line's Tier I.
func _report_tier_value() -> void:
	_p("## Tier value (primary stat gained per 100 Lumen, step vs Tier I)")
	_p()
	_p("| item | stat | T1 | T2 step | T3 step | note |")
	_p("|---|---|---|---|---|---|")
	for it in _cat.items:
		if it == null or it.tiers() < 2 or it.values.size() < it.tiers():
			continue
		# values are absolute per tier, prices are list prices (upgrade = list(new) - list(held)).
		var base := 1.0 if it.op == Modifier.Op.MUL else 0.0
		var eff: Array = []
		for t in it.tiers():
			var dv := absf(it.values[t] - (it.values[t - 1] if t > 0 else base))
			var dc := float(it.prices[t] - (it.prices[t - 1] if t > 0 else 0))
			eff.append(dv / maxf(dc, 1.0) * 100.0)
		var notes: Array = []
		for t in range(1, eff.size()):
			var ratio: float = eff[t] / maxf(eff[0], 1e-9)
			if ratio > 1.0:
				notes.append("T%d step better value than T1 (x%.2f)" % [t + 1, ratio])
			elif ratio < 0.4:
				notes.append("T%d step weak (x%.2f)" % [t + 1, ratio])
		_p("| %s | %s | %.4f | %s | %s | %s |" % [it.id, it.stat, eff[0],
			"%.4f" % eff[1] if eff.size() > 1 else "-", "%.4f" % eff[2] if eff.size() > 2 else "-",
			"; ".join(notes) if not notes.is_empty() else ""])
	_p()
