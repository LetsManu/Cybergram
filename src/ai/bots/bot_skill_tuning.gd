class_name BotSkillTuning
extends Resource
## W10-W3 thresholds for the bot skill behaviours that need more than a single
## "condition -> slot" rule: Liora's heal beam, Sable's remote detonation, the
## Tripwire Lattice and Hex's Relay Hop (BotSkillRules). Loaded through
## BotRosterDef.skill_tuning (assets/data/ai/bot_skill_tuning.tres). All values
## are PLACEHOLDER tuning.

@export_group("Heal beam")
## Start beaming an ally at or below this HP fraction.
@export_range(0.0, 1.0, 0.01) var beam_start_hp_frac: float = 0.75
## Keep beaming the same ally until it reaches this HP fraction.
@export_range(0.0, 1.0, 0.01) var beam_release_hp_frac: float = 0.98
## Stop below / start above this mana fraction (a hysteresis pair).
@export_range(0.0, 1.0, 0.01) var beam_mana_stop_frac: float = 0.05
@export_range(0.0, 1.0, 0.01) var beam_mana_start_frac: float = 0.2
## Metres kept inside the beam range / leash when choosing an ally.
@export_range(0.0, 10.0, 0.5) var beam_range_margin_m: float = 1.5
## Heavy fire on the healer: damaged within this window while at or below
## `beam_self_hp_frac` means she fights or runs instead of beaming.
@export_range(0.1, 5.0, 0.1) var beam_self_fire_window_s: float = 1.5
@export_range(0.0, 1.0, 0.01) var beam_self_hp_frac: float = 0.5

@export_group("Sabotage remote detonation")
## An enemy hero within this fraction of the charge's blast radius triggers it.
@export_range(0.1, 1.5, 0.05) var sabotage_hero_radius_frac: float = 0.85
## An enemy Ward Generator within this extra reach of the blast radius (its
## hit radius is added by the rule's caller) triggers it.
@export_range(0.0, 10.0, 0.5) var sabotage_generator_slack_m: float = 1.0
## Enemy sightings older than this do not count (seconds).
@export_range(0.0, 3.0, 0.1) var sabotage_sighting_age_s: float = 0.5

@export_group("Tripwire Lattice")
## Place wires only within this distance of the zone being worked (m).
@export_range(5.0, 60.0, 1.0) var wire_zone_range_m: float = 24.0
## Path distances (m back from the zone centre toward the enemy) tried as
## wire sites; the narrowest site wins.
@export var wire_path_offsets_m: PackedFloat32Array = PackedFloat32Array([8.0, 12.0, 16.0])
## Skip a site whose free width (m) is under this (no wire fits).
@export_range(1.0, 10.0, 0.5) var wire_min_width_m: float = 3.0
## Margin from the bot to both anchors inside the skill's range (m).
@export_range(0.0, 10.0, 0.5) var wire_range_margin_m: float = 2.0

@export_group("Relay Hop")
## Escape when at or below this HP fraction and hurt recently.
@export_range(0.0, 1.0, 0.01) var hop_escape_hp_frac: float = 0.35
## The gadget must be at least this much closer to home (escape) or to the
## fight (reposition), in metres.
@export_range(1.0, 40.0, 0.5) var hop_min_gain_m: float = 10.0
## Reposition only toward a fight at least this far away (m), healthy.
@export_range(5.0, 80.0, 1.0) var hop_reposition_min_target_m: float = 28.0
@export_range(0.0, 1.0, 0.01) var hop_reposition_min_hp_frac: float = 0.6
@export_range(0.0, 10.0, 0.5) var hop_range_margin_m: float = 2.0
