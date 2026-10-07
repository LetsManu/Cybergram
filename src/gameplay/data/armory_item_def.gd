class_name ArmoryItemDef
extends Resource
## One Armory item (wardlings-and-economy.md §7, §19; weapons-and-mods.md §3.6,
## §3.8, §3.10). A MOUNT is a Crystal / Chip line with 3 tiers (prices and
## values per tier); AMMO is a Chamber Ammo Type; SQUAD upgrades last for the
## match; CONSUMABLE is carried (Med-Pack). Effects are hero-scope Modifiers
## (StatCatalog HERO_NAMES), never code paths.
##
## Armory v2 (items-and-armory.md, protocol 22) adds recipe items: weapon parts
## (MOUNT) and body GEAR at three tiers (Component -> Assembly -> Signature),
## AMMO_MOD for the Chamber, any number of stats ("Recipe (v22)" group) and a
## named Signature passive. v1 tier lines keep using prices / values.

enum Kind { CONSUMABLE, SQUAD, MOUNT, AMMO, AMMO_MOD, GEAR }
## v22 recipe tier (NONE = v1 tiered line or a non-recipe item).
enum Tier { NONE, COMPONENT, ASSEMBLY, SIGNATURE }
enum Socket { NONE, CORE, BARREL, FRAME, CHAMBER }
## Crystals fit Mana guns, Chips Mechanical guns (§3.6.4 rule 2).
enum Family { ANY, CRYSTAL, CHIP }

@export var id: StringName = &""
@export var display_name: String = ""
## One-line effect text for the Armory list.
@export var effect_text: String = ""
@export var kind: Kind = Kind.CONSUMABLE
@export var socket: Socket = Socket.NONE
@export var family: Family = Family.ANY
## List price per tier (one entry for untiered items).
@export var prices: PackedInt32Array = PackedInt32Array([100])
## Hero-scope stat changed per tier (StatCatalog name), op and tier values.
@export var stat: StringName = &""
@export var op: Modifier.Op = Modifier.Op.ADD
@export var values: PackedFloat32Array = PackedFloat32Array()
## Optional second stat (Flux Coil: regen delay).
@export var stat2: StringName = &""
@export var op2: Modifier.Op = Modifier.Op.ADD
@export var values2: PackedFloat32Array = PackedFloat32Array()
## AMMO: DamageMath.AMMO_*.
@export var ammo_type: int = 0
## Another item that must be owned first (Squad Expansion II needs I).
@export var requires: StringName = &""
## CONSUMABLE carry limit (Med-Pack 3).
@export_range(0, 99) var carry_limit: int = 0
## Family hue (art: kept out of the team blue / red ranges).
@export var hue: Color = Color(1.0, 0.7, 0.2)

@export_group("Recipe (v22)")
@export var tier: Tier = Tier.NONE
## Part ids, in order (an id may repeat: Vital Core = two Vital Cells).
@export var recipe: PackedStringArray = PackedStringArray()
## Extra Lumen to combine the parts (Assemblies and Signatures).
@export_range(0, 5000) var combine_cost: int = 0
## Stats, one value each (StatCatalog hero names, Modifier.Op, value).
@export var stat_ids: PackedStringArray = PackedStringArray()
@export var stat_ops: PackedInt32Array = PackedInt32Array()
@export var stat_values: PackedFloat32Array = PackedFloat32Array()
## Mechanical-gun stats when they differ (Feed items); empty = the ones above.
@export var mech_stat_ids: PackedStringArray = PackedStringArray()
@export var mech_stat_ops: PackedInt32Array = PackedInt32Array()
@export var mech_stat_values: PackedFloat32Array = PackedFloat32Array()
## Signature passive id (C3 hooks; &"" = none).
@export var passive: StringName = &""
## AMMO_MOD: DamageMath.MOD_* (0 = none).
@export var ammo_mod: int = 0
## Where an open-slot item shows on the hero (§3.8): &"body_belt", &"body_chest"...
@export var body_anchor: StringName = &""
## Name on Mechanical guns (Chip form); display_name is the Crystal form.
@export var chip_name: String = ""

