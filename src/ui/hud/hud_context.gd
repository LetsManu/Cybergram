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
## v0.12: IBM Plex Mono (keys, lane letters, small counters).
var font_mono: Font
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
## v0.12 idle fade progress (0 = active, 1 = fully faded), eased by HudRoot.
var idle_k: float = 0.0
## The last input came from a gamepad (key chips show pad glyphs).
var pad_active: bool = false
## Key chip label cache: "<action>/<pad>" -> text; HudRoot clears it.
var key_labels: Dictionary = {}


func _init(session_: Node, settings_: HudSettings, tuning_: HudTuningDef) -> void:
	session = session_
	client = session.get("client") as ClientWorld if session != null else null
	settings = settings_
	tuning = tuning_
	roster = RosterTracker.new()
	theme = load(THEME_PATH) as Theme
	if theme == null:
		theme = Theme.new()
	# v0.12: the UI kit faces (Chakra Petch / IBM Plex), the same files as the menus.
	font_body = UiKit.body_font(500)
	font_display = UiKit.display_font(600, 0)
	font_numbers = UiKit.display_font(600, 0)
	font_mono = UiKit.mono_font()
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


## Chakra Petch SemiBold with `em` letter tracking at `px` (cached by UiKit).
func caps_font(px: int, em: float) -> Font:
	return UiKit.display_font(600, UiKit.track(px, em))


## Text shown on a key chip for `action`: the current keyboard binding, or the
## gamepad binding while a pad is in use; `fallback` if unbound / unknown.
func key_label(action: StringName, fallback: String) -> String:
	var k := "%s/%d" % [action, int(pad_active)]
	if key_labels.has(k):
		return key_labels[k]
	var t := fallback
	var b := GameSettings.shared().bindings if GameSettings.shared() != null else null
	if b != null and String(action) in InputBindings.action_ids():
		if pad_active:
			var ps := b.get_pad_spec(String(action))
			if ps != InputBindings.UNBOUND:
				t = short_pad(InputBindings.joy_spec_text(ps))
		else:
			var ks := b.get_spec(String(action))
			if ks != InputBindings.UNBOUND:
				t = InputBindings.spec_text(ks)
	if t.length() > 5:
		t = t.substr(0, 5)
	key_labels[k] = t
	return t


## Compact pad glyph text for a chip ("D-Pad Up" -> "D↑").
static func short_pad(t: String) -> String:
	match t:
		"D-Pad Up":
			return "D↑"
		"D-Pad Down":
			return "D↓"
		"D-Pad Left":
			return "D←"
		"D-Pad Right":
			return "D→"
	return t


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
