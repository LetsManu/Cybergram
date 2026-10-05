class_name HudPalette
extends RefCounted
## HUD colour tokens (design/art-bible.md §4.1, §4.2, §4.4, §9) and the
## colour-blind team presets. Team colour is never the only cue: every widget
## that uses team_color() also draws a shape (chevron / diamond, solid / hatch).
## The world (hardpoint emissives, hero bodies) is not recoloured by a preset
## yet; that is the technical-artist `team_tint` uniform (art bible §4.3).

enum Preset { DEFAULT, DEUTERANOPIA, PROTANOPIA, TRITANOPIA }

## Ids used by settings files and `--colorblind <id>`.
const PRESET_IDS: Array[String] = ["default", "deuteranopia", "protanopia", "tritanopia"]
## Translation keys for the preset names (toasts, settings).
const PRESET_KEYS: Array[String] = ["HUD_CB_DEFAULT", "HUD_CB_DEUTERANOPIA", "HUD_CB_PROTANOPIA", "HUD_CB_TRITANOPIA"]

## Concord / Syndicate per preset (art bible §4.4 "Validated presets").
const TEAM_COLORS: Array = [
	[Color("#2E86FF"), Color("#FF5A1F")],
	[Color("#2B6CFF"), Color("#FFB000")],
	[Color("#2B6CFF"), Color("#FFB000")],
	[Color("#00C2D1"), Color("#FF3B7A")],
]
## Raw mana / neutral (leyfall_violet).
const NEUTRAL := Color("#8E5CFF")

## Panels: ≤ 65% opaque night ink with a 1 px light keyline (art bible §9).
## Retired from the in-match HUD in v0.12 (no boxes); kept for menus / tools.
const PANEL := Color(0.043, 0.055, 0.094, 0.65)
const PANEL_STRONG := Color(0.043, 0.055, 0.094, 0.85)
const KEYLINE := Color(0.79, 0.83, 0.89, 0.35)
const TEXT := Color("#EAF3FF")
const TEXT_DIM := Color(0.66, 0.7, 0.78)
const TEXT_OFF := Color(0.45, 0.47, 0.53)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
## Semantic colours (art bible §4.2).
const SP := Color("#B07CFF")
const RESONANCE := Color("#B07CFF")
const LUMEN := Color("#FFC93C")
const HEAL := Color("#4CE38A")
const CRIT := Color("#FFD447")
const WARN := Color("#FFB534")
const DANGER := Color("#FF4A3D")
## HP bar (hud.md §4.2: normal white, caution, critical) and shield overlay.
const HP := Color("#F4F7FF")
const SHIELD := Color("#FFFFFF")
## Weapon feed (hud.md §4.3): mana pool (leyfall violet, lifted), magazine,
## Burnout grey.
const MANA := Color("#A98BFF")
const MAG := Color("#E6F7FF")
const BURNOUT := Color(0.45, 0.45, 0.5)


## v0.12 premium-dark HUD (design/ux/hud-v0.12.md §1): mirrors of the UI kit
## tokens (assets/ui/ui_kit_tokens.tres) as constants so per-frame _draw code
## needs no resource lookups. Brass is the only accent / action colour, teal is
## status only, and none of these is a team cue (presets do not change them).
const INK := Color("#0B1015")
const INK_DEEP := Color("#080C10")
const IVORY := Color("#ECE6D6")
const MUTED := Color("#9AA3A8")
const DIM := Color("#6C757A")
const BRASS := Color("#C2A267")
const BRASS_HI := Color("#EAD7A8")
const BRASS_DIM := Color("#6B5A38")
const TEAL := Color("#4FB8B0")
## UI warn (debuffs, Overtime, respawn timers).
const WARN_UI := Color("#D0904E")
const HAIR := Color("#1E272D")
const HAIR_STRONG := Color("#2A3238")


## Colour of damage warnings (direction arc, damage vignette) under `preset`:
## the default red; the validated colour-blind presets use their enemy / warning
## colour (amber for red-green, pink for tritan), never red-on-green.
static func damage_color(preset: int = Preset.DEFAULT) -> Color:
	var p := clampi(preset, 0, TEAM_COLORS.size() - 1)
	return DANGER if p == Preset.DEFAULT else TEAM_COLORS[p][1]


## Team colour of `team` (MapDef.TEAM_*; anything else = neutral) under `preset`.
static func team_color(team: int, preset: int = Preset.DEFAULT) -> Color:
	if team < 0 or team > 1:
		return NEUTRAL
	var p := clampi(preset, 0, TEAM_COLORS.size() - 1)
	return TEAM_COLORS[p][team]


## Preset index from its id ("" or unknown = DEFAULT).
static func preset_from_id(id: String) -> int:
	var i := PRESET_IDS.find(id.to_lower())
	return i if i >= 0 else Preset.DEFAULT
