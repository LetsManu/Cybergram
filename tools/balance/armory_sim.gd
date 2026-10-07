extends RefCounted
## Armory v2 balance report (items-and-armory.md §3.10 rule 7, §4.7; docs/armory.md
## "Balance check"). Spends every hero's v22 guide along the §18 Lumen curve
## through the bot path: BuildState.from_hero -> BuildAdvisor.best() (next
## part) -> ItemShop.buy, selling a loose item the guide never uses when the
## slots are full (bot_brain.gd).
##
## Income profiles (wardlings-and-economy.md §18): average = the model in
## economy_curve_test.gd; weak / strong = the same curve above the purse
## scaled so 30:00 lands on the GDD's 6,320 / 12,280.
## Per hero, profile and visit pattern: time of the first Signature, time the
## full build is owned, share of the full build owned at 30:00, unspent
## Lumen, dead zones (> 240 s without a purchase), spend split (items /
## squad / consumables); then items no run buys.
##
## Observations only, no verdicts. Run: tools/balance/armory_report.gd
## (tests/unit/economy/armory_report_test.gd checks the simulation).

const CurveModel := preload("res://tests/unit/economy/economy_curve_test.gd")
const HEROES_DIR := "res://assets/data/heroes/"
const SLICE_RULES := "res://assets/data/economy/economy_rules_slice.tres"
const MATCH_S := 1800
const VISIT_S := 180
const DEAD_ZONE_S := 240
const HZ := 30
## GDD AC 16 looks for the full build between 28 and 33 minutes.
const FULL_HORIZON_S := 2100
## Sim assumption: the player uses one Med-Pack every MED_USE_S seconds
## (about the GDD's heal-on-pressure cadence); the guide's restock step buys it back.
const MED_USE_S := 210
## Threat scenario (opts "threat"): every counter / defensive Situational node opens.
const THREAT_SIGNALS := 1 | 2 | 64
const THREAT_TAGS := {"frontline": 2, "squad": 2, "sustain": 2, "cc": 2, "zone": 2, "skill_dps": 2,
	"weapon_dps": 2, "burst": 2}
## §18 30:00 Lumen of the weak and strong profiles.
const WEAK_30 := 6320.0
const STRONG_30 := 12280.0

var cat: ArmoryCatalogDef
var guides: RecommendedBuildsDef
var ar: AdviceRulesDef
var heroes: Array[HeroDef] = []
var _out := PackedStringArray()


func _init() -> void:
	cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	guides = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	ar = load(AdviceRulesDef.DEFAULT_PATH) as AdviceRulesDef
	for f in DirAccess.get_files_at(HEROES_DIR):
		if f.ends_with(".tres"):
			var d := load(HEROES_DIR + f) as HeroDef
			if d != null:
				heroes.append(d)
	heroes.sort_custom(func(a: HeroDef, b: HeroDef) -> bool: return String(a.id) < String(b.id))


## Earned Lumen after each second of the match (index = second - 1).
static func curve(r: EconomyRulesDef, sentinels: bool) -> Array:
	var s: Array = []
	CurveModel.run_model(r, sentinels, 900.0, s)
	return s


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


## `base` (earned Lumen per second, starts at the purse) scaled above the purse
## so its last value becomes `end_value`.
static func scaled(base: Array, purse: float, end_value: float) -> Array:
	var k := (end_value - purse) / maxf(1.0, float(base[base.size() - 1]) - purse)
	return base.map(func(v: float) -> float: return purse + (v - purse) * k)


