class_name BotSkillRules
extends RefCounted
## Per-skill usage rules for the M1 kits (architecture.md §9 "BotSkillRule:
## condition -> slot"), keyed by SkillDef.id so they follow the data, not the
## slot order. Each rule reads the blackboard and the hero and returns a
## SkillUse (or null). Tuning numbers are PLACEHOLDER.
##   Brannoc: Aegis Wall when under fire, Ram Charge at a hero 3-11 m away,
##            Fortify when hurt under fire, Earthbreaker on a hero 6-24 m away.
##   Vesper:  Marionette Thread on a hero in thread range, Rally Beacon on the
##            hardpoint she is working (or at her feet when hurt), Rewrite when
##            enemies crowd her. Threadstep is not used by bots yet.

enum Aim { NONE, TRACK, POINT }

class SkillUse:
	var slot: int = 0
	var aim: int = Aim.NONE
	var point: Vector3 = Vector3.ZERO

	func _init(s: int, a: int, p: Vector3 = Vector3.ZERO) -> void:
		slot = s
		aim = a
		point = p


## Fraction of ground distance in front of Brannoc where the wall goes.
const WALL_AHEAD_M: float = 5.0


## First applicable skill use for this decision, or null. `ready` is a
## Callable(slot) -> bool (unlocked, off cooldown, not casting).
static func choose(skills: Array[SkillInstance], bb: BotBlackboard, h: HeroBody, ready: Callable,
		zone_center: Vector3, zone_radius: float) -> SkillUse:
	var pos := h.state.position
	var hurt_now := bb.seconds_since(bb.last_damaged_tick) < 1.0
	var hero_t := bb.target_id != 0 and bb.target_is_hero
	for s in skills:
		if not ready.call(s.slot):
			continue
		match s.def.id:
			&"skill_brannoc_aegis_wall":
				if hurt_now and hero_t and bb.target_dist > 9.0 and bb.target_dist < 40.0 and bb.hp_frac < 0.9:
					var flat := Vector3(bb.target_pos.x - pos.x, 0.0, bb.target_pos.z - pos.z).normalized()
					return SkillUse.new(s.slot, Aim.POINT, pos + flat * WALL_AHEAD_M)
			&"skill_brannoc_ram_charge":
				if hero_t and bb.target_dist >= 3.0 and bb.target_dist <= s.param(&"distance") - 1.0:
					return SkillUse.new(s.slot, Aim.TRACK)
			&"skill_brannoc_fortify":
				if hurt_now and bb.hp_frac < 0.7:
					return SkillUse.new(s.slot, Aim.NONE)
			&"skill_brannoc_earthbreaker":
				if hero_t and bb.target_dist >= 6.0 and bb.target_dist <= s.param(&"range") - 1.0:
					return SkillUse.new(s.slot, Aim.POINT, bb.target_pos)
			&"skill_vesper_marionette_thread":
				if hero_t and bb.target_dist <= s.param(&"range") - 2.0:
					return SkillUse.new(s.slot, Aim.TRACK)
			&"skill_vesper_rally_beacon":
				var r := s.param(&"range") - 2.0
				if hurt_now and bb.hp_frac < 0.6:
					return SkillUse.new(s.slot, Aim.POINT, pos + Vector3(0.0, 0.0, 0.0))
				if zone_radius > 0.0 and BotBlackboard.flat_dist(pos, zone_center) < minf(zone_radius, r):
					return SkillUse.new(s.slot, Aim.POINT, zone_center)
			&"skill_vesper_rewrite":
				if bb.enemy_wardlings_seen >= 3 or (hero_t and bb.target_dist < 15.0):
					return SkillUse.new(s.slot, Aim.NONE)
	return null
