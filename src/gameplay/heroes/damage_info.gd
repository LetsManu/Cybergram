class_name DamageInfo
extends RefCounted
## One damage application (architecture.md §7.2 DamageInfo).

enum Type { WEAPON, SKILL, TRUE }

const FLAG_HEADSHOT: int = 1
## Already mitigated (ammo Burn ticks are a share of final damage, items-and-armory.md
## §4.3): armor, resist and DR are not applied again; shields and DAMAGE_TAKEN are.
const FLAG_PREMITIGATED: int = 2
## Ammo effect damage (Burn, Shock arcs, Volatile): never triggers ammo effects
## again (weapons-and-mods.md §5: not recursive).
const FLAG_AMMO_EFFECT: int = 4

var amount: float = 0.0
var type: Type = Type.WEAPON
var source_net_id: int = 0
var instigator_team: int = -1
var flags: int = 0
## E13 Piercing (weapons-and-mods.md §4.1): A_eff = A × (1 − min(0.60, armor_pen)).
var armor_pen: float = 0.0
## items-and-armory.md §4.3 Rend: gear-armor points removed by the attacker's
## Breaker Bore stacks (0-0.08). Hook for chunk C3; 0 here.
var rend: float = 0.0


static func make(amount_: float, source: int, team: int, flags_: int = 0, type_: Type = Type.WEAPON) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount_
	d.source_net_id = source
	d.instigator_team = team
	d.flags = flags_
	d.type = type_
	return d
