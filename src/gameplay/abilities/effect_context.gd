class_name EffectContext
extends RefCounted
## Everything an EffectDef needs to apply (ADR-0004 Key Interfaces): the world
## executor, caster, skill (its StatBlock gives magnitudes), aim and the target
## of this application. Areas and projectiles apply child effects with a copy
## whose `target` / `point` changed.

var world: AbilityWorld
var caster: HeroBody
var skill: SkillInstance
var team: int = 0
var tick: int = 0
## Eye position and unit aim direction at the press.
var origin: Vector3 = Vector3.ZERO
var dir: Vector3 = Vector3.FORWARD
var yaw: float = 0.0
## Resolved point (ground target, impact, landing, caster feet).
var point: Vector3 = Vector3.ZERO
## Hero or Wardling this application targets (null = none).
var target: Node3D


## Raw skill param (seconds, metres, fractions).
func param(name: StringName) -> float:
	return skill.param(name) if skill != null else 0.0


## Skill param scaled by SkillPower (heroes.md §3.3: damage, heals, shields).
func power_param(name: StringName) -> float:
	return param(name) * (caster.combat.skill_power() if caster != null and caster.combat != null else 1.0)


func ticks(name: StringName) -> int:
	return roundi(param(name) * world.tick_hz) if world != null else 0


func with_target(t: Node3D, at: Vector3) -> EffectContext:
	var c := EffectContext.new()
	c.world = world
	c.caster = caster
	c.skill = skill
	c.team = team
	c.tick = tick
	c.origin = origin
	c.dir = dir
	c.yaw = yaw
	c.point = at
	c.target = t
	return c


## Runs `effects` (EffectDef resources) with this context.
func run(effects: Array) -> void:
	for e in effects:
		if e is EffectDef:
			(e as EffectDef).apply(self)
