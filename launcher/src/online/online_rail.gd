class_name OnlineRail
extends PanelContainer
## The launcher's right rail (W15): server status (LauncherStatusWidget), the
## friends list (FriendsView) and the party (PartyView). Collapsible to a thin
## strip that keeps the status dot. Talks to the server only through the
## launcher's sign-in link (LauncherLogin); nothing is stored on disk.

const W_OPEN: int = 268
const W_CLOSED: int = 44
const TOP: int = 76
## Same as main.gd PLAY_BAR_H (the play bar under the rail).
const BOTTOM: int = 112

var status: LauncherStatusWidget
var social: SocialView
var login: LauncherLogin
var collapsed: bool = false
var _body: VBoxContainer
var _mini: VBoxContainer
var _mini_dot: ColorRect
var _social: VBoxContainer


func _init() -> void:
	name = "OnlineRail"


## Wires the rail to the launcher's probe and sign-in link (`login_` may be null).
func setup(probe: StatusProbe, version_url: String, login_: LauncherLogin) -> void:
	login = login_
	if login != null:
		social.bind(login)
	status.setup(probe, version_url, func() -> int: return login.rtt_ms() if login != null else -1,
		func() -> void:
			if login != null:
				login.ping())
	var preview: String = OnlinePreview.requested()
	if preview != "":
		(func() -> void: OnlinePreview.apply(get_parent(), preview)).call_deferred()
	probe.probed.connect(func(info: Dictionary) -> void:
		var t: UiKitTokens = UiKit.tokens()
		_mini_dot.color = t.ok if bool(info.get("reachable", false)) else t.danger)


func _ready() -> void:
	var t: UiKitTokens = UiKit.tokens()
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	clip_contents = true
	offset_top = TOP
	offset_bottom = -BOTTOM
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(t.bg_deep, 0.94)
	sb.border_width_left = 1
	sb.border_color = t.line
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)
	var stack: Control = Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_body = VBoxContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.add_theme_constant_override("separation", 12)
	stack.add_child(_body)
	var head: HBoxContainer = HBoxContainer.new()
	_body.add_child(head)
	var title: Label = UiKit.eyebrow("SERVER", t.text_dim, 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.icon_button(&"right", func() -> void: set_collapsed(true), "Hide the panel", 24))
	status = LauncherStatusWidget.new()
	_body.add_child(status)
	_body.add_child(UiKit.hairline())
	_social = VBoxContainer.new()
	_social.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_social.add_theme_constant_override("separation", 12)
	_body.add_child(_social)
	social = SocialView.new()
	_social.add_child(social)
	_mini = VBoxContainer.new()
	_mini.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mini.add_theme_constant_override("separation", 14)
	_mini.visible = false
	stack.add_child(_mini)
	_mini.add_child(UiKit.icon_button(&"left", func() -> void: set_collapsed(false), "Show server, friends and party", 24))
	_mini_dot = ColorRect.new()
	_mini_dot.custom_minimum_size = Vector2(8, 8)
	_mini_dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mini_dot.color = t.text_off
	_mini.add_child(_mini_dot)
	set_collapsed(false)


## Adds a section (friends, party) under the status.
func add_section(c: Control) -> void:
	_social.add_child(c)


func set_collapsed(c: bool) -> void:
	collapsed = c
	_body.visible = not c
	_mini.visible = c
	var sb: StyleBoxFlat = get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.content_margin_left = 10 if c else 18
		sb.content_margin_right = 10 if c else 18
	offset_left = -(W_CLOSED if c else W_OPEN)
	offset_right = 0
