class_name NamePlateModel
extends RefCounted
## W11-V1: which hero plates (name + health bar) are drawn. Pure rules, no scene access.
## Allies: always (up to `plate_ally_max_distance_m`, no line of sight needed).
## Enemies: only in line of sight and within `plate_max_distance_m`.
## The name label is drawn on the plate by WorldOverlay; draw cost is one canvas
## item per overlay (screen-space, no per-hero nodes), so nothing needs pooling.


## True when a plate should be drawn for a living, visible hero.
static func is_visible(ally: bool, has_los: bool, distance_m: float, t: HudTuningDef) -> bool:
	if ally:
		return distance_m <= t.plate_ally_max_distance_m
	return has_los and distance_m <= t.plate_max_distance_m


## Number of basic skills with Mastery in an EntityState-style fork_bits value.
static func mastery_count(fork_bits: int) -> int:
	var n := 0
	for slot in 3:
		if ((fork_bits >> (slot * 3 + 2)) & 1) != 0:
			n += 1
	return n


## Fork (0 none, 1 A, 2 B) of `slot` in a fork_bits value.
static func fork_of(fork_bits: int, slot: int) -> int:
	return (fork_bits >> (slot * 3)) & 3


## Scoreboard text of the Fork choices, e.g. "A B -" (+ "*" for Mastery).
static func fork_text(fork_bits: int) -> String:
	var parts: PackedStringArray = []
	for slot in 3:
		var f := fork_of(fork_bits, slot)
		var s := "-" if f == 0 else ("A" if f == 1 else "B")
		if ((fork_bits >> (slot * 3 + 2)) & 1) != 0:
			s += "*"
		parts.append(s)
	return " ".join(parts)
