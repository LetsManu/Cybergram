class_name LoginScreen
extends PanelContainer
## Online sign-in ahead of the lobby (design/ux/lobby-and-social.md §6):
## LOG IN, CREATE ACCOUNT (privacy notice + "I am at least 14", and the note
## that there is no password recovery) or PLAY AS GUEST. Display only: it
## emits `submitted(op, fields)`; the menu sends it and calls show_error() /
## the menu closes it on success. Nothing is stored except the optional
## "remember username" (menu.cfg, done by the menu).
##
## Example:
##   var ls := LoginScreen.new()
##   ls.server_text = "cyber.djboeck.at (encrypted)"
##   ls.submitted.connect(func(op, f): online.request(op, f))

signal submitted(op: int, fields: Dictionary)
signal cancelled

enum Mode { LOGIN, REGISTER, GUEST }

const PRIVACY_URL := "https://github.com/LetsManu/Cybergram/blob/main/PRIVACY.md"

## Shown under the title ("host:port · encrypted").
var server_text: String = ""
## Accounts possible on this link (DTLS); false = guest only.
var accounts_available: bool = true
var remembered_username: String = ""
var remember: bool = false
## Pre-fill for register / guest (e.g. an old local profile).
var prefill_name: String = ""
var prefill_emblem: int = 0
var prefill_accent: int = 0

var mode: Mode = Mode.LOGIN
var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _msg: Label
var _user: LineEdit
var _pass: LineEdit
var _remember: CheckBox
var _r_user: LineEdit
var _r_pass: LineEdit
var _r_pass2: LineEdit
var _r_name: LineEdit
var _r_privacy: CheckBox
var _r_age: CheckBox
var _g_name: LineEdit
var _g_privacy: CheckBox
var _emblem: int = 0
var _accent: int = 0
var _pickers: Array[HBoxContainer] = []


func _ready() -> void:
	HudStrings.ensure_loaded()
	_emblem = prefill_emblem
	_accent = prefill_accent
	custom_minimum_size = Vector2(620, 0)
	var col := UiKit.screen_frame(self, tr("HUD_LOGIN_TITLE"), server_text)
	var tabs := UiKit.tab_bar([tr("HUD_LOGIN_TAB_LOGIN"), tr("HUD_LOGIN_TAB_REGISTER"), tr("HUD_LOGIN_TAB_GUEST")],
		func(m: int) -> void: set_mode(m))
	for b: Button in tabs.get_children():
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.append(b)
	col.add_child(tabs)
	col.add_child(HSeparator.new())
	_pages.append(_login_page())
	_pages.append(_register_page())
	_pages.append(_guest_page())
	for p in _pages:
		col.add_child(p)
	_msg = MenuStyle.label("", 13, HudPalette.WARN, HORIZONTAL_ALIGNMENT_CENTER)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_msg)
	col.add_child(UiKit.button(tr("HUD_LOGIN_BACK"), func() -> void: cancelled.emit(), &"ghost", 36))
	if not accounts_available:
		_tabs[0].disabled = true
		_tabs[1].disabled = true
		show_error(tr("HUD_LOGIN_NO_TLS"))
		set_mode(Mode.GUEST)
	else:
		set_mode(Mode.LOGIN if remembered_username != "" or prefill_name == "" else Mode.REGISTER)


func set_mode(m: Mode) -> void:
	mode = m
	for i in _pages.size():
		_pages[i].visible = i == m
		_tabs[i].set_pressed_no_signal(i == m)
	_refresh_pickers()
	var first: LineEdit = [_user if remembered_username == "" else _pass, _r_user, _g_name][m]
	first.grab_focus.call_deferred()


## A server answer that failed (already translated).
func show_error(text: String) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", HudPalette.WARN)


func show_info(text: String) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", HudPalette.TEXT_DIM)


## Whether "remember username" is ticked (the menu saves it).
func remember_username() -> bool:
	return _remember.button_pressed


## The username typed on the login page.
func login_username() -> String:
	return _user.text.strip_edges()


