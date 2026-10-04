class_name TrapEffectDef
extends EffectDef
## Juniper Quill's placed traps (heroes.md §4.3): Snare Coil, Tripwire Lattice,
## Pressure Mine. The shared Linkwork rules (budget, chain, orphan life) are
## data on the def; magnitudes (damage, root, radius, arm time...) come from
## the casting skill's params so Boost nodes need no code. Server-side state:
## TrapWorld.

enum Kind { SNARE, WIRE, MINE }

@export var kind: Kind = Kind.SNARE
## Tripwire only: false = press 1 (anchor A), true = recast press (anchor B).
@export var wire_close: bool = false
## PLACEHOLDER (heroes.md gives only the Tripwire's 90 s). Trap lifetime (s).
@export var life_s: float = 60.0
@export var hp_param: StringName = &"hp"
@export var arm_param: StringName = &"arm_time"
## Trigger reach (m): Snare 2, Mine 2 (heroes.md §4.3); the wire uses its segment.
@export var trigger_radius_m: float = 2.0
## Pressure Mines are triggered by Wardlings too; Snares and Tripwires by heroes only (§3.8).
@export var hits_wardlings: bool = false
## Mine blast: damage fraction at the edge (40%) and the Wardling multiplier (x1.5).
@export var edge_falloff: float = 0.4
@export var wardling_mult: float = 1.5
## Linkwork passive: trap budget across all skills, link distance (m), chain delay (s)
## and how long traps outlive a dead owner (s).
@export var budget: int = 6
@export var link_radius_m: float = 6.0
@export var chain_delay_s: float = 0.3
@export var orphan_life_s: float = 30.0


func apply(ctx: EffectContext) -> void:
	if kind == Kind.WIRE:
		ctx.world.traps.tripwire_press(ctx, self, wire_close)
	else:
		ctx.world.traps.spawn_trap(ctx, self, ctx.point)
