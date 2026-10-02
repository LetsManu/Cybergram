class_name DamageInfo
extends RefCounted
## One damage application (architecture.md §7.2 DamageInfo).

enum Type { WEAPON, SKILL, TRUE }

const FLAG_HEADSHOT: int = 1

var amount: float = 0.0
var type: Type = Type.WEAPON
var source_net_id: int = 0
var instigator_team: int = -1
var flags: int = 0
## E13 Piercing (weapons-and-mods.md §4.1): A_eff = A × (1 − min(0.60, armor_pen)).
var armor_pen: float = 0.0


static func make(amount_: float, source: int, team: int, flags_: int = 0, type_: Type = Type.WEAPON) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount_
	d.source_net_id = source
	d.instigator_team = team
	d.flags = flags_
	d.type = type_
	return d
