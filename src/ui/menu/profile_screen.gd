class_name ProfileScreen
extends PanelContainer
## Account / profile screen (design/ux/lobby-and-social.md §6): display name,
## emblem, accent and favourite hero (UPDATE_PROFILE), and for accounts:
## change password, EXPORT MY DATA (the server's JSON, saved where the player
## picks), DELETE ACCOUNT (password + second press) and LOG OUT. Guests can
## edit the display fields of their session only. W21-N1: the recovery code
## row (asks RECOVERY_INFO on open; "No recovery code yet - create one" for
## older accounts; a new code needs the current password, the menu shows it
## with RecoveryCodeDialog). Display only: it emits
## `requested(op, fields)`; the menu forwards server answers to on_result().
##
## Example:
##   var ps := ProfileScreen.new()
##   ps.session = online.session
##   ps.requested.connect(online.request)

signal requested(op: int, fields: Dictionary)
signal closed

## The logged-in session ({display_name, emblem, accent, favourite_hero, guest, username, id}).
var session: Dictionary = {}
## Where the last export was written (tests read it).
var export_path: String = ""

var _name: LineEdit
var _hint: Label
var _msg: Label
var _hero: OptionButton
var _heroes: Array = []
var _emblems: Array[Button] = []
var _accents: Array[Button] = []
var _emblem: int = 0
var _accent: int = 0
var _old_pw: LineEdit
var _new_pw: LineEdit
var _del_pw: LineEdit
var _delete_btn: Button
var _rec_pw: LineEdit
var _rec_state: Label
var _rec_btn: Button
## RECOVERY_INFO answer: -1 unknown, 0 no code, 1 a code exists.
var recovery_state: int = -1
var _delete_armed: bool = false
var _pending_export: String = ""
var _dialog: FileDialog


func _ready() -> void:
	HudStrings.ensure_loaded()
	_emblem = int(session.get("emblem", 0))
	_accent = int(session.get("accent", 0))
	var guest: bool = int(session.get("guest", 0)) != 0
	custom_minimum_size = Vector2(660, 0)
	var who := tr("HUD_ACCOUNT_GUEST_LINE") if guest else tr("HUD_ACCOUNT_LINE") % str(session.get("username", ""))
	var col := UiKit.screen_frame(self, tr("HUD_PROFILE_TITLE"), who)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(MenuStyle.label(tr("HUD_LOGIN_DISPLAY_NAME"), 13, HudPalette.TEXT_DIM))
	_name = MenuStyle.line_edit(tr("HUD_PROFILE_NAME_HINT"), PlayerProfile.NAME_MAX)
	_name.text = str(session.get("display_name", ""))
	_name.text_changed.connect(func(_t: String) -> void: _refresh())
	nv.add_child(_name)
	row.add_child(nv)
	var hv := VBoxContainer.new()
	hv.add_child(MenuStyle.label(tr("HUD_ACCOUNT_FAV_HERO"), 13, HudPalette.TEXT_DIM))
	_hero = OptionButton.new()
	_hero.custom_minimum_size = Vector2(200, 36)
	_hero.add_item(tr("HUD_ACCOUNT_NO_FAV"))
	_heroes = HeroCatalog.entries()
	for h: Dictionary in _heroes:
		_hero.add_item(str(h.name))
		if h.stem == str(session.get("favourite_hero", "")):
			_hero.selected = _hero.item_count - 1
	hv.add_child(_hero)
	row.add_child(hv)
	col.add_child(row)
	_hint = MenuStyle.label("", 12, HudPalette.TEXT_DIM)
	col.add_child(_hint)

	col.add_child(MenuStyle.label(tr("HUD_PROFILE_EMBLEM"), 13, HudPalette.TEXT_DIM))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	for i in PlayerProfile.EMBLEM_COUNT:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = tr("HUD_PROFILE_EMBLEM_N") % (i + 1)
		MenuStyle.style_button(b, Color(0.03, 0.035, 0.07, 0.9))
		var icon := EmblemIcon.make(i, _accent, 34.0)
		icon.position = Vector2(5, 5)
		icon.size = Vector2(34, 34)
		b.add_child(icon)
		b.pressed.connect(func() -> void:
			_emblem = i
			_refresh())
		grid.add_child(b)
		_emblems.append(b)
	col.add_child(grid)
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 8)
	sw.add_child(MenuStyle.label(tr("HUD_PROFILE_ACCENT"), 13, HudPalette.TEXT_DIM))
	for i in PlayerProfile.ACCENTS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(34, 28)
		b.tooltip_text = tr("HUD_PROFILE_ACCENT_N") % (i + 1)
		MenuStyle.style_button(b, PlayerProfile.ACCENTS[i])
		b.pressed.connect(func() -> void:
			_accent = i
			_refresh())
		sw.add_child(b)
		_accents.append(b)
	col.add_child(sw)
	col.add_child(UiKit.button(tr("HUD_PROFILE_SAVE"), _save_profile, &"primary", 44))

	if not guest:
		var acc := UiKit.card(tr("HUD_PROFILE_ACCOUNT"), 12)
		var av := acc.body
		var pw := HBoxContainer.new()
		pw.add_theme_constant_override("separation", 6)
		_old_pw = _secret(tr("HUD_ACCOUNT_OLD_PW"))
		_new_pw = _secret(tr("HUD_ACCOUNT_NEW_PW"))
		pw.add_child(_old_pw)
		pw.add_child(_new_pw)
		pw.add_child(MenuStyle.button(tr("HUD_ACCOUNT_CHANGE_PW"), _change_password, false, 34))
		av.add_child(pw)
		var data := HBoxContainer.new()
		data.add_theme_constant_override("separation", 6)
		data.add_child(MenuStyle.button(tr("HUD_PRIVACY_EXPORT"), func() -> void: _export(""), false, 34))
		_del_pw = _secret(tr("HUD_ACCOUNT_DELETE_PW"))
		data.add_child(_del_pw)
		_delete_btn = UiKit.button(tr("HUD_ACCOUNT_DELETE"), _delete, &"danger", 34)
		data.add_child(_delete_btn)
		av.add_child(data)
		av.add_child(_recovery_row())
		col.add_child(acc)
		requested.emit.call_deferred(AccountCodec.OP_RECOVERY_INFO, {})
	else:
		var g := MenuStyle.label(tr("HUD_ACCOUNT_GUEST_INFO"), 12, HudPalette.TEXT_DIM)
		g.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(g)
	_msg = MenuStyle.label("", 13, HudPalette.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_msg)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	var logout := MenuStyle.button(tr("HUD_ACCOUNT_LOGOUT"), func() -> void: requested.emit(AccountCodec.OP_LOGOUT, {}),
		false, 38)
	logout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(logout)
	var back := UiKit.button(tr("HUD_LOGIN_BACK"), func() -> void: closed.emit(), &"ghost", 38)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(back)
	col.add_child(bottom)
	_refresh()
	_name.grab_focus.call_deferred()


