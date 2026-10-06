class_name EconomyRulesDef
extends Resource
## Resonance (EXP), levels and Lumen income (design/gdd/wardlings-and-economy.md
## Part 2, §15–§17, §26 slice subset; heroes.md §3.3, §3.5). Defaults are the
## GDD values; the slice .tres raises the trickle to 60/min (§26 re-tune).
## Values marked PLACEHOLDER are not given by the GDD.

@export_group("Levels (§16, C12)")
@export_range(1, 30) var max_level: int = 15
## inc(L) = early_base + early_per_level·L for L = 1..early_last; then
## late_base + late_per_level·(L − early_last − 1) up to max_level − 1.
@export var xp_early_base: int = 140
@export var xp_early_per_level: int = 50
@export var xp_early_last: int = 5
@export var xp_late_base: int = 520
@export var xp_late_per_level: int = 60
## heroes.md §3.3 MaxHP(L): +4% per level (weapon +2.5%: DamageMath.K_LEVEL;
## skill +2%: AbilityRulesDef.skill_power_per_level).
@export_range(0.0, 0.2, 0.001) var hp_per_level: float = 0.04

@export_group("Resonance sources (§16.1)")
## Per Tier I / II / III Wardling (× S(n)).
@export var exp_vanguard: PackedInt32Array = PackedInt32Array([20, 30, 40])
@export var exp_squad: PackedInt32Array = PackedInt32Array([45, 60, 75])
## Hero kill P = (base + per_level·Lv_victim) × C × D; assisters / allies in range get assist_frac·P.
@export var exp_kill_base: int = 200
@export var exp_kill_per_victim_level: int = 20
@export_range(0.0, 1.0, 0.05) var exp_assist_frac: float = 0.5
@export var exp_capture_team: int = 100
@export var exp_capture_participant: int = 250
@export var exp_defence: int = 150
## C = min(cap, 1 + per_level × max(0, Lv_victim − Lv_killer)).
@export_range(0.0, 1.0, 0.01) var catchup_per_level: float = 0.15
@export_range(1.0, 3.0, 0.05) var catchup_cap: float = 1.6
## D = 1 + min(cap, slope × gap) (kills and captures only).
@export_range(0.0, 1.0, 0.01) var deficit_cap: float = 0.25
@export_range(0.0, 2.0, 0.05) var deficit_slope: float = 0.5
## Individual catch-up: all Resonance × mult while Lv ≤ team average − levels.
@export_range(1.0, 2.0, 0.05) var individual_catchup_mult: float = 1.2
@export_range(0, 10) var individual_catchup_levels: int = 2

@export_group("Lumen (§17, C14)")
@export var starting_purse: int = 500
## GDD 40/min; the slice .tres uses 60 (§26: no Sentinels).
@export var trickle_per_min: float = 40.0
@export_range(0.0, 600.0, 1.0) var trickle_start_s: float = 60.0
@export var lumen_vanguard: PackedInt32Array = PackedInt32Array([35, 45, 55])
@export var lumen_squad: PackedInt32Array = PackedInt32Array([60, 75, 90])
## §11 / §17: a Garrison Sentinel pays this × the squad-Wardling bounty; a
## Sentinel death at the same hardpoint within the window pays × repeat_mult.
@export_range(1.0, 3.0, 0.05) var sentinel_bounty_mult: float = 1.5
@export_range(0.0, 600.0, 5.0) var sentinel_repeat_window_s: float = 180.0
@export_range(0.0, 1.0, 0.05) var sentinel_repeat_mult: float = 0.5
## §12: 25% of a Wardling bounty sits in the Core's Lumen Mote.
@export_range(0.0, 1.0, 0.01) var mote_fraction: float = 0.25
@export_range(0.5, 60.0, 0.5) var mote_life_s: float = 10.0
@export_range(0.1, 10.0, 0.1) var mote_radius_m: float = 1.2
## K = (base + Shutdown) × D; Shutdown = min(cap, per × max(0, streak − free)).
@export var kill_lumen_base: int = 200
@export var shutdown_per_kill: int = 50
@export var shutdown_cap: int = 300
@export var shutdown_free_streak: int = 2
@export var assist_lumen: int = 100
## Capture: participant × D × Recap (Recap for retaking a starting hardpoint);
## the 120 / 40 / 60 amounts come from MatchRulesDef via ObjectiveEvent.
@export_range(1.0, 2.0, 0.05) var recap_mult: float = 1.25
@export_range(0.0, 600.0, 1.0) var capture_cooldown_s: float = 180.0
@export_range(0.0, 1.0, 0.05) var capture_cooldown_mult: float = 0.25
@export_range(0.0, 600.0, 1.0) var defence_cooldown_s: float = 90.0

@export_group("Share list (§15.1, C13)")
@export_range(1.0, 100.0, 0.5) var share_radius_m: float = 25.0
@export_range(0.5, 3.0, 0.05) var share_k: float = 1.2
## Contribution windows: damage to a Wardling / a hero within this long.
@export_range(0.0, 30.0, 0.5) var wardling_contrib_s: float = 3.0
@export_range(0.0, 30.0, 0.5) var hero_contrib_s: float = 5.0
## §21: a death within this long of hero damage credits the last damager.
@export_range(0.0, 30.0, 0.5) var last_damager_s: float = 10.0

@export_group("Armory and spawn (§19; weapons-and-mods.md §3.6.4)")
## PLACEHOLDER. Armory zone radius around HqDef.armory (same as the Foundry pad).
@export_range(1.0, 30.0, 0.5) var armory_radius_m: float = 6.0
## Owner decision 2026-10-06 ("like the LoL shop at the spawn"): the whole
## Sanctum zone (HqDef.sanctum_radius around HqDef.sanctum) also counts as the
## Armory, so a hero can shop where they spawn.
@export var shop_in_sanctum: bool = true
## §3.6.4 rule 4: later sells pay 60%, rounded down to a multiple of 5.
@export_range(0.0, 1.0, 0.05) var sell_late_frac: float = 0.6
@export var sell_round: int = 5
## §19 Med-Pack: heal 40% of max HP over 3 s, cancelled by firing.
@export_range(0.0, 1.0, 0.05) var medpack_heal_frac: float = 0.4
@export_range(0.1, 10.0, 0.1) var medpack_duration_s: float = 3.0
## match-flow §3.5: a Mid Forward Beacon becomes a spawn after 15 s attunement,
## and is "under attack" while enemy progress > 0 or an enemy hero is within 25 m.
@export_range(0.0, 60.0, 0.5) var beacon_attune_s: float = 15.0
@export_range(0.0, 60.0, 0.5) var beacon_threat_radius_m: float = 25.0