func _login_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(MenuStyle.label(tr("HUD_LOGIN_USERNAME"), 13, HudPalette.TEXT_DIM))
	_user = MenuStyle.line_edit(tr("HUD_LOGIN_USERNAME"), PlayerProfile.NAME_MAX)
	_user.text = remembered_username
	v.add_child(_user)
	v.add_child(MenuStyle.label(tr("HUD_LOGIN_PASSWORD"), 13, HudPalette.TEXT_DIM))
	_pass = _secret()
	_pass.text_submitted.connect(func(_t: String) -> void: _submit_login())
	v.add_child(_pass)
	_remember = CheckBox.new()
	_remember.text = tr("HUD_LOGIN_REMEMBER")
	_remember.button_pressed = remember
	v.add_child(_remember)
	v.add_child(UiKit.spacer(4))
	v.add_child(UiKit.button(tr("HUD_LOGIN_SUBMIT"), _submit_login, &"primary"))
	return v


func _register_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_r_user = MenuStyle.line_edit(tr("HUD_LOGIN_USERNAME"), PlayerProfile.NAME_MAX)
	_r_user.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_r_user)
	_r_name = MenuStyle.line_edit(tr("HUD_LOGIN_DISPLAY_NAME"), PlayerProfile.NAME_MAX)
	_r_name.text = prefill_name
	_r_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_r_name)
	v.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_r_pass = _secret()
	_r_pass.placeholder_text = tr("HUD_LOGIN_PASSWORD")
	_r_pass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_r_pass)
	_r_pass2 = _secret()
	_r_pass2.placeholder_text = tr("HUD_LOGIN_PASSWORD_AGAIN")
	_r_pass2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_r_pass2)
	v.add_child(row2)
	v.add_child(_picker())
	var notice := MenuStyle.label(tr("HUD_LOGIN_PRIVACY_BODY"), 11, HudPalette.TEXT_DIM)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(notice)
	var prow := HBoxContainer.new()
	_r_privacy = _check(tr("HUD_LOGIN_PRIVACY_ACK"))
	_r_privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(_r_privacy)
	var read := UiKit.button(tr("HUD_PRIVACY_READ"), func() -> void: OS.shell_open(PRIVACY_URL), &"ghost", 28)
	read.add_theme_font_size_override("font_size", 11)
	prow.add_child(read)
	v.add_child(prow)
	_r_age = _check(tr("HUD_LOGIN_AGE") % AuthConfig.rules().min_age)
	v.add_child(_r_age)
	var rec := MenuStyle.label(tr("HUD_LOGIN_NO_RECOVERY"), 11, HudPalette.LUMEN)
	rec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(rec)
	v.add_child(UiKit.button(tr("HUD_LOGIN_CREATE"), _submit_register, &"primary", 46))
	return v


func _guest_page() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var info := MenuStyle.label(tr("HUD_LOGIN_GUEST_INFO"), 12, HudPalette.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info)
	_g_name = MenuStyle.line_edit(tr("HUD_LOGIN_DISPLAY_NAME"), PlayerProfile.NAME_MAX)
	_g_name.text = prefill_name
	v.add_child(_g_name)
	v.add_child(_picker())
	_g_privacy = _check(tr("HUD_LOGIN_GUEST_PRIVACY"))
	v.add_child(_g_privacy)
	v.add_child(UiKit.button(tr("HUD_LOGIN_GUEST_SUBMIT"), _submit_guest, &"primary"))
	return v


## Emblem + accent row (shared by register and guest).
func _picker() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	for i in PlayerProfile.EMBLEM_COUNT:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(30, 30)
		MenuStyle.style_button(b, Color(0.03, 0.035, 0.07, 0.9))
		var icon := EmblemIcon.make(i, _accent, 24.0)
		icon.position = Vector2(3, 3)
		icon.size = Vector2(24, 24)
		b.add_child(icon)
		b.pressed.connect(func() -> void:
			_emblem = i
			_refresh_pickers())
		h.add_child(b)
	h.add_child(MenuStyle.spacer(0))
	for i in PlayerProfile.ACCENTS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(16, 30)
		MenuStyle.style_button(b, PlayerProfile.ACCENTS[i])
		b.pressed.connect(func() -> void:
			_accent = i
			_refresh_pickers())
		h.add_child(b)
	_pickers.append(h)
	return h