## A server answer for one of this screen's requests.
func on_result(d: Dictionary) -> void:
	var ok: bool = d.code == AccountCodec.OK
	match int(d.op):
		AccountCodec.OP_UPDATE_PROFILE:
			_say(tr("HUD_ACCOUNT_SAVED") if ok else tr(LobbyClient.account_error_key(d.code)), ok)
		AccountCodec.OP_CHANGE_PASSWORD:
			_say(tr("HUD_ACCOUNT_PW_CHANGED") if ok else tr(LobbyClient.account_error_key(d.code)), ok)
		AccountCodec.OP_EXPORT:
			if ok:
				_write_export(str(d.json))
			else:
				_say(tr(LobbyClient.account_error_key(d.code)), false)
		AccountCodec.OP_RECOVERY_INFO:
			if ok:
				_set_recovery_state(int(d.has_code))
		AccountCodec.OP_RECOVERY_CODE:
			if ok:
				_set_recovery_state(1)
				_say(tr("HUD_RECOVERY_NEW_OK"), true)
			else:
				_say(tr(LobbyClient.account_error_key(d.code)), false)
		AccountCodec.OP_DELETE_ACCOUNT:
			if not ok:
				_delete_armed = false
				_delete_btn.text = tr("HUD_ACCOUNT_DELETE")
				_say(tr(LobbyClient.account_error_key(d.code)), false)


## Recovery code row: state, current password, NEW / CREATE RECOVERY CODE.
func _recovery_row() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_rec_state = MenuStyle.label(tr("HUD_RECOVERY_STATE_UNKNOWN"), 12, HudPalette.TEXT_DIM)
	_rec_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_rec_state)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	_rec_pw = _secret(tr("HUD_RECOVERY_PW"))
	h.add_child(_rec_pw)
	_rec_btn = MenuStyle.button(tr("HUD_RECOVERY_NEW"), _new_recovery_code, false, 34)
	h.add_child(_rec_btn)
	v.add_child(h)
	return v


func _set_recovery_state(state: int) -> void:
	recovery_state = state
	if _rec_state == null:
		return
	_rec_state.text = tr("HUD_RECOVERY_STATE_SET") if state == 1 else tr("HUD_RECOVERY_STATE_NONE")
	_rec_state.add_theme_color_override("font_color", HudPalette.TEXT_DIM if state == 1 else HudPalette.WARN)
	_rec_btn.text = tr("HUD_RECOVERY_NEW") if state == 1 else tr("HUD_RECOVERY_CREATE")


func _new_recovery_code() -> void:
	if _rec_pw.text == "":
		_say(tr("HUD_RECOVERY_NEEDS_PW"), false)
		return
	requested.emit(AccountCodec.OP_RECOVERY_CODE, {"password": _rec_pw.text})
	_rec_pw.text = ""


