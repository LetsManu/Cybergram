class_name BotSkillRules
extends RefCounted
## Per-skill usage rules for the M1 kits (architecture.md §9 "BotSkillRule:
## condition -> slot"), keyed by SkillDef.id so they follow the data, not the
## slot order. Each rule reads the blackboard and the hero and returns a
## SkillUse (or null). Tuning numbers are PLACEHOLDER.
##   Brannoc: Aegis Wall when under fire, Ram Charge at a hero 3-11 m away,
##            Fortify when hurt under fire, Earthbreaker on a hero 6-24 m away.
##   Ryker / Sable / Liora (wave 9): see the per-skill rules below.
##   Vesper:  Marionette Thread on a hero in thread range, Rally Beacon on the
##            hardpoint she is working (or at her feet when hurt), Rewrite when
##            enemies crowd her. Threadstep is not used by bots yet.

enum Aim { NONE, TRACK, POINT }

class SkillUse:
	var slot: int = 0
	var aim: int = Aim.NONE
	var point: Vector3 = Vector3.ZERO
	## W10-W3: a second POINT press to queue after this one lands (Tripwire anchor B).
	var then_point: Vector3 = Vector3.ZERO
	var has_then: bool = false
	## Press even though the skill is on cooldown (recast: remote detonation, Tripwire B).
	var recast: bool = false

	func _init(s: int, a: int, p: Vector3 = Vector3.ZERO) -> void:
		slot = s
		aim = a
		point = p


## Fraction of ground distance in front of Brannoc where the wall goes.
const WALL_AHEAD_M: float = 5.0


## PLACEHOLDER. Gravity of thrown bodies (ThrownEffectDef.gravity) and the lift
## the throw adds to the aim, for the grenade lob.
const THROW_GRAVITY: float = 20.0
const THROW_LIFT: float = 0.18


## Aim point that makes a thrown body (speed `v`) land near `target`: the low
## launch angle for the range, minus the lift the throw adds itself.
static func _lob_point(h: HeroBody, target: Vector3, v: float) -> Vector3:
	var eye := h.state.position + Vector3(0.0, h.eye_height(), 0.0)
	var to := target + Vector3(0.0, 1.0, 0.0) - eye
	var flat := Vector2(to.x, to.z).length()
	var theta := 0.5 * asin(clampf(THROW_GRAVITY * flat / maxf(v * v, 1.0), 0.0, 1.0))
	var phi := theta - THROW_LIFT * 0.9
	var dir := Vector3(to.x, 0.0, to.z).normalized() * cos(phi) + Vector3.UP * sin(phi)
	return eye + dir * maxf(flat, 1.0)


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
			&"skill_ryker_frag_grenade":
				if hero_t and bb.target_dist >= 6.0 and bb.target_dist <= 16.0:
					return SkillUse.new(s.slot, Aim.POINT, _lob_point(h, bb.target_pos, s.param(&"speed")))
			&"skill_ryker_combat_stim":
				if hero_t and bb.target_dist <= 30.0 and bb.hp_frac > 0.5:
					return SkillUse.new(s.slot, Aim.NONE)
			&"skill_ryker_tactical_slide":
				if hero_t and bb.target_dist >= 9.0 and bb.target_dist <= 22.0:
					return SkillUse.new(s.slot, Aim.TRACK)
			&"skill_ryker_overdrive":
				if hero_t and bb.target_dist <= 35.0:
					return SkillUse.new(s.slot, Aim.NONE)
			&"skill_sable_veilwalk":
				if hero_t and bb.target_dist > 14.0 and not hurt_now:
					return SkillUse.new(s.slot, Aim.NONE)
			&"skill_sable_phase_shift":
				if hurt_now and bb.hp_frac < 0.5:
					return SkillUse.new(s.slot, Aim.NONE)
			&"skill_sable_sabotage_charge":
				if zone_radius > 0.0 and BotBlackboard.flat_dist(pos, zone_center) < zone_radius:
					return SkillUse.new(s.slot, Aim.POINT, zone_center)
			&"skill_sable_eclipse_step":
				if hero_t and bb.target_dist >= 8.0 and bb.target_dist <= s.param(&"range") - 5.0:
					return SkillUse.new(s.slot, Aim.TRACK)
			&"skill_liora_med_pack_drone":
				if hurt_now and bb.hp_frac < 0.8:
					return SkillUse.new(s.slot, Aim.POINT, pos)
			&"skill_liora_prism_ward":
				if hurt_now and bb.hp_frac < 0.7:
					return SkillUse.new(s.slot, Aim.NONE)
			&"skill_liora_flash_bloom":
				if hero_t and bb.target_dist <= 9.0:
					return SkillUse.new(s.slot, Aim.POINT, bb.target_pos)
			&"skill_liora_aurora":
				if (hurt_now and bb.hp_frac < 0.5) or (hero_t and bb.target_dist < 10.0 and bb.hp_frac < 0.8):
					return SkillUse.new(s.slot, Aim.NONE)
			# W9-H2 Juniper Quill (Trapper) and Hex (Hacker). Tripwire Lattice (two presses)
			# and Relay Hop (a gadget under the crosshair) are BotSkillBehaviours, driven
			# from BotBrain._decide_special.
			&"skill_juniper_snare_coil":
				if hero_t and bb.target_dist >= 5.0 and bb.target_dist <= s.param(&"range") - 2.0:
					return SkillUse.new(s.slot, Aim.POINT, bb.target_pos)
			&"skill_juniper_pressure_mine":
				if zone_radius > 0.0 and BotBlackboard.flat_dist(pos, zone_center) < minf(zone_radius, s.param(&"range") - 2.0):
					return SkillUse.new(s.slot, Aim.POINT, zone_center)
				if hero_t and bb.target_dist >= 5.0 and bb.target_dist <= 16.0:
					return SkillUse.new(s.slot, Aim.POINT, bb.target_pos)
			&"skill_juniper_killbox":
				if hero_t and bb.target_dist >= 6.0 and bb.target_dist <= s.param(&"range") - 2.0:
					return SkillUse.new(s.slot, Aim.POINT, bb.target_pos)
			&"skill_hex_breach_spike":
				if hero_t and bb.target_dist <= s.param(&"range") - 3.0:
					return SkillUse.new(s.slot, Aim.TRACK)
			&"skill_hex_static_field":
				if hero_t and bb.target_dist >= 3.0 and bb.target_dist <= 16.0:
					return SkillUse.new(s.slot, Aim.POINT, bb.target_pos)
			&"skill_hex_zero_day":
				if (bb.enemy_wardlings_seen >= 3 or hero_t) and bb.target_dist >= 8.0 and bb.target_dist <= s.param(&"range") - 4.0:
					return SkillUse.new(s.slot, Aim.POINT, bb.target_pos)
	return null
