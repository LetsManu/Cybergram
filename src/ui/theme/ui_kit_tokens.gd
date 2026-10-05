class_name UiKitTokens
extends Resource
## Colours and metrics of the Cybergram UI kit (design/ux/ui-kit.md §2-§5).
## One file, `assets/ui/ui_kit_tokens.tres`, is shared by the game menus, the
## lobby and the launcher, so the whole client has a single palette.
##
## Example:
##   var t := UiKit.tokens()
##   label.add_theme_color_override("font_color", t.text_dim)

@export_group("Surfaces")
## Deepest ink (overlays, wells).
@export var bg_deep := Color("#080C10")
## Ground ink of every screen.
@export var bg := Color("#0B1015")
## The social rail / launcher rail surface.
@export var panel := Color(0.051, 0.075, 0.094, 0.97)
## Portrait wells, raised chips.
@export var panel_raised := Color("#111A20")
@export var panel_sunken := Color("#080C10")
## Hairlines: `line` between rows, `line_strong` for frames and separators.
@export var line := Color("#1E272D")
@export var line_strong := Color("#2A3238")

@export_group("Accents")
## Brass: the ONE action colour (PLAY, LOCK IN, selection, underlines).
@export var accent := Color("#C2A267")
@export var accent_hi := Color("#EAD7A8")
## Dim brass (key chip frames, quiet outlines).
@export var accent_dim := Color("#6B5A38")
## Kept for old call sites: same brass as `accent`.
@export var gold := Color("#C2A267")
## Status teal (online, picking). Old name kept for call sites.
@export var cyan := Color("#4FB8B0")
## In-match orange.
@export var in_match := Color("#D0904E")

@export_group("Text")
@export var text := Color("#ECE6D6")
@export var text_dim := Color("#9AA3A8")
@export var text_off := Color("#6C757A")

@export_group("Status")
@export var ok := Color("#4FB8B0")
@export var warn := Color("#D0904E")
@export var danger := Color("#C8574A")

@export_group("Type scale (px)")
@export var size_display: int = 56
@export var size_title: int = 28
@export var size_heading: int = 17
@export var size_nav: int = 15
@export var size_body: int = 16
@export var size_small: int = 13
@export var size_caption: int = 11

@export_group("Metrics (px)")
@export var space_xs: int = 4
@export var space_s: int = 8
@export var space_m: int = 12
@export var space_l: int = 16
@export var space_xl: int = 24
@export var space_xxl: int = 32
@export var radius: int = 2
## Clipped corner size of primary buttons.
@export var bevel: int = 10
@export var top_bar_height: int = 72
@export var header_height: int = 34
@export var sidebar_width: int = 280
@export var sidebar_collapsed: int = 52

@export_group("Motion (ms)")
@export var motion_fast: int = 120
@export var motion_base: int = 200
@export var motion_slow: int = 320
## Background spotlight breathing and hero turntable speed.
@export var bg_speed: float = 0.05
@export var turntable_deg_s: float = 12.0
