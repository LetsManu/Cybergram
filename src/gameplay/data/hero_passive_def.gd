class_name HeroPassiveDef
extends Resource
## Data for one hero passive that needs server behaviour beyond plain stat
## Modifiers (design/gdd/heroes.md §4 "Passive"). `kind` selects the behaviour
## in SkillEntities; only the fields of that kind are read. All numbers are
## the GDD values, tuned here and never in code.
##   BATTLE_RHYTHM (Ryker): a kill refills `magazine_refill_frac` of the magazine
##                 and grants `speed_bonus` move speed for `duration_s`.
##   SHADOWGRAPH (Sable): weapon +`damage_bonus` vs targets facing away.
##   TRIAGE_KIT (Liora): a free Med-Pack every `interval_s`, free ones cap at `max_free`.
##   HEAL_BEAM (Liora): alt-fire beam, `range_m` / `cone_deg` lock, `leash_m` hold,
##                 `hero_heal_per_s` / `wardling_heal_per_s`, `mana_per_s` drain.

enum Kind { BATTLE_RHYTHM, SHADOWGRAPH, TRIAGE_KIT, HEAL_BEAM }

@export var kind: Kind = Kind.BATTLE_RHYTHM
@export_range(0.0, 1.0, 0.01) var magazine_refill_frac: float = 0.5
@export_range(0.0, 1.0, 0.01) var speed_bonus: float = 0.15
@export_range(0.0, 30.0, 0.1) var duration_s: float = 3.0
@export_range(0.0, 2.0, 0.01) var damage_bonus: float = 0.2
@export_range(1.0, 300.0, 0.5) var interval_s: float = 30.0
@export_range(0, 10) var max_free: int = 2
@export_range(1.0, 60.0, 0.5) var range_m: float = 18.0
@export_range(0.5, 45.0, 0.5) var cone_deg: float = 6.0
@export_range(1.0, 60.0, 0.5) var leash_m: float = 20.0
@export_range(0.0, 500.0, 1.0) var hero_heal_per_s: float = 60.0
@export_range(0.0, 500.0, 1.0) var wardling_heal_per_s: float = 30.0
@export_range(0.0, 200.0, 0.5) var mana_per_s: float = 25.0