## Testing / automation: ask for a new recovery code with `password`.
func request_recovery_code(password: String) -> void:
	_rec_pw.text = password
	_new_recovery_code()


## Asks the server for the export; `path` "" = let the player pick a file.
func _export(path: String) -> void:
	if path == "":
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.current_file = "cybergram_account.json"
		_dialog.filters = PackedStringArray(["*.json"])
		_dialog.file_selected.connect(func(p: String) -> void: _export(p))
		add_child(_dialog)
		_dialog.popup_centered(Vector2i(760, 480))
		return
	_pending_export = path
	requested.emit(AccountCodec.OP_EXPORT, {})


## Testing / automation: export straight to `path` (no dialog).
func export_to(path: String) -> void:
	_export(path)


func _write_export(json: String) -> void:
	if _pending_export == "":
		return
	var f := FileAccess.open(_pending_export, FileAccess.WRITE)
	if f == null:
		_say(tr("HUD_PRIVACY_EXPORT_FAILED"), false)
		return
	f.store_string(json)
	f.close()
	export_path = _pending_export
	_say(tr("HUD_PRIVACY_EXPORTED") % ProjectSettings.globalize_path(_pending_export), true)
	_pending_export = ""


func _save_profile() -> void:
	var n := _name.text.strip_edges()
	if PlayerProfile.validate_name(n) != PlayerProfile.NameError.OK or not PlayerProfile.name_allowed(n):
		_say(tr("HUD_ACCOUNT_ERR_8"), false)
		return
	var fav: String = "" if _hero.selected <= 0 else str(_heroes[_hero.selected - 1].stem)
	requested.emit(AccountCodec.OP_UPDATE_PROFILE, {"display_name": n, "emblem": _emblem, "accent": _accent,
		"favourite_hero": fav})


func _change_password() -> void:
	if _old_pw.text == "" or _new_pw.text == "":
		_say(tr("HUD_LOGIN_ERR_EMPTY"), false)
		return
	requested.emit(AccountCodec.OP_CHANGE_PASSWORD, {"old_password": _old_pw.text, "new_password": _new_pw.text})
	_old_pw.text = ""
	_new_pw.text = ""


## Two presses with the password typed: the first arms, the second sends.
func _delete() -> void:
	if _del_pw.text == "":
		_say(tr("HUD_ACCOUNT_DELETE_NEEDS_PW"), false)
		return
	if not _delete_armed:
		_delete_armed = true
		_delete_btn.text = tr("HUD_PRIVACY_DELETE_CONFIRM")
		return
	requested.emit(AccountCodec.OP_DELETE_ACCOUNT, {"password": _del_pw.text})
	_del_pw.text = ""


func _refresh() -> void:
	var n := _name.text.strip_edges()
	var err := PlayerProfile.validate_name(n)
	var ok := err == PlayerProfile.NameError.OK and PlayerProfile.name_allowed(n)
	_hint.text = name_error_text(err) if err != PlayerProfile.NameError.OK or ok else tr("HUD_PROFILE_ERR_BLOCKED")
	_hint.add_theme_color_override("font_color", HudPalette.HEAL if ok else HudPalette.WARN)
	for i in _emblems.size():
		_emblems[i].set_pressed_no_signal(i == _emblem)
		(_emblems[i].get_child(0) as EmblemIcon).accent = _accent
	for i in _accents.size():
		_accents[i].set_pressed_no_signal(i == _accent)


func _say(text: String, ok: bool) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", HudPalette.HEAL if ok else HudPalette.WARN)


func _secret(placeholder: String) -> LineEdit:
	var e := MenuStyle.line_edit(placeholder, AccountCodec.PASSWORD_MAX_BYTES)  # never cut a password (W21-N1)
	e.secret = true
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


## Player-facing text key for a name validation result.
static func name_error_key(e: PlayerProfile.NameError) -> String:
	match e:
		PlayerProfile.NameError.TOO_SHORT:
			return "HUD_PROFILE_ERR_SHORT"
		PlayerProfile.NameError.TOO_LONG:
			return "HUD_PROFILE_ERR_LONG"
		PlayerProfile.NameError.BAD_CHAR:
			return "HUD_PROFILE_ERR_CHAR"
		PlayerProfile.NameError.BAD_SPACE:
			return "HUD_PROFILE_ERR_SPACE"
	return "HUD_PROFILE_NAME_OK"


## Localised message for a validation result.
static func name_error_text(e: PlayerProfile.NameError) -> String:
	var t := TranslationServer.translate(name_error_key(e))
	if e == PlayerProfile.NameError.TOO_SHORT:
		return t % PlayerProfile.NAME_MIN
	if e == PlayerProfile.NameError.TOO_LONG:
		return t % PlayerProfile.NAME_MAX
	return t
