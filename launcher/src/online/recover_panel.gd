class_name LauncherRecoverPanel
extends VBoxContainer
## "Forgot password?" in the launcher's sign-in dialog (W21-N1). attach()
## adds a small link under the login fields and this panel next to them;
## the link swaps the login fields for: username, recovery code, new password
## twice. Success signs in like a login (LauncherLogin.login_result, which the
## launcher already handles) and the next recovery code is shown once in
## RecoveryCodeDialog (shared with the game). Passwords and codes are cleared
## from the fields right after sending; nothing is stored.
##
## Example (in the login dialog builder):
##   LauncherRecoverPanel.attach(_login_box, func() -> LauncherLogin: return _login)

var _box: VBoxContainer
var _get_login: Callable
var _link: Button
var _hidden: Array[Control] = []
var _user: LineEdit
var _code: LineEdit
var _pass: LineEdit
var _pass2: LineEdit
var _status: Label
var _send: Button
var _wired: LauncherLogin


## Adds the "Forgot password?" link and the hidden panel to `login_box`.
## `get_login` returns the LauncherLogin (it may be created later).
static func attach(login_box: VBoxContainer, get_login: Callable) -> LauncherRecoverPanel:
	var p := LauncherRecoverPanel.new()
	p._box = login_box
	p._get_login = get_login
	p._link = UiKit.button("Forgot password?", p.open, &"ghost", 28)
	p._link.add_theme_font_size_override("font_size", 12)
	login_box.add_child(p._link)
	login_box.add_child(p)
	p.visible = false
	return p


func _ready() -> void:
	var t: UiKitTokens = UiKit.tokens()
	add_theme_constant_override("separation", 8)
	var info: Label = UiKit.label("Enter your username, the recovery code you wrote down when you created the account (or the one the server host gave you) and a new password.", &"small", t.text_dim)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	_user = UiKit.line_edit("Username", 32)
	add_child(_user)
	_code = UiKit.line_edit("Recovery code (XXXXX-XXXXX-XXXXX-XXXXX)", 64)
	add_child(_code)
	_pass = UiKit.line_edit("New password", 128)
	_pass.secret = true
	add_child(_pass)
	_pass2 = UiKit.line_edit("New password again", 128)
	_pass2.secret = true
	_pass2.text_submitted.connect(func(_s: String) -> void: submit())
	add_child(_pass2)
	_status = UiKit.label("", &"small", t.warn)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_send = UiKit.button("Set new password", submit, &"primary", 42)
	add_child(_send)
	add_child(UiKit.button("Back to sign in", close, &"ghost", 28))


## Shows the panel instead of the login fields (username carried over).
func open() -> void:
	_hidden.clear()
	for c in _box.get_children():
		if c != self and c is Control and (c as Control).visible and not (c is Label and c.get_index() == 0):
			_hidden.append(c)
			(c as Control).visible = false
	var u := _login_user_edit()
	if u != null and _user.text == "":
		_user.text = u.text.strip_edges()
	_status.text = ""
	visible = true
	(_code if _user.text != "" else _user).grab_focus.call_deferred()


## Back to the login fields.
func close() -> void:
	visible = false
	for c in _hidden:
		if is_instance_valid(c):
			c.visible = true
	_hidden.clear()


## Checks the fields and sends the request (or shows what is wrong).
func submit() -> void:
	var err := check(_user.text, _code.text, _pass.text, _pass2.text)
	if err != "":
		_status.text = err
		return
	var login: LauncherLogin = _get_login.call() if _get_login.is_valid() else null
	if login == null:
		_status.text = "Not connected to the server."
		return
	_wire(login)
	_status.text = "Working ..."
	_send.disabled = true
	login.recover(_user.text, _code.text, _pass.text)
	_pass.text = ""
	_pass2.text = ""
	_code.text = ""


## Client-side checks (the server checks again); "" = fine.
static func check(user: String, code: String, pw: String, again: String) -> String:
	if user.strip_edges() == "" or code.strip_edges() == "":
		return "Enter your username and the recovery code."
	var n := pw.to_utf8_buffer().size()
	var rules := AuthConfig.rules()  # AuthRulesDef (shared with the game)
	if n < rules.password_min or n > rules.password_max:
		return "The new password needs %d to %d characters." % [rules.password_min, rules.password_max]
	if pw != again:
		return "The two new passwords differ."
	return ""


## Testing / automation: fill the fields.
func fill(user: String, code: String, pw: String) -> void:
	_user.text = user
	_code.text = code
	_pass.text = pw
	_pass2.text = pw


## The status line (tests).
func status_text() -> String:
	return _status.text


func _wire(login: LauncherLogin) -> void:
	if _wired == login:
		return
	_wired = login
	login.recover_failed.connect(func(msg: String) -> void:
		_send.disabled = false
		_status.text = msg)
	login.recovery_code_issued.connect(func(code: String) -> void:
		_send.disabled = false
		var u := _login_user_edit()
		if u != null:
			u.text = _user.text.strip_edges()  # the launcher remembers this username
		close()
		RecoveryCodeDialog.show_if_issued(self, {"code": 0, "recovery_code": code}))


## The login dialog's username field: its first visible-or-hidden plain LineEdit.
func _login_user_edit() -> LineEdit:
	for c in _box.get_children():
		if c is LineEdit and not (c as LineEdit).secret:
			return c
	return null
