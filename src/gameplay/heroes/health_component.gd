class_name HealthComponent
extends RefCounted
## Hit points with flat armor and a team filter (architecture.md §7.2,
## design/gdd/heroes.md §3.1, weapons-and-mods.md §3.1 rule 5: no friendly fire).
## Server-authoritative; clients only see replicated hp.
## Deviation: a RefCounted held by HeroCombat, not a Node (no tree cost).

signal died(killer_net_id: int)

var max_hp: float
var hp: float
## Flat % reduction (0.20 = 20%).
var armor: float
## Active damage reduction from skills (Fortify, Anchor...; E10).
var damage_reduction: float = 0.0
var team: int
var last_attacker: int = 0


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
		amount *= DamageMath.armor_mult(armor, damage_reduction)
	var applied := minf(amount, hp)
	hp -= applied
	last_attacker = info.source_net_id
	if hp <= 0.0:
		hp = 0.0
		died.emit(info.source_net_id)
	return applied


func heal(amount: float) -> float:
	if not is_alive():
		return 0.0
	var applied := minf(maxf(amount, 0.0), max_hp - hp)
	hp += applied
	return applied


func reset() -> void:
	hp = max_hp
	last_attacker = 0
