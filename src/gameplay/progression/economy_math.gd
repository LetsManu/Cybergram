class_name EconomyMath
extends RefCounted
## Pure formulas of design/gdd/wardlings-and-economy.md Part 2 and the shop math
## of weapons-and-mods.md §4.7. No state; ProgressionSystem and tests call these.
##
## Example: EconomyMath.level_for_exp(rules, 1450) -> 6; EconomyMath.share(rules, 3) -> 0.69


## §16 inc(L): EXP needed from L to L + 1 (0 at the cap).
static func exp_to_next(r: EconomyRulesDef, level: int) -> int:
	if level >= r.max_level or level < 1:
		return 0
	if level <= r.xp_early_last:
		return r.xp_early_base + r.xp_early_per_level * level
	return r.xp_late_base + r.xp_late_per_level * (level - r.xp_early_last - 1)


## §16 cumulative EXP at which `level` starts (L1 = 0, L15 = 8,290).
static func exp_for_level(r: EconomyRulesDef, level: int) -> int:
	var total := 0
	for l in range(1, clampi(level, 1, r.max_level)):
		total += exp_to_next(r, l)
	return total


static func level_for_exp(r: EconomyRulesDef, exp_total: int) -> int:
	var l := 1
	while l < r.max_level and exp_total >= exp_for_level(r, l + 1):
		l += 1
	return l


## heroes.md §3.5: 1 point at L1, +1 per level.
static func skill_points_total(level: int) -> int:
	return maxi(level, 0)


## §15.1 S(n) = min(1, k / √n); 0 for an empty list.
static func share(r: EconomyRulesDef, n: int) -> float:
	if n <= 0:
		return 0.0
	return minf(1.0, r.share_k / sqrt(float(n)))


## §16.1 C = min(cap, 1 + per_level × max(0, Lv_victim − Lv_killer)).
static func catchup(r: EconomyRulesDef, victim_level: int, killer_level: int) -> float:
	return minf(r.catchup_cap, 1.0 + r.catchup_per_level * maxi(0, victim_level - killer_level))


## §16.1 D = 1 + min(cap, slope × gap), gap = (Res_leader − Res_team) / Res_leader.
static func deficit(r: EconomyRulesDef, team_res: float, leader_res: float) -> float:
	if leader_res <= 0.0 or team_res >= leader_res:
		return 1.0
	return 1.0 + minf(r.deficit_cap, r.deficit_slope * (leader_res - team_res) / leader_res)


## §17 Shutdown = min(cap, per × max(0, streak − free)).
static func shutdown(r: EconomyRulesDef, victim_streak: int) -> int:
	return mini(r.shutdown_cap, r.shutdown_per_kill * maxi(0, victim_streak - r.shutdown_free_streak))


## §17 Wardling bounty (Lumen) per share-list member at `tier` (1..3):
## [instant 75%, Mote 25%] (floats; rounded when paid).
static func wardling_lumen_split(r: EconomyRulesDef, squad: bool, tier: int, n: int) -> Array[float]:
	var table := r.lumen_squad if squad else r.lumen_vanguard
	var base := float(table[clampi(tier, 1, table.size()) - 1]) * share(r, maxi(n, 1))
	return [base * (1.0 - r.mote_fraction), base * r.mote_fraction]


## §16.1 Wardling Resonance per share-list member.
static func wardling_exp(r: EconomyRulesDef, squad: bool, tier: int, n: int) -> float:
	var table := r.exp_squad if squad else r.exp_vanguard
	return float(table[clampi(tier, 1, table.size()) - 1]) * share(r, n)


## §16.1 hero-kill Resonance P for the killer.
static func kill_exp(r: EconomyRulesDef, victim_level: int, killer_level: int, d: float) -> float:
	return float(r.exp_kill_base + r.exp_kill_per_victim_level * victim_level) * catchup(r, victim_level, killer_level) * d


## weapons-and-mods.md §4.7 / §3.6.4 rule 4: refund of a mount whose line cost
## `paid_total`, of which `paid_visit` was paid during the current Armory visit
## (that part is an undo at 100%; the rest pays 60%, rounded down to 5).
static func sell_value(r: EconomyRulesDef, paid_total: int, paid_visit: int) -> int:
	var visit := clampi(paid_visit, 0, paid_total)
	var late := paid_total - visit
	var step := maxi(1, r.sell_round)
	return visit + floori(r.sell_late_frac * late / step) * step


## §4.7 UpgradeCost = list(new) − list(held) for the same line (held tier 0 = empty).
## Deprecated: v1 tiered mounts are gone; v22 items have one price (RecipeMath prices recipes).
static func upgrade_cost(item: ArmoryItemDef, new_tier: int, held_tier: int) -> int:
	return item.price(new_tier) - (item.price(held_tier) if held_tier >= 1 else 0)
