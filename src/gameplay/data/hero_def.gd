class_name HeroDef
extends Resource
## Minimal hero definition for M1 combat (architecture.md §6 HeroDef, abridged).
## Stats from design/gdd/heroes.md §3.1; skills and passive from §4 (E10).
## Level growth arrives with E15. Hitbox values marked PLACEHOLDER are not in the GDD.

@export var id: StringName = &""
@export var display_name: String = ""
@export_range(1, 5000) var max_hp: int = 250
## Flat damage reduction, 0..1 (heroes.md §3.1: Brannoc 0.20).
@export_range(0.0, 0.7, 0.01) var armor: float = 0.0
## Run speed (m/s). Overrides MovementDef.base_move_speed for this hero.
@export_range(0.0, 20.0, 0.1) var move_speed: float = 6.0
@export var weapon: WeaponDef

@export_group("Roles")
## Role ids for build guides and team-function rules (heroes.md §2):
## commander, infiltrator, trapper, soldier, tank, healer, hacker.
@export var roles: PackedStringArray = PackedStringArray()
## What this hero threatens enemies with (BuildAdvisor counter rules):
## cc, burst, sustain, weapon_dps, skill_dps, mobility, zone, squad, frontline.
@export var tags: PackedStringArray = PackedStringArray()

@export_group("Art")
## Procedural model key (ModelCatalog), e.g. &"vesper". Empty = derived from `id`.
@export var model_id: StringName = &""
## Optional authored model scene; when set, views instance it instead of the
## procedural stand-in (the swap path for final art).
@export var model_scene: PackedScene

@export_group("Kit (E10)")
## S1, S2, S3, Ult (heroes.md §4; binds Q / E / C / G, hud.md §4.4).
@export var skills: Array[SkillDef] = []
## Passive: always-on hero-scope modifiers (e.g. Vesper Conductor +2 squad).
@export var passive_modifiers: Array[ModifierDef] = []
## Passive: hero-scope modifiers active only inside a hardpoint zone with an
## active task (Brannoc Anchor: +15% DR, knockback immune).
@export var zone_passive_modifiers: Array[ModifierDef] = []
## Passive: behaviours that need server logic beyond Modifiers (HeroPassiveDef:
## Battle Rhythm, Shadowgraph, Triage Kit, Heal Beam).
@export var passives: Array[HeroPassiveDef] = []
## Passive: radius of the WARDLING_AURA_DAMAGE aura (Vesper Conductor: 15 m).
@export_range(0.0, 60.0, 0.5) var wardling_aura_radius_m: float = 0.0
## Passive: allied Vanguard waves with a member this close are "conducted"
## (Vesper Conductor: 25 m; 0 = cannot conduct waves).
@export_range(0.0, 60.0, 0.5) var conduct_radius_m: float = 0.0

## W9-H2 Hex Signal Sight: weapon damage multiplier against enemy gadgets
## (traps, deployables). 1 = no bonus.
@export_range(1.0, 3.0, 0.01) var gadget_damage_mult: float = 1.0

@export_group("Hitbox")
## Linear scale of the hitbox. heroes.md §3.1: Brannoc +25% volume -> 1.25^(1/3) = 1.077.
@export_range(0.5, 2.0, 0.001) var hitbox_scale: float = 1.0
## PLACEHOLDER. Body capsule radius and top height above the feet (standing, m).
@export_range(0.1, 2.0, 0.01) var body_radius: float = 0.4
@export_range(0.5, 3.0, 0.01) var body_top_m: float = 1.42
## PLACEHOLDER. Head sphere centre height above the feet (standing) and radius (m).
@export_range(0.5, 3.0, 0.01) var head_center_m: float = 1.6
@export_range(0.05, 1.0, 0.01) var head_radius: float = 0.2


## `base` with this hero's run speed (a per-hero copy; `base` is not mutated).
func movement_for(base: MovementDef) -> MovementDef:
	if is_equal_approx(base.base_move_speed, move_speed):
		return base
	var m := base.duplicate() as MovementDef
	m.base_move_speed = move_speed
	return m
