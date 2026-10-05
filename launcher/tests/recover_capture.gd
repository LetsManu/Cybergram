extends Control
## Evidence capture for W21-N1: the launcher's sign-in card (built like
## main.gd's login dialog) with "Forgot password?" open, or the show-once code
## dialog. `-- --view forgot|code`. Fixture data only; no server.

var _view := "forgot"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		_view = args[i + 1]
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t: UiKitTokens = UiKit.tokens()
	var bg: ColorRect = UiKit.background()
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(t.bg_deep, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := UiKit.card("SIGN IN", 20)
	card.custom_minimum_size.x = 420
	center.add_child(card)
	var box: VBoxContainer = card.body
	box.add_theme_constant_override("separation", 8)
	var status := UiKit.label("Wrong username or password. Sign in with your username, not your display name.", &"small", t.text_dim)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var user := UiKit.line_edit("Username", 32)
	user.text = "neo_runner"
	box.add_child(user)
	var pw := UiKit.line_edit("Password", 128)
	pw.secret = true
	box.add_child(pw)
	box.add_child(UiKit.button("Log in", Callable(), &"primary", 42))
	var panel := LauncherRecoverPanel.attach(box, func() -> LauncherLogin: return null)
	await get_tree().process_frame
	if _view == "forgot":
		panel.open()
		panel.fill("neo_runner", "7KQ2M-X4D9P-0RTB8-HV3NC", "a new password")
	else:
		RecoveryCodeDialog.show_if_issued(self, {"code": 0, "recovery_code": "7KQ2M-X4D9P-0RTB8-HV3NC"})