## Spends `guide` along `earned` (visit_s 0 = always on the pad). `opts`:
## "threat" (bool) opens the Situational nodes, "full_value" (int) records when
## the owned value first reaches it ("full_at"). Returns
## {buys: [{t, id, cost, kind}], sells, left, owned_value, first_sig, full_at, items, squad, consumables}.
func simulate(hero: HeroDef, guide: RecommendedBuildDef, r: EconomyRulesDef, earned: Array, visit_s: int,
		opts: Dictionary = {}) -> Dictionary:
	var p := HeroProgress.new(1)
	var holder := HeroBody.new()
	holder.setup(MovementDef.new(), Vector3.ZERO, false)
	holder.combat = HeroCombat.new(hero, 0, HZ, 1)
	var c := holder.combat
	var buys: Array = []
	var sells := 0
	var spent := {"items": 0, "squad": 0, "consumables": 0}
	var first_sig := -1
	var full_at := -1
	var full_value := int(opts.get("full_value", 0))
	var prev := 0
	var need := 0  # Lumen the advisor's pick costs while it is out of reach (skip the evaluation until then)
	var recheck := 0
	var plan := _plan(guide)
	for sec in range(0, earned.size() + 1):
		var total := int(r.starting_purse) if sec == 0 else floori(earned[sec - 1])
		p.lumen += total - prev
		prev = total
		if sec > 0 and sec % MED_USE_S == 0 and p.medpacks > 0:
			p.medpacks -= 1  # used one since the last look
			need = 0
		if visit_s > 0 and sec % visit_s != 0:
			continue
		if p.lumen < need and sec < recheck:
			continue  # nothing changed: the same pick is still out of reach
		need = 0
		p.at_armory = true
		for _guard in 40:
			var st := BuildState.from_hero(p, cat, hero.weapon, r)
			st.time_s = sec
			st.mode = &"5v5"
			if bool(opts.get("threat", false)):
				st.signals = THREAT_SIGNALS
				st.enemy_tags = THREAT_TAGS.duplicate()
			var a := BuildAdvisor.evaluate(guide, st, ar).best()
			if a == null:
				break
			if not a.affordable and a.cost >= (1 << 30) and st.slots_used >= st.open_slots:
				var loc := _sell_loc(p, plan)
				if loc < 0 or ItemShop.sell(p, c, cat, loc, r) != HeroProgress.Result.OK:
					break
				sells += 1
				continue
			if not a.affordable or a.item_index < 0:
				if not a.affordable and a.cost < (1 << 30):
					need = a.cost
					recheck = sec + 30
				break
			var before := p.lumen
			if ItemShop.buy(p, c, cat, a.item_index, r) != HeroProgress.Result.OK:
				break
			var it := cat.at(a.item_index)
			var paid := before - p.lumen
			var kind := "squad" if it.kind == ArmoryItemDef.Kind.SQUAD else \
				"consumables" if it.kind == ArmoryItemDef.Kind.CONSUMABLE else "items"
			spent[kind] += paid
			buys.append({"t": sec, "id": String(it.id), "cost": paid, "kind": kind})
			if first_sig < 0 and it.tier == ArmoryItemDef.Tier.SIGNATURE:
				first_sig = sec
			if full_value > 0 and full_at < 0 and _owned_value(p) >= full_value:
				full_at = sec
		p.end_visit()
		p.at_armory = false
	var value := _owned_value(p)
	holder.free()
	return {"buys": buys, "sells": sells, "left": p.lumen, "owned_value": value, "first_sig": first_sig,
		"full_at": full_at,
		"items": spent["items"], "squad": spent["squad"], "consumables": spent["consumables"]}


## Every item id a guide names: a node's item, its choices, and the recipe parts of those.
func _named_items() -> Dictionary:
	var named := {}
	for g in guides.builds:
		for n in g.nodes:
			_name_item(named, String(n.item_id))
			for alt in n.alternatives:
				_name_item(named, String(alt))
	return named


func _name_item(named: Dictionary, id: String) -> void:
	if named.has(id):
		return
	named[id] = true
	var it := cat.find(StringName(id))
	if it != null:
		for part in it.recipe:
			_name_item(named, String(part))


func _owned_value(p: HeroProgress) -> int:
	var value := 0
	for e in p.inv.pool():
		value += RecipeMath.total(cat, int(e["index"]))
	return value


## `guide` without its Squad-upgrade nodes (the "no squad spend" reference of the GDD).
func without_squad(guide: RecommendedBuildDef) -> RecommendedBuildDef:
	var g := guide.duplicate(true) as RecommendedBuildDef
	var keep: Array[BuildNodeDef] = []
	for n in g.nodes:
		var it := cat.find(n.item_id)
		if it == null or it.kind != ArmoryItemDef.Kind.SQUAD:
			keep.append(n)
	g.nodes = keep
	return g


func _plan(guide: RecommendedBuildDef) -> Dictionary:
	var plan := {}
	for n in guide.nodes:
		if n != null:
			for id in [n.item_id] + Array(n.alternatives):
				_add(plan, cat.index_of(StringName(id)))
	return plan


func _add(plan: Dictionary, index: int) -> void:
	var it := cat.at(index)
	if it == null or plan.has(index):
		return
	plan[index] = true
	for part in it.recipe:
		_add(plan, cat.index_of(StringName(part)))


func _sell_loc(p: HeroProgress, plan: Dictionary) -> int:
	var best := -1
	var best_v := 1 << 30
	for i in p.inv.slots.size():
		var idx: int = p.inv.slots[i].index
		var v := RecipeMath.total(cat, idx)
		if not plan.has(idx) and v < best_v:
			best = ItemInventory.LOC_SLOT + i
			best_v = v
	return best


## `earned` continued to `seconds` at its last minute's rate.
static func extended(earned: Array, seconds: int) -> Array:
	var out := earned.duplicate()
	var rate := (float(earned[earned.size() - 1]) - float(earned[earned.size() - 61])) / 60.0
	while out.size() < seconds:
		out.append(float(out[out.size() - 1]) + rate)
	return out


static func mmss(t: int) -> String:
	return "%d:%02d" % [t / 60, t % 60] if t >= 0 else "never"