@export_group("Guide")
## Build-guide metadata (docs/armory.md). None of it changes what the item
## does; the Armory list, BuildAdvisor and ArmoryValidator read it.
## Broad shelf for filters: &"offense", &"defense", &"utility", &"squad", &"supply".
@export var category: StringName = &""
## Role in a build: starter, core, defensive, offensive, utility, counter, luxury.
@export var tags: PackedStringArray = PackedStringArray()
## Enemy threats this item answers (HeroDef.tags vocabulary: cc, burst,
## sustain, weapon_dps, skill_dps, mobility, zone, squad, frontline).
@export var counter_tags: PackedStringArray = PackedStringArray()
## Extra search words (lowercase).
@export var keywords: PackedStringArray = PackedStringArray()
## When it usually fits: &"early", &"mid", &"late" (&"" = any time).
@export var phase: StringName = &""
## Safe pick for new players.
@export var beginner: bool = false
## Only worth it in some matches (the guide says when).
@export var situational: bool = false
## Items sharing a non-empty group never stack their effect (only one may be held).
@export var unique_group: StringName = &""
## Localization key of the one-line "why buy this" text.
@export var explain_key: String = ""
## Localization keys for name and effect (empty = display_name / effect_text).
@export var name_key: String = ""
@export var effect_key: String = ""
## Kept out of build guides (still buyable from the catalog).
@export var hidden_in_guides: bool = false
## Switched off for this catalog (server refuses with DISABLED; still listed, greyed).
@export var disabled: bool = false


func tiers() -> int:
	return prices.size()


func price(tier: int) -> int:
	return prices[clampi(tier, 1, prices.size()) - 1]


## True if this item can go on `weapon` (family vs feed kind).
func fits(weapon: WeaponDef) -> bool:
	if family == Family.ANY or weapon == null:
		return family == Family.ANY
	return (family == Family.CRYSTAL) == (weapon.feed_kind == WeaponDef.FeedKind.MANA)


## Modifiers of `tier` tagged `source`.
func modifiers(tier: int, source: int) -> Array[Modifier]:
	var out: Array[Modifier] = []
	var i := clampi(tier, 1, maxi(1, values.size())) - 1
	if stat != &"" and i < values.size():
		out.append(Modifier.make(StatCatalog.hero_index(stat), op, values[i], source))
	if stat2 != &"" and i < values2.size():
		out.append(Modifier.make(StatCatalog.hero_index(stat2), op2, values2[i], source))
	return out


## v22: true for recipe items (Component / Assembly / Signature).
func is_recipe_item() -> bool:
	return tier != Tier.NONE


## v22: true when the item goes in an open slot (components and gear), false
## when it mounts on a gun socket (weapon Assemblies / Signatures).
func uses_open_slot() -> bool:
	return tier == Tier.COMPONENT or kind == Kind.GEAR


## v22 modifiers tagged `source` for a gun of `mana_gun` family.
func v2_modifiers(mana_gun: bool, source: int) -> Array[Modifier]:
	var ids := stat_ids
	var ops := stat_ops
	var vals := stat_values
	if not mana_gun and not mech_stat_ids.is_empty():
		ids = mech_stat_ids
		ops = mech_stat_ops
		vals = mech_stat_values
	var out: Array[Modifier] = []
	for i in mini(ids.size(), mini(ops.size(), vals.size())):
		var si := StatCatalog.hero_index(StringName(ids[i]))
		if si >= 0:
			out.append(Modifier.make(si, ops[i] as Modifier.Op, vals[i], source))
	return out


## Name for a gun family (Chip form on Mechanical guns).
func label_for(mana_gun: bool) -> String:
	return chip_name if not mana_gun and chip_name != "" else label()


## True if `tag` is one of this item's guide tags.
func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Player-facing name (localized when a key is set).
func label() -> String:
	return TranslationServer.translate(name_key) if name_key != "" else display_name


## Player-facing one-line effect (localized when a key is set).
func effect_label() -> String:
	return TranslationServer.translate(effect_key) if effect_key != "" else effect_text


## Slot this item occupies, as a short id for UI badges and validators:
## &"mount" (tiered socket line), &"ammo", &"squad" or &"consumable".
func slot_kind() -> StringName:
	if tier != Tier.NONE:
		return &"open" if uses_open_slot() else &"socket"
	match kind:
		Kind.MOUNT:
			return &"mount"
		Kind.AMMO, Kind.AMMO_MOD:
			return &"ammo"
		Kind.SQUAD:
			return &"squad"
	return &"consumable"
