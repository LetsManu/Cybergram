class_name WardlingRulesDef
extends Resource
## Squad, command and Vanguard rules (wardlings-and-economy.md §3, §8–§10;
## Canon C15). Values marked PLACEHOLDER are not given by the GDD.

@export_group("Squad")
@export_range(1, 7) var squad_size: int = 3
## Foundry zone radius around HqDef.foundry (§3).
@export_range(1.0, 30.0, 0.5) var foundry_radius_m: float = 6.0
## Stagger between mints (§3: 0.5 s per Wardling).
@export_range(0.0, 5.0, 0.05) var mint_interval_s: float = 0.5
## Owner death: hold, then dissolve (C15, §9.8).
@export_range(0.0, 60.0, 0.1) var death_hold_s: float = 10.0

@export_group("Commands")
@export_range(1.0, 200.0, 0.5) var command_range_m: float = 50.0
@export_range(1.0, 100.0, 0.5) var hold_ground_range_m: float = 25.0
## Attack Target ends after this long, or after the target is out of LOS this long (§9.5).
@export_range(0.5, 60.0, 0.5) var attack_timeout_s: float = 12.0
@export_range(0.5, 60.0, 0.5) var attack_los_timeout_s: float = 4.0
## Attack leash: from the owner (from Follow) / from the Hold point (from Hold).
@export_range(1.0, 100.0, 0.5) var attack_leash_owner_m: float = 30.0
@export_range(1.0, 100.0, 0.5) var attack_leash_hold_m: float = 20.0

@export_group("Formation and leash")
## Follow wedge distance behind the owner (§9.2: 3–6 m).
@export_range(0.5, 20.0, 0.1) var follow_back_min_m: float = 3.0
@export_range(0.5, 20.0, 0.1) var follow_back_max_m: float = 6.0
## Farther than this from the slot -> sprint (§9.2).
@export_range(1.0, 50.0, 0.5) var catch_up_m: float = 10.0
## Follow leash; on break return and hold fire until within return_fire_m (§9.6).
@export_range(1.0, 100.0, 0.5) var follow_leash_m: float = 30.0
@export_range(1.0, 100.0, 0.5) var return_fire_m: float = 20.0
## PLACEHOLDER (§9.5 says "ring slots around an 8 m radius"; 3 m reads better for 3 units).
@export_range(0.5, 20.0, 0.1) var hold_slot_radius_m: float = 3.0
## Hold: engage up to this far beyond the point; Hold leash (§9.5, §9.6).
@export_range(1.0, 50.0, 0.5) var hold_engage_m: float = 12.0
## Go Capture zone leash (§9.6).
@export_range(1.0, 50.0, 0.5) var capture_leash_m: float = 15.0
## PLACEHOLDER. Capture ring radius as a fraction of the zone radius (the centre holds a solid core).
@export_range(0.1, 1.0, 0.05) var capture_ring_frac: float = 0.55

@export_group("Perception")
## Retaliation window: who damaged the owner / a member within this long (§9.4).
@export_range(0.5, 10.0, 0.5) var threat_memory_s: float = 3.0
## Enemy Wardlings within this radius of the anchor are always valid targets (§9.4).
@export_range(1.0, 50.0, 0.5) var wardling_aggro_m: float = 10.0

@export_group("Vanguard")
## Global cadence: first wave at 1:00, then every 60 s (§10).
@export_range(1.0, 600.0, 1.0) var wave_first_s: float = 60.0
@export_range(1.0, 600.0, 1.0) var wave_interval_s: float = 60.0
@export_range(1, 8) var wave_size: int = 4
## A new wave spawns only when the previous one has at most this many alive.
@export_range(0, 8) var wave_gate_alive: int = 1
@export_range(0.5, 20.0, 0.1) var wave_march_speed: float = 5.5
## Engage enemy Wardlings within this radius (§10).
@export_range(1.0, 50.0, 0.5) var wave_engage_m: float = 15.0
## Front re-evaluation period (§10: every 2 s).
@export_range(0.5, 10.0, 0.5) var wave_retarget_s: float = 2.0
## PLACEHOLDER. Lateral spacing of the 2 x 2 march block (m).
@export_range(0.5, 5.0, 0.1) var wave_spacing_m: float = 1.6

@export_group("AI scheduling (architecture.md §10.2)")
## Per-Wardling decisions every N ticks (3 = 10 Hz at 30 Hz), staggered by net id.
@export_range(1, 30) var decision_interval_ticks: int = 3
## Squad brain every N ticks (6 = 5 Hz).
@export_range(1, 60) var squad_think_interval_ticks: int = 6
## Wave brain every N ticks (15 = 2 Hz).
@export_range(1, 120) var wave_think_interval_ticks: int = 15
## Deterministic cap on per-Wardling decisions per tick; overflow waits a tick.
@export_range(1, 256) var max_decisions_per_tick: int = 32
## Path queries per tick (§14: <= 8); the rest wait in a FIFO queue.
@export_range(1, 64) var max_path_requests_per_tick: int = 8
## LOS rays per tick for target checks.
@export_range(1, 256) var max_los_rays_per_tick: int = 40