func _refresh_pickers() -> void:
	for h in _pickers:
		var k := 0
		for c in h.get_children():
			if not (c is Button):
				continue
			var b := c as Button
			if k < PlayerProfile.EMBLEM_COUNT:
				b.set_pressed_no_signal(k == _emblem)
				(b.get_child(0) as EmblemIcon).accent = _accent
			else:
				b.set_pressed_no_signal(k - PlayerProfile.EMBLEM_COUNT == _accent)
			k += 1


func _submit_login() -> void:
	if _user.text.strip_edges() == "" or _pass.text == "":
		show_error(tr("HUD_LOGIN_ERR_EMPTY"))
		return
	show_info(tr("HUD_LOGIN_WORKING"))
	submitted.emit(AccountCodec.OP_LOGIN, {"ver": MsgType.PROTOCOL_VERSION, "username": _user.text.strip_edges(),
		"password": _pass.text})
	_pass.text = ""  # never kept in the UI


func _submit_register() -> void:
	var err := _register_error()
	if err != "":
		show_error(err)
		return
	var flags := AccountCodec.FLAG_PRIVACY | AccountCodec.FLAG_AGE
	show_info(tr("HUD_LOGIN_WORKING"))
	submitted.emit(AccountCodec.OP_REGISTER, {"ver": MsgType.PROTOCOL_VERSION, "username": _r_user.text.strip_edges(),
		"password": _r_pass.text, "display_name": _r_name.text.strip_edges(), "emblem": _emblem, "accent": _accent,
		"flags": flags})
	_r_pass.text = ""
	_r_pass2.text = ""


## Client-side checks (the server checks again); "" = fine.
func _register_error() -> String:
	if not AccountService.valid_username(_r_user.text.strip_edges()):
		return tr("HUD_ACCOUNT_ERR_6")
	var n := _r_pass.text.to_utf8_buffer().size()
	var rules := AuthConfig.rules()
	if n < rules.password_min or n > rules.password_max:
		return tr("HUD_LOGIN_ERR_PASSWORD") % [rules.password_min, rules.password_max]
	if _r_pass.text != _r_pass2.text:
		return tr("HUD_LOGIN_ERR_MISMATCH")
	var dn := _r_name.text.strip_edges()
	if PlayerProfile.validate_name(dn) != PlayerProfile.NameError.OK or not PlayerProfile.name_allowed(dn):
		return tr("HUD_ACCOUNT_ERR_8")
	if not _r_privacy.button_pressed:
		return tr("HUD_ACCOUNT_ERR_9")
	if not _r_age.button_pressed:
		return tr("HUD_ACCOUNT_ERR_10") % rules.min_age
	return ""


func _submit_guest() -> void:
	var dn := _g_name.text.strip_edges()
	if PlayerProfile.validate_name(dn) != PlayerProfile.NameError.OK or not PlayerProfile.name_allowed(dn):
		show_error(tr("HUD_ACCOUNT_ERR_8"))
		return
	if not _g_privacy.button_pressed:
		show_error(tr("HUD_ACCOUNT_ERR_9"))
		return
	show_info(tr("HUD_LOGIN_WORKING"))
	submitted.emit(AccountCodec.OP_GUEST, {"ver": MsgType.PROTOCOL_VERSION, "display_name": dn, "emblem": _emblem,
		"accent": _accent, "flags": AccountCodec.FLAG_PRIVACY})


## Testing / automation: fill the register form.
func fill_register(username: String, password: String, display: String, privacy: bool, age: bool) -> void:
	_r_user.text = username
	_r_pass.text = password
	_r_pass2.text = password
	_r_name.text = display
	_r_privacy.button_pressed = privacy
	_r_age.button_pressed = age


func _secret() -> LineEdit:
	var e := MenuStyle.line_edit("", AuthConfig.rules().password_max)
	e.secret = true
	return e


func _check(text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.add_theme_font_size_override("font_size", 12)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return c
