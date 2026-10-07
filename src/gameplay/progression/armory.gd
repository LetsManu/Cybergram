class_name Armory
extends RefCounted
## Source-id helper for catalog-item modifiers. The v1 tiered Armory (mounts,
## tiers, swap, sell, undo) was retired at the Armory v2 switch-over; purchases
## now go through ItemShop (items-and-armory.md, docs/armory.md). Each catalog
## item owns one SRC_MOD source on the hero StatBlock.


static func source_for(index: int) -> int:
	return Modifier.source(Modifier.SRC_MOD, index)
