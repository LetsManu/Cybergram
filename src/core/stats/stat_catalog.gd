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
## C5 Supply Cache (Mana): multiplier on the mana regen delay (base 1; -50% for 10 s).
const REGEN_DELAY_MULT: int = 18
## Armory Barrel lines (Focus Lens, Rifling): falloff start and end distances
## multiplier (base 1; +12/20/30%).
const FALLOFF_RANGE: int = 19
## Armory Barrel (Penetrator): armor penetration added to the ammo's (total
## capped at 60% by HealthComponent).
const ARMOR_PEN_BONUS: int = 20
## Armory defensive Frame lines: multiplier on incoming WEAPON / SKILL damage (base 1).
const WEAPON_DAMAGE_TAKEN: int = 21
const SKILL_DAMAGE_TAKEN: int = 22
## Armory squad upgrades (wardlings-and-economy.md §7): own squad move speed
## multiplier and extra Follow leash metres (Harmonic Tether); mint interval
## multiplier and damage resistance right after minting (Quick Mint); damage
## resistance while holding or capturing (Bulwark Protocol).
const WARDLING_SPEED_MULT: int = 23
const WARDLING_LEASH_BONUS: int = 24
const MINT_INTERVAL_MULT: int = 25
const MINT_GUARD: int = 26
const WARDLING_GUARD_DR: int = 27
## Armory v2 item stats (items-and-armory.md §3.5, caps §3.7). Additive,
## base 0 unless noted; the limits below are the §3.7 caps.
## M_rate: fire-rate bonus (cap +0.15).
const FIRE_RATE_BONUS: int = 28
## Spread and recoil multipliers (base 1, at most -50% each).
const SPREAD_MULT: int = 29
const RECOIL_MULT: int = 30
## Headshot multiplier bonus from items (cap +0.30).
const HEADSHOT_BONUS: int = 31
## Mana pool / magazine and reserve multiplier (base 1, cap +60%).
const CAPACITY_MULT: int = 32
## Gear Armor (vs weapon damage) and Resist (vs skill damage), cap 0.20 each.
const GEAR_ARMOR: int = 33
const GEAR_RESIST: int = 34
## Max HP from items, added to MAX_HP (cap +200).
const ITEM_MAX_HP: int = 35
## Move speed from items (fraction, cap +0.12); extra while carrying a Mana
## Cell; extra after 4 s out of combat (Stride Rig).
const ITEM_MOVE_SPEED: int = 36
const CELL_CARRY_SPEED: int = 37
const OOC_MOVE_SPEED: int = 38
const HERO_COUNT: int = 39

const HERO_NAMES: Array[StringName] = [&"move_speed", &"damage_taken", &"damage_dealt", &"cooldown_reduction",
	&"damage_reduction", &"skill_power", &"squad_capacity_bonus", &"wardling_hp_mult", &"wardling_aura_damage",
	&"knockback_immune", &"cc_immune", &"max_hp", &"weapon_damage", &"mod_damage", &"mana_regen",
	&"regen_delay", &"reload_time", &"wardling_damage_mult", &"regen_delay_mult", &"falloff_range",
	&"armor_pen_bonus", &"weapon_damage_taken", &"skill_damage_taken", &"wardling_speed_mult",
	&"wardling_leash_bonus", &"mint_interval_mult", &"mint_guard", &"wardling_guard_dr",
	&"fire_rate_bonus", &"spread_mult", &"recoil_mult", &"headshot_bonus", &"capacity_mult", &"gear_armor",
	&"gear_resist", &"item_max_hp", &"item_move_speed", &"cell_carry_speed", &"ooc_move_speed"]
## Default base values (move speed and max HP are overwritten from HeroDef).
const HERO_BASE: Array[float] = [6.0, 1.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0,
	250.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0,
	0.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const HERO_MIN: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	1.0, 0.0, 0.0, 0.0, -10.0, 0.1, 0.0, 0.0, 0.5, 0.0, 0.3, 0.3, 0.5, 0.0, 0.1, 0.0, 0.0,
	0.0, 0.5, 0.5, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## MOD_DAMAGE max 0.25 is the §4.1 M_dmg cap; the v2 item caps are
## items-and-armory.md §3.7 (fire rate 0.15, headshot 0.30, capacity +60%,
## gear armor / resist 0.20, item HP +200, item move speed +12%).
const HERO_MAX: Array[float] = [50.0, 10.0, 10.0, 1.0, 1.0, 10.0, 8.0, 10.0, 5.0, 1.0, 1.0,
	100000.0, 10.0, 0.25, 10.0, 10.0, 10.0, 10.0, 10.0, 2.0, 0.6, 1.0, 1.0, 2.0, 40.0, 1.0, 0.9, 0.9,
	0.15, 2.0, 2.0, 0.30, 1.6, 0.20, 0.20, 200.0, 0.12, 0.30, 0.20]

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
	# W11-M1 Interceptor: range (m) at which Ram Charge may target an ally (0 = off).
	&"ally_charge",
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