## The report. `quick` runs the average curve on the pad only (tuning loop).
func report(quick: bool = false) -> String:
	_out.clear()
	var r := load(SLICE_RULES) as EconomyRulesDef
	var avg := curve(r, false)
	var purse := float(r.starting_purse)
	var strong := scaled(avg, purse, STRONG_30)
	var profiles := [["weak", scaled(avg, purse, WEAK_30)], ["average", avg], ["strong", strong]]
	var visits := [0, VISIT_S]
	if quick:
		profiles = [["average", avg]]
		visits = [0]
	var unlimited: Array = []
	unlimited.resize(MATCH_S)
	unlimited.fill(100000.0)
	_p("# Armory v2 balance report (generated)")
	_p()
	_p("Generated by `tools/balance/armory_report.gd` (do not edit by hand).")
	_p("Catalog %s (%d items), guides %s. Purchases: BuildAdvisor next part -> ItemShop.buy; full slots -> sell a loose item the guide never uses. Med-Packs: one used every %d s." % [
		ArmoryCatalogDef.DEFAULT_PATH.get_file(), cat.items.size(), RecommendedBuildsDef.DEFAULT_PATH.get_file(), MED_USE_S])
	_p("Lumen at 30:00: weak %d, average %d, strong %d (§18). \"pad\" = always on the Armory pad; \"visit\" = every %d s." % [
		int(WEAK_30), int(avg[MATCH_S - 1]), int(strong[MATCH_S - 1]), VISIT_S])
	_p()
	_p("| hero | profile | visits | first Signature | full build value | owned at 30:00 | unspent | items / squad / consumables | dead zones | sells |")
	_p("|---|---|---|---|---|---|---|---|---|---|")
	var bought := {}
	var full_rows := PackedStringArray()
	for hero in heroes:
		var g := guides.for_hero(hero.id)
		if g == null:
			_p("| %s | NO GUIDE | | | | | | | | |" % hero.display_name)
			continue
		var full: Dictionary = simulate(hero, g, r, unlimited, 0)
		var full_value: int = full["owned_value"]
		for prof in profiles:
			for v in visits:
				var run := simulate(hero, g, r, prof[1], v)
				for b in run["buys"]:
					bought[b["id"]] = true
				var spent := maxi(1, int(run["items"]) + int(run["squad"]) + int(run["consumables"]))
				var dz := dead_zones(run["buys"])
				_p("| %s | %s | %s | %s | %d | %d%% | %d | %d%% / %d%% / %d%% | %d | %d |" % [hero.display_name, prof[0],
					"pad" if v == 0 else "%ds" % v, mmss(run["first_sig"]), full_value,
					roundi(100.0 * float(run["owned_value"]) / maxf(1.0, full_value)), run["left"],
					roundi(100.0 * int(run["items"]) / spent), roundi(100.0 * int(run["squad"]) / spent),
					roundi(100.0 * int(run["consumables"]) / spent), dz.size(), run["sells"]])
		# Strong curve, no squad upgrades: when is the full build complete (GDD AC 16: 28-33 min)?
		var ns: Dictionary = simulate(hero, without_squad(g), r, extended(strong, FULL_HORIZON_S), 0,
			{"full_value": full_value})
		full_rows.append("| %s | %s | %d%% |" % [hero.display_name, mmss(int(ns["full_at"])),
			roundi(100.0 * float(ns["owned_value"]) / maxf(1.0, full_value))])
		# Coverage: what the guide asks for with unlimited Lumen, plain and with every Situational node open.
		for b in full["buys"]:
			bought[b["id"]] = true
		var th: Dictionary = simulate(hero, g, r, unlimited, 0, {"threat": true})
		for b in th["buys"]:
			bought[b["id"]] = true
	_p()
	_p("Strong curve (continued past 30:00 at its last rate), no squad spend, always on the pad: when the guide's full build is complete (GDD AC 16: 28-33 min).")
	_p()
	_p("| hero | full build at | owned at 30:00 |")
	_p("|---|---|---|")
	for row in full_rows:
		_p(row)
	_p()
	var named := _named_items()
	var unnamed: Array = []
	var unreached: Array = []
	for it in cat.items:
		if it == null:
			continue
		var id := String(it.id)
		if not named.has(id):
			unnamed.append(id)
		elif not bought.has(id):
			unreached.append(id)
	_p("Items no guide names (as a step, a choice or a recipe part): %s." % (", ".join(unnamed) if not unnamed.is_empty() else "none"))
	_p()
	_p("Named by a guide but bought whole by no simulated run (average and strong runs, plus unlimited-Lumen runs plain and with every Situational node open; a closer choice wins, or the two-Signature limit is reached, or it only ever arrives as a recipe part): %s." % (
		", ".join(unreached) if not unreached.is_empty() else "none"))
	_p()
	return "\n".join(_out) + "\n"


func _p(line: String = "") -> void:
	_out.append(line)
