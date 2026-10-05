class_name LauncherStatusWidget
extends VBoxContainer
## Server status for the launcher's right rail (W15): online / offline, players
## online, your ping and the operator's message of the day.
## - Status + MOTD: StatusProbe (status.json on the update host, anonymous
##   counts), refreshed every REFRESH_S while the widget is visible and the
##   window is not minimised; nothing is fetched while hidden.
## - Ping: an RTT probe on the sign-in link (AccountCodec.OP_PING, a few
##   bytes every PING_EVERY_S while visible): `ping` Callable sends one,
##   `rtt` Callable -> int ms (-1 = no link / no answer yet).
## The MOTD is plain text in a Label (no BBCode, no links).

## Seconds between two status probes while visible.
const REFRESH_S: float = 30.0
## Seconds between two RTT probes (a 2-byte request, only while visible).
const PING_EVERY_S: float = 1.0

var probe: StatusProbe
var version_url: String = ""
var rtt: Callable = Callable()
var ping: Callable = Callable()
var _dot: ColorRect
var _state: Label
var _ping: Label
var _players: Label
var _motd: Label
var _since: float = REFRESH_S
var _since_ping: float = PING_EVERY_S


## `probe_` is shared with the launcher; `rtt_` returns the RTT in ms.
func setup(probe_: StatusProbe, version_url_: String, rtt_: Callable, ping_: Callable = Callable()) -> void:
	probe = probe_
	version_url = version_url_
	rtt = rtt_
	ping = ping_
	probe.probed.connect(show_info)
	_since = 0.0  # the launcher probes once at start itself
	show_info(probe.last)


func _ready() -> void:
	var t: UiKitTokens = UiKit.tokens()
	add_theme_constant_override("separation", 4)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_dot = ColorRect.new()
	_dot.custom_minimum_size = Vector2(8, 8)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.color = t.text_off
	row.add_child(_dot)
	_state = UiKit.eyebrow("CHECKING", t.text_dim, 12)
	_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_state)
	_ping = Label.new()
	_ping.add_theme_font_override("font", UiKit.mono_font())
	_ping.add_theme_font_size_override("font_size", 12)
	_ping.add_theme_color_override("font_color", t.text_dim)
	_ping.tooltip_text = "Round-trip time to the game server"
	_ping.mouse_filter = Control.MOUSE_FILTER_PASS
	_ping.text = OnlineText.ping_text(-1)
	row.add_child(_ping)
	_players = UiKit.label("", &"small", t.text_dim)
	add_child(_players)
	_motd = UiKit.label("", &"small", t.text)
	_motd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_motd.max_lines_visible = 5
	_motd.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_motd.custom_minimum_size.x = 200
	_motd.visible = false
	add_child(_motd)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _minimised():
		return  # refresh only while visible
	_since += delta
	_since_ping += delta
	if _since_ping >= PING_EVERY_S:
		_since_ping = 0.0
		show_ping(int(rtt.call()) if rtt.is_valid() else -1)
		if ping.is_valid():
			ping.call()
	if _since >= REFRESH_S and probe != null and not probe.busy:
		_since = 0.0
		probe.probe(version_url)


func _minimised() -> bool:
	return DisplayServer.get_name() != "headless" \
		and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED


## Paints a StatusProbe result.
func show_info(info: Dictionary) -> void:
	if _state == null:
		return
	var t: UiKitTokens = UiKit.tokens()
	var up: bool = bool(info.get("reachable", false))
	_state.text = OnlineText.state_word(info)
	_state.add_theme_color_override("font_color", t.ok if up else t.danger)
	_dot.color = t.ok if up else t.danger
	_players.text = OnlineText.players_line(info)
	var m: String = OnlineText.plain_text(String(info.get("motd", "")), OnlineText.MOTD_MAX_CHARS)
	_motd.text = m
	_motd.visible = m != "" and up


## Paints the ping (ms, -1 = unknown).
func show_ping(ms: int) -> void:
	if _ping == null:
		return
	var t: UiKitTokens = UiKit.tokens()
	_ping.text = OnlineText.ping_text(ms)
	var cols: Array = [t.ok, t.warn, t.danger]
	var band: int = OnlineText.ping_band(ms)
	_ping.add_theme_color_override("font_color", t.text_dim if band < 0 else cols[band])
