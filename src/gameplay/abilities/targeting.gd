class_name Targeting
extends RefCounted
## Skill targeting modes (architecture.md §7.2 TargetingDef, abridged to the
## M1 kits). Resolves ctx.point / ctx.dir / ctx.target from the aim at the press.
## Returns false when the skill has no valid target (no cooldown is spent).

## PLACEHOLDER. ALLY_WARDLING: crosshair cone half-angle (degrees).
const ALLY_CONE_DEG: float = 12.0


static func resolve(def: SkillDef, ctx: EffectContext) -> bool:
	match def.targeting:
		SkillDef.TargetMode.SELF:
			ctx.point = ctx.caster.state.position if ctx.caster != null else ctx.point
			return true
		SkillDef.TargetMode.DIRECTION:
			ctx.dir = Basis(Vector3.UP, ctx.yaw) * Vector3.FORWARD
			return true
		SkillDef.TargetMode.PROJECTILE:
			return true
		SkillDef.TargetMode.GROUND:
			if ctx.world == null:
				ctx.point = ctx.origin + ctx.dir * ctx.param(&"range")
				return true
			ctx.point = ctx.world.ground_point(ctx.origin, ctx.dir, ctx.param(&"range"))
			return true
		SkillDef.TargetMode.ALLY_WARDLING:
			if ctx.world == null:
				return false
			ctx.target = ctx.world.aimed_ally_wardling(ctx.caster, ctx.origin, ctx.dir, ctx.param(&"range"),
				deg_to_rad(ALLY_CONE_DEG))
			if ctx.target == null:
				return false
			ctx.point = ctx.target.global_position
			return true
		SkillDef.TargetMode.GADGET:
			if ctx.world == null:
				return false
			return ctx.world.traps.aim_gadget(ctx, ctx.param(&"range"), deg_to_rad(ALLY_CONE_DEG))
	return false
