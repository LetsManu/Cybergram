class_name StatCatalog
extends RefCounted
## The single list of stat ids (ADR-0004 §1, architecture.md §7.1). Two scopes:
## - HERO stats live in a hero's StatBlock (HeroCombat.stats);
## - SKILL params live in each SkillInstance's StatBlock, seeded from
##   SkillDef.params. Skill-tree nodes (Boost/Fork/Mastery, E15) and mods write
##   Modifiers into these blocks by name; nothing else changes numbers.

# --- Hero scope ---------------------------------------------------------------
## Run speed (m/s). Base = HeroDef.move_speed; slows/roots write PCT/OVERRIDE.
const MOVE_SPEED: int = 0
## Multiplier on incoming damage after armor (base 1).
const DAMAGE_TAKEN: int = 1
## Multiplier on outgoing weapon and skill damage (base 1).
const DAMAGE_DEALT: int = 2
## External cooldown reduction, 0..1 (base 0). Capped by AbilityRules.CDR_CAP at use.
const COOLDOWN_REDUCTION: int = 3
## Additive damage reduction stacked with armor (heroes.md §3.1, clamp 70%).
const DAMAGE_REDUCTION: int = 4
## SkillPower(L) of heroes.md §3.3 (base 1).
const SKILL_POWER: int = 5
## Vesper Conductor: extra personal squad slots (wardlings §13 squad_capacity_bonus).
const SQUAD_CAPACITY_BONUS: int = 6
## Multiplier on own squad Wardlings' max HP (Vesper +15%).
const WARDLING_HP_MULT: int = 7
## Damage bonus granted to allied Wardlings near this hero (Vesper aura +10%).
const WARDLING_AURA_DAMAGE: int = 8
## > 0 = immune to knockback/pull (Brannoc Anchor).
const KNOCKBACK_IMMUNE: int = 9
## > 0 = immune to hard CC (Brannoc Fortify).
const CC_IMMUNE: int = 10
## E15 MaxHP(L) of heroes.md §3.3 (base = HeroDef.max_hp; level writes a MUL).
const MAX_HP: int = 11
## E15 weapon L(level) of weapons-and-mods.md §4.2 (base 1; level writes a MUL).
const WEAPON_DAMAGE: int = 12
## E13 M_dmg of weapons-and-mods.md §4.1: additive mod damage bonus, capped at +0.25.
const MOD_DAMAGE: int = 13
## E13 Frame mounts: mana regen multiplier (Flux Coil +15/25/35%).
const MANA_REGEN: int = 14
## E13 Frame mounts: seconds added to the mana regen delay (Flux Coil −0.1/0.2/0.3).
const REGEN_DELAY: int = 15
## E13 Frame mounts: reload time multiplier (Quickload −12/22/30%).
const RELOAD_TIME: int = 16
## E13 Amplifier Emitters: own squad Wardling bolt damage multiplier (+20%).
const WARDLING_DAMAGE_MULT: int = 17
const HERO_COUNT: int = 18

const HERO_NAMES: Array[StringName] = [&"move_speed", &"damage_taken", &"damage_dealt", &"cooldown_reduction",
	&"damage_reduction", &"skill_power", &"squad_capacity_bonus", &"wardling_hp_mult", &"wardling_aura_damage",
	&"knockback_immune", &"cc_immune", &"max_hp", &"weapon_damage", &"mod_damage", &"mana_regen",
	&"regen_delay", &"reload_time", &"wardling_damage_mult"]
## Default base values (move speed and max HP are overwritten from HeroDef).
const HERO_BASE: Array[float] = [6.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0,
	250.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0]
const HERO_MIN: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	1.0, 0.0, 0.0, 0.0, -10.0, 0.1, 0.0]
## MOD_DAMAGE max 0.25 is the §4.1 M_dmg cap.
const HERO_MAX: Array[float] = [50.0, 10.0, 10.0, 1.0, 1.0, 10.0, 8.0, 10.0, 5.0, 1.0, 1.0,
	100000.0, 10.0, 0.25, 10.0, 10.0, 10.0, 10.0]

# --- Skill scope (generic params, reused across skills) -----------------------
## Names of the per-skill params; index = position. Seconds, metres, HP, fractions.
const SKILL_PARAMS: Array[StringName] = [
	&"cooldown", &"damage", &"range", &"radius", &"duration", &"hp", &"heal_per_s", &"dr",
	&"stun", &"slow", &"speed", &"cast_time", &"bonus_damage", &"secondary_duration",
	&"width", &"height", &"distance", &"charges", &"leap_time",
	# W9-H2 (Trapper / Hacker): arm delay, Scramble, Lag (s), traps placed at once.
	&"arm_time", &"scramble", &"lag", &"max_placed",
	# W10-T1 fork nodes: hero heal/s of a beacon, effect-specific extras (s / fraction / count).
	&"ally_heal", &"extra", &"extra_b", &"count", &"splits",
	# W11-M1 mechanics: Reveal (s), Bleed (total HP, s), Healing reduction (fraction, s),
	# Hijack (s), recast window (s) / strength, expiry-hook amount.
	&"reveal", &"bleed", &"bleed_time", &"heal_cut", &"heal_cut_time", &"hijack",
	&"recast_window", &"recast_value", &"expiry_heal",
	# W11-M1: a wall that blocks enemy hero movement (> 0).
	&"block_move",
]


static func hero_index(stat: StringName) -> int:
	return HERO_NAMES.find(stat)


static func skill_index(param: StringName) -> int:
	return SKILL_PARAMS.find(param)


## A fresh hero block with the catalog defaults, `move_speed` and `max_hp`.
static func new_hero_block(move_speed: float, max_hp: float = 250.0) -> StatBlock:
	var base := PackedFloat32Array(HERO_BASE)
	base[MOVE_SPEED] = move_speed
	base[MAX_HP] = max_hp
	var b := StatBlock.new(base)
	for i in HERO_COUNT:
		b.set_limits(i, HERO_MIN[i], HERO_MAX[i])
	return b


## A skill block seeded from `params` (missing params are 0).
static func new_skill_block(params: Dictionary) -> StatBlock:
	var base := PackedFloat32Array()
	base.resize(SKILL_PARAMS.size())
	for k in params:
		var i := skill_index(StringName(k))
		if i >= 0:
			base[i] = float(params[k])
	var b := StatBlock.new(base)
	for i in SKILL_PARAMS.size():
		b.set_limits(i, 0.0, INF)
	return b
