class_name FxForkTint
extends RefCounted
## W11-V1 (Pillar 4): tint of a skill's VFX by the caster's Fork, per faction palette.
## Fork A = cool, Fork B = warm; no Fork = untouched. Presentation only.

## [faction][fork - 1]: Concord (team 0) and Syndicate (team 1).
const TINTS: Array = [
	[Color("#4FE3FF"), Color("#FFC15A")],
	[Color("#8FB4FF"), Color("#FF6A3D")],
]
const STRENGTH: float = 0.5


## Tint colour, or Color(0, 0, 0, 0) for no Fork.
static func tint_for(team: int, fork: int) -> Color:
	if fork < 1 or fork > 2:
		return Color(0, 0, 0, 0)
	return TINTS[clampi(team, 0, 1)][fork - 1]


## Blends `base` toward the Fork tint (no change without a Fork).
static func apply(base: Color, team: int, fork: int) -> Color:
	var t := tint_for(team, fork)
	if t.a <= 0.0:
		return base
	var c := base.lerp(t, STRENGTH)
	c.a = base.a
	return c


## Recolours every StandardMaterial3D override under `root` (albedo and emission).
static func tint_tree(root: Node, team: int, fork: int) -> void:
	if fork < 1 or fork > 2:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override as StandardMaterial3D
		if m == null:
			continue
		m = m.duplicate() as StandardMaterial3D
		m.albedo_color = apply(m.albedo_color, team, fork)
		if m.emission_enabled:
			m.emission = apply(m.emission, team, fork)
		(n as MeshInstance3D).material_override = m
