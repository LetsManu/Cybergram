@abstract
class_name EffectDef
extends Resource
## Stateless effect resource (ADR-0004 §4). Magnitudes are read from the
## casting skill's StatBlock by param name, so a Boost node that changes
## `damage` needs no effect change. Execution goes through ctx.world
## (AbilityWorld), the server-side executor.


@abstract func apply(ctx: EffectContext) -> void
