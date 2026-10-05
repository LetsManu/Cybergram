class_name HealthComponent
extends RefCounted
## Hit points with flat armor and a team filter (architecture.md §7.2,
## design/gdd/heroes.md §3.1, weapons-and-mods.md §3.1 rule 5: no friendly fire).
## Server-authoritative; clients only see replicated hp.
## Deviation: a RefCounted held by HeroCombat, not a Node (no tree cost).

signal died(killer_net_id: int)
## HP restored (applied amount) and who healed (0 = unknown / self); feeds MatchStats.
signal healed(amount: float, source_net_id: int)

var max_hp: float
var hp: float
## Flat % reduction (0.20 = 20%).
var armor: float
## Flat extra damage reduction (stacked with armor; clamp 70%).
var damage_reduction: float = 0.0
## E10: hero StatBlock (null for Wardlings). DAMAGE_REDUCTION adds to armor and
## DAMAGE_TAKEN multiplies the result (statuses, passives, zones write them).
var stats: StatBlock
## E10: absorb pool (StatusComponent SHIELD); spent before HP.
var shield: float = 0.0
## HP + shield removed by the latest apply_damage (diagnostics).
var last_absorbed: float = 0.0
var team: int
var last_attacker: int = 0
## HP that damage cannot reduce below (Aurora's 2 s floor of 1 HP; 0 = none).
var floor_hp: float = 0.0
## W11-M1 Healing reduction: incoming heals are multiplied by this (StatusComponent HEAL_CUT).
var heal_mult: float = 1.0
## W11-M1: running total of damage removed by the stats' DAMAGE_REDUCTION (statuses,
## zones); window readers (Fortify Lifeblood) take differences.
var mitigated: float = 0.0


func _init(max_hp_: float, armor_: float, team_: int) -> void:
	max_hp = max_hp_
	hp = max_hp_
	armor = armor_
	team = team_


func is_alive() -> bool:
	return hp > 0.0


## Applies `info` and returns the HP actually removed (0 if filtered).
## TRUE damage ignores armor. Same-team damage is dropped (no friendly fire).
func apply_damage(info: DamageInfo) -> float:
	if not is_alive() or info.amount <= 0.0:
		return 0.0
	if info.instigator_team == team:
		return 0.0
	var amount := info.amount
	if info.type != DamageInfo.Type.TRUE:
		var dr := damage_reduction
		if stats != null:
			dr += stats.get_value(StatCatalog.DAMAGE_REDUCTION)
		var arm := armor * (1.0 - minf(0.60, maxf(info.armor_pen, 0.0)))
		var after := DamageMath.armor_mult(arm, dr)
		if stats != null:
			mitigated += amount * (DamageMath.armor_mult(arm, damage_reduction) - after)
		amount *= after
		if stats != null:
			amount *= stats.get_value(StatCatalog.DAMAGE_TAKEN)
	last_absorbed = 0.0
	if shield > 0.0:
		last_absorbed = minf(shield, amount)
		shield -= last_absorbed
		amount -= last_absorbed
		if amount <= 0.0:
			last_attacker = info.source_net_id
			return 0.0
	var applied := minf(amount, maxf(0.0, hp - floor_hp))
	hp -= applied
	last_attacker = info.source_net_id
	if hp <= 0.0:
		hp = 0.0
		died.emit(info.source_net_id)
	return applied


func heal(amount: float, source_net_id: int = 0) -> float:
	if not is_alive():
		return 0.0
	var applied := minf(maxf(amount, 0.0) * heal_mult, max_hp - hp)
	hp += applied
	if applied > 0.0:
		healed.emit(applied, source_net_id)
	return applied


func reset() -> void:
	hp = max_hp
	shield = 0.0
	last_attacker = 0
