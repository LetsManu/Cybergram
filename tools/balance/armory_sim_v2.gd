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
## Observations only, no verdicts. Run: tools/balance/armory_report.gd -- --v22

const ArmorySim := preload("res://tools/balance/armory_sim.gd")
const MATCH_S := 1800
const VISIT_S := 180
const DEAD_ZONE_S := 240
const HZ := 30
## §18 30:00 Lumen of the weak and strong profiles.
const WEAK_30 := 6320.0
const STRONG_30 := 12280.0

var cat: ArmoryCatalogDef
var guides: RecommendedBuildsDef
var ar: AdviceRulesDef
var heroes: Array[HeroDef] = []
var _out := PackedStringArray()


func _init() -> void:
	cat = load(ArmoryCatalogDef.V22_PATH) as ArmoryCatalogDef
	guides = load(RecommendedBuildsDef.V22_PATH) as RecommendedBuildsDef
	ar = load(AdviceRulesDef.DEFAULT_PATH) as AdviceRulesDef
	heroes = ArmorySim.new().heroes


## `base` (earned Lumen per second, starts at the purse) scaled above the purse
## so its last value becomes `end_value`.
static func scaled(base: Array, purse: float, end_value: float) -> Array:
	var k := (end_value - purse) / maxf(1.0, float(base[base.size() - 1]) - purse)
	return base.map(func(v: float) -> float: return purse + (v - purse) * k)


## Spends `guide` along `earned` (visit_s 0 = always on the pad). Returns
## {buys: [{t, id, cost, kind}], sells, left, owned_value, first_sig, items, squad, consumables}.
func simulate(hero: HeroDef, guide: RecommendedBuildDef, r: EconomyRulesDef, earned: Array, visit_s: int) -> Dictionary:
	var p := HeroProgress.new(1)
	var holder := HeroBody.new()
	holder.setup(MovementDef.new(), Vector3.ZERO, false)
	holder.combat = HeroCombat.new(hero, 0, HZ, 1)
	var c := holder.combat
	var buys: Array = []
	var sells := 0
	var spent := {"items": 0, "squad": 0, "consumables": 0}
	var first_sig := -1
	var prev := 0
	var plan := _plan(guide)
	for sec in range(0, MATCH_S + 1):
		var total := int(r.starting_purse) if sec == 0 else floori(earned[sec - 1])
		p.lumen += total - prev
		prev = total
		if visit_s > 0 and sec % visit_s != 0:
			continue
		p.at_armory = true
		for _guard in 40:
			var st := BuildState.from_hero(p, cat, hero.weapon, r)
			st.time_s = sec
			st.mode = &"5v5"
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
		p.end_visit()
		p.at_armory = false
	var value := 0
	for e in p.inv.pool():
		value += RecipeMath.total(cat, int(e["index"]))
	holder.free()
	return {"buys": buys, "sells": sells, "left": p.lumen, "owned_value": value, "first_sig": first_sig,
		"items": spent["items"], "squad": spent["squad"], "consumables": spent["consumables"]}


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


static func mmss(t: int) -> String:
	return "%d:%02d" % [t / 60, t % 60] if t >= 0 else "never"


func report() -> String:
	_out.clear()
	var r := load(ArmorySim.SLICE_RULES) as EconomyRulesDef
	var avg := ArmorySim.curve(r, false)
	var purse := float(r.starting_purse)
	var profiles := [["weak", scaled(avg, purse, WEAK_30)], ["average", avg], ["strong", scaled(avg, purse, STRONG_30)]]
	var unlimited: Array = []
	unlimited.resize(MATCH_S)
	unlimited.fill(100000.0)
	_p("# Armory v2 balance report (generated)")
	_p()
	_p("Generated by `tools/balance/armory_report.gd -- --v22` (do not edit by hand).")
	_p("Catalog %s (%d items), guides %s. Purchases: BuildAdvisor next part -> ItemShop.buy; full slots -> sell a loose item the guide never uses." % [
		ArmoryCatalogDef.V22_PATH.get_file(), cat.items.size(), RecommendedBuildsDef.V22_PATH.get_file()])
	_p("Lumen at 30:00: weak %d, average %d, strong %d (§18). \"pad\" = always on the Armory pad; \"visit\" = every %d s." % [
		int(profiles[0][1][MATCH_S - 1]), int(avg[MATCH_S - 1]), int(profiles[2][1][MATCH_S - 1]), VISIT_S])
	_p()
	_p("| hero | profile | visits | first Signature | full build value | owned at 30:00 | unspent | items / squad / consumables | dead zones | sells |")
	_p("|---|---|---|---|---|---|---|---|---|---|")
	var bought := {}
	for hero in heroes:
		var g := guides.for_hero(hero.id)
		if g == null:
			_p("| %s | NO GUIDE | | | | | | | | |" % hero.display_name)
			continue
		var full: Dictionary = simulate(hero, g, r, unlimited, 0)
		var full_value: int = full["owned_value"]
		for prof in profiles:
			for v in [0, VISIT_S]:
				var run := simulate(hero, g, r, prof[1], v)
				for b in run["buys"]:
					bought[b["id"]] = true
				var spent := maxi(1, int(run["items"]) + int(run["squad"]) + int(run["consumables"]))
				var dz := ArmorySim.dead_zones(run["buys"])
				_p("| %s | %s | %s | %s | %d | %d%% | %d | %d%% / %d%% / %d%% | %d | %d |" % [hero.display_name, prof[0],
					"pad" if v == 0 else "%ds" % v, mmss(run["first_sig"]), full_value,
					roundi(100.0 * float(run["owned_value"]) / maxf(1.0, full_value)), run["left"],
					roundi(100.0 * int(run["items"]) / spent), roundi(100.0 * int(run["squad"]) / spent),
					roundi(100.0 * int(run["consumables"]) / spent), dz.size(), run["sells"]])
	_p()
	var never: Array = []
	for it in cat.items:
		if it != null and not bought.has(String(it.id)):
			never.append(String(it.id))
	_p("Items no run buys: %s." % (", ".join(never) if not never.is_empty() else "none"))
	_p()
	return "\n".join(_out) + "\n"


func _p(line: String = "") -> void:
	_out.append(line)
