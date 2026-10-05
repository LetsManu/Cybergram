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
@export var bg_deep := Color("#05060D")
@export var bg := Color("#0A0D1A")
@export var panel := Color(0.055, 0.07, 0.14, 0.86)
@export var panel_raised := Color(0.082, 0.102, 0.2, 0.94)
@export var panel_sunken := Color(0.024, 0.031, 0.075, 0.92)
@export var line := Color(0.79, 0.83, 0.89, 0.18)
@export var line_strong := Color(0.79, 0.83, 0.89, 0.38)

@export_group("Accents")
## Leyfall violet: the one "do this" colour.
@export var accent := Color("#8E5CFF")
@export var accent_hi := Color("#B794FF")
## Brass secondary accent (frames, ticks, the PLAY rim).
@export var gold := Color("#D9B26A")
## Information / network state.
@export var cyan := Color("#3FD8F2")

@export_group("Text")
@export var text := Color("#EAF3FF")
@export var text_dim := Color("#A8B2C7")
@export var text_off := Color("#6B7286")

@export_group("Status")
@export var ok := Color("#4CE38A")
@export var warn := Color("#FFB534")
@export var danger := Color("#FF4A3D")

@export_group("Type scale (px)")
@export var size_display: int = 44
@export var size_title: int = 26
@export var size_heading: int = 17
@export var size_nav: int = 14
@export var size_body: int = 15
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
@export var top_bar_height: int = 64
@export var header_height: int = 34
@export var sidebar_width: int = 280
@export var sidebar_collapsed: int = 52

@export_group("Motion (ms)")
@export var motion_fast: int = 120
@export var motion_base: int = 200
@export var motion_slow: int = 320
## Background grid drift and hero turntable speed.
@export var bg_speed: float = 0.05
@export var turntable_deg_s: float = 12.0
