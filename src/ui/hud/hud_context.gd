class_name HudContext
extends RefCounted
## Shared state handed to every HUD widget by HudRoot: the client world (read
## only), settings, tuning, roster, theme resources and the current scale.

const THEME_PATH := "res://assets/ui/hud_theme.tres"

var session: Node
var client: ClientWorld
var settings: HudSettings
var tuning: HudTuningDef
var roster: RosterTracker
var theme: Theme
var font_body: Font
var font_display: Font
var font_numbers: Font
var panel: StyleBox
var panel_strong: StyleBox
var panel_own: StyleBox
## Design units -> pixels (HudLayout).
var scale: float = 1.0
## Overlay state that changes what the gameplay HUD shows (hud.md §14).
var armory_open: bool = false
var scoreboard_open: bool = false
## On the HQ Armory pad with the panel closed ([F] prompt).
var armory_prompt: bool = false


func _init(session_: Node, settings_: HudSettings, tuning_: HudTuningDef) -> void:
	session = session_
	client = session.get("client") as ClientWorld if session != null else null
	settings = settings_
	tuning = tuning_
	roster = RosterTracker.new()
	theme = load(THEME_PATH) as Theme
	if theme == null:
		theme = Theme.new()
	font_body = _font("body")
	font_display = _font("display")
	font_numbers = _font("numbers")
	panel = _style("panel", HudPalette.PANEL)
	panel_strong = _style("panel_strong", HudPalette.PANEL_STRONG)
	panel_own = _style("panel_own", HudPalette.PANEL)


func team_color(team: int) -> Color:
	return HudPalette.team_color(team, settings.colorblind)


func own_team() -> int:
	return client.own_team() if client != null else 0


## Own hero's net id (0 until welcomed).
func own_id() -> int:
	return client.session.own_net_id if client != null and client.session != null else 0


func _font(name: String) -> Font:
	if theme.has_font(name, "Hud"):
		return theme.get_font(name, "Hud")
	return ThemeDB.fallback_font


func _style(name: String, bg: Color) -> StyleBox:
	if theme.has_stylebox(name, "Hud"):
		return theme.get_stylebox(name, "Hud")
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	return sb
