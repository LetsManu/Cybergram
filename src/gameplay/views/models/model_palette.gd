class_name ModelPalette
extends RefCounted
## Colour tokens for the procedural stand-in models (design/art-bible.md §4.1,
## §4.7). Team colours are never baked into meshes: they reach the toon master
## as uniforms (see ModelMaterials), so these are the fixed zone colours only.

const TEAM_CONCORD: int = 0
const TEAM_SYNDICATE: int = 1
## No team (showcase / unknown).
const TEAM_NEUTRAL: int = -1

const AZURE_CORE := Color("#2E86FF")
const AZURE_LIGHT := Color("#EAF3FF")
const CONCORD_GOLD := Color("#E8B547")
const EMBER_CORE := Color("#FF5A1F")
const EMBER_DARK := Color("#1E1A1C")
const SYNDICATE_IRON := Color("#2B2629")
const SYNDICATE_BRASS := Color("#B48A4E")
const LEYFALL_VIOLET := Color("#8E5CFF")
const CHROME_COOL := Color("#C9D4E2")
const CHROME_WARM := Color("#BFA68A")
const NIGHT_INK := Color("#141726")
const HEAL_VERDANT := Color("#4CE38A")
const ELITE_GOLD := Color("#FFC93C")
const AETHER_VIOLET := Color("#B07CFF")
const HOLO_WHITE := Color("#E6F7FF")

## Neutrals shared by every hero (blacks, greys, skin, hair).
const INK := Color("#1C1D22")
const GREY := Color("#4A4C55")
const GREY_LIGHT := Color("#8C8F98")
const GUNMETAL := Color("#2F333B")
const RUBBER := Color("#232428")
const SKIN_A := Color("#E9B994")
const SKIN_B := Color("#C98F6B")
const SKIN_C := Color("#8E5A3E")

## Hero signature + secondary (art bible §4.7).
const SIGNATURE := {
	&"vesper": [Color("#5B2A6E"), Color("#D9A441")],
	&"sable": [Color("#22252B"), Color("#3FBF8F")],
	&"juniper": [Color("#D9A21B"), Color("#6B7B3A")],
	&"ryker": [Color("#4E5A45"), Color("#E3DCC8")],
	&"brannoc": [Color("#2F6E6A"), Color("#2A2826")],
	&"liora": [Color("#F2EDE4"), Color("#8DBF9A")],
	&"hex": [Color("#B6F23A"), Color("#18181C")],
}


static func team_color(team: int) -> Color:
	match team:
		TEAM_CONCORD:
			return AZURE_CORE
		TEAM_SYNDICATE:
			return EMBER_CORE
	return LEYFALL_VIOLET


static func signature(key: StringName) -> Color:
	return (SIGNATURE.get(key, [GREY, GREY_LIGHT]) as Array)[0]


static func secondary(key: StringName) -> Color:
	return (SIGNATURE.get(key, [GREY, GREY_LIGHT]) as Array)[1]
