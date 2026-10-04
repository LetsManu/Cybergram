class_name ProfileScreen
extends PanelContainer
## Player profile creation / editing (design/ux/lobby-and-social.md §2.1):
## name with live validation, emblem grid, accent swatches and a preview of
## the Riot-ID style "Name#TAG". On first launch there is no Cancel. Saving
## writes `path` and emits `saved`; the id and key of an existing profile are
## kept (only a new profile gets fresh ones).
## Privacy (GDPR, PRIVACY.md): a short notice says what goes to the server and
## why; the checkbox (acknowledgement) is needed for online play only and can
## be withdrawn here. Existing profiles also get "Export my data" and
## "Delete my profile & data".
##
## Example:
##   var ps := ProfileScreen.new()
##   ps.profile = PlayerProfile.load_or_null(path)   # null = first launch
##   ps.path = path
##   ps.saved.connect(_on_profile_saved)

signal saved(profile: PlayerProfile)
signal cancelled
## Every local data file was deleted ("Delete my profile & data").
signal deleted

## The full privacy notice (repository root, also shipped next to the game).
const PRIVACY_URL := "https://github.com/LetsManu/Cybergram/blob/main/PRIVACY.md"

## The profile being edited (null = create a new one).
var profile: PlayerProfile
var path: String = PlayerProfile.DEFAULT_PATH
## Local data files (export / delete).
var files: LocalData.Files = LocalData.Files.defaults()
## Opened from PLAY ONLINE without an acknowledgement: highlight the notice.
var online_required: bool = false

var _name: LineEdit
var _hint: Label
var _preview_emblem: EmblemIcon
var _preview_name: Label
var _save: Button
var _emblems: Array[Button] = []
var _accents: Array[Button] = []
var _emblem: int = 0
var _accent: int = 0
## Tag shown in the preview (a new profile's tag is known only after saving).
var _tag: String = ""
var _first: bool = false
var _ack: CheckBox
var _notice_panel: PanelContainer
var _data_hint: Label
var _delete_armed: bool = false
var _delete_btn: Button


func _ready() -> void:
	HudStrings.ensure_loaded()
	_first = profile == null
	if _first:
		_emblem = randi() % PlayerProfile.EMBLEM_COUNT
		_accent = randi() % PlayerProfile.ACCENTS.size()
		_tag = "????"
	else:
		_emblem = profile.emblem
		_accent = profile.accent
		_tag = profile.tag()
	add_theme_stylebox_override("panel", MenuStyle.panel(HudPalette.PANEL_STRONG, 18))
	custom_minimum_size = Vector2(640, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	add_child(col)
	col.add_child(MenuStyle.label(tr("HUD_PROFILE_CREATE" if _first else "HUD_PROFILE_TITLE"), 28,
		HudPalette.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if _first:
		var intro := MenuStyle.label(tr("HUD_PROFILE_INTRO"), 14, HudPalette.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(intro)

	# Preview: big emblem + Name#TAG.
	var prev := HBoxContainer.new()
	prev.alignment = BoxContainer.ALIGNMENT_CENTER
	prev.add_theme_constant_override("separation", 14)
	_preview_emblem = EmblemIcon.make(_emblem, _accent, 60.0)
	prev.add_child(_preview_emblem)
	_preview_name = MenuStyle.label("", 26, HudPalette.TEXT)
	prev.add_child(_preview_name)
	col.add_child(prev)

	col.add_child(MenuStyle.label(tr("HUD_PROFILE_NAME"), 14, HudPalette.TEXT_DIM))
	_name = MenuStyle.line_edit(tr("HUD_PROFILE_NAME_HINT"), PlayerProfile.NAME_MAX)
	_name.text = profile.name if profile != null else ""
	_name.text_changed.connect(func(_t: String) -> void: _refresh())
	_name.text_submitted.connect(func(_t: String) -> void: _on_save())
	col.add_child(_name)
	_hint = MenuStyle.label("", 13, HudPalette.TEXT_DIM)
	col.add_child(_hint)

	col.add_child(MenuStyle.label(tr("HUD_PROFILE_EMBLEM"), 14, HudPalette.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = PlayerProfile.EMBLEM_COUNT
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
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

	col.add_child(MenuStyle.label(tr("HUD_PROFILE_ACCENT"), 14, HudPalette.TEXT_DIM))
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 8)
	for i in PlayerProfile.ACCENTS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(40, 32)
		b.tooltip_text = tr("HUD_PROFILE_ACCENT_N") % (i + 1)
		MenuStyle.style_button(b, PlayerProfile.ACCENTS[i])
		b.pressed.connect(func() -> void:
			_accent = i
			_refresh())
		sw.add_child(b)
		_accents.append(b)
	col.add_child(sw)

	# Privacy notice (what is sent, why, how long) + acknowledgement.
	_notice_panel = MenuStyle.panel_container(Color(0.02, 0.025, 0.05, 0.9), 10)
	if online_required:
		(_notice_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = HudPalette.LUMEN
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 6)
	_notice_panel.add_child(nv)
	nv.add_child(MenuStyle.label(tr("HUD_PRIVACY_TITLE"), 14, HudPalette.TEXT))
	var body := MenuStyle.label(tr("HUD_PRIVACY_BODY"), 12, HudPalette.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(body)
	var prow := HBoxContainer.new()
	_ack = CheckBox.new()
	_ack.text = tr("HUD_PRIVACY_ACK")
	_ack.add_theme_font_size_override("font_size", 12)
	_ack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ack.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ack.button_pressed = profile != null and profile.can_play_online()
	prow.add_child(_ack)
	var read := MenuStyle.button(tr("HUD_PRIVACY_READ"), func() -> void: OS.shell_open(PRIVACY_URL), false, 30)
	read.add_theme_font_size_override("font_size", 12)
	read.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(read)
	nv.add_child(prow)
	col.add_child(_notice_panel)

	if not _first:
		var drow := HBoxContainer.new()
		drow.add_theme_constant_override("separation", 10)
		var export := MenuStyle.button(tr("HUD_PRIVACY_EXPORT"), _on_export, false, 34)
		export.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drow.add_child(export)
		_delete_btn = MenuStyle.button(tr("HUD_PRIVACY_DELETE"), _on_delete, false, 34)
		_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_delete_btn.add_theme_color_override("font_color", HudPalette.DANGER)
		drow.add_child(_delete_btn)
		col.add_child(drow)
		_data_hint = MenuStyle.label("", 12, HudPalette.TEXT_DIM)
		_data_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(_data_hint)

	col.add_child(MenuStyle.spacer(6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if not _first:
		var cancel := MenuStyle.button(tr("HUD_PROFILE_CANCEL"), func() -> void: cancelled.emit())
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cancel)
	_save = MenuStyle.button(tr("HUD_PROFILE_SAVE") if not _first else tr("HUD_PROFILE_CONTINUE"), _on_save, true)
	_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_save)
	col.add_child(row)
	_refresh()
	_name.grab_focus.call_deferred()


## Player-facing text for a name validation result.
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


## Testing / automation: tick or untick the privacy acknowledgement.
func set_acknowledged(on: bool) -> void:
	_ack.button_pressed = on


func _on_export() -> void:
	var out := LocalData.export_json(files)
	_data_hint.text = tr("HUD_PRIVACY_EXPORTED") % out if out != "" else tr("HUD_PRIVACY_EXPORT_FAILED")


## Two presses: the first arms, the second deletes.
func _on_delete() -> void:
	if not _delete_armed:
		_delete_armed = true
		_delete_btn.text = tr("HUD_PRIVACY_DELETE_CONFIRM")
		return
	var n := LocalData.delete_all(files)
	print("[profile] local data deleted (%d files)" % n)
	profile = null
	deleted.emit()


## Testing / automation: set the fields as a player would.
func set_fields(name_: String, emblem_: int, accent_: int) -> void:
	_name.text = name_
	_emblem = clampi(emblem_, 0, PlayerProfile.EMBLEM_COUNT - 1)
	_accent = clampi(accent_, 0, PlayerProfile.ACCENTS.size() - 1)
	_refresh()


func _refresh() -> void:
	var n := _name.text
	var err := PlayerProfile.validate_name(n)
	var ok := err == PlayerProfile.NameError.OK and PlayerProfile.name_allowed(n)
	_hint.text = name_error_text(err) if err != PlayerProfile.NameError.OK or ok else tr("HUD_PROFILE_ERR_BLOCKED")
	_hint.add_theme_color_override("font_color", HudPalette.HEAL if ok else (HudPalette.TEXT_DIM if n == "" else HudPalette.WARN))
	_save.disabled = not ok
	_preview_emblem.emblem = _emblem
	_preview_emblem.accent = _accent
	_preview_name.text = "%s#%s" % [n if n != "" else tr("HUD_PROFILE_NAME"), _tag]
	_preview_name.add_theme_color_override("font_color", PlayerProfile.accent_of(_accent).lerp(HudPalette.TEXT, 0.35))
	for i in _emblems.size():
		_emblems[i].set_pressed_no_signal(i == _emblem)
		(_emblems[i].get_child(0) as EmblemIcon).accent = _accent
	for i in _accents.size():
		_accents[i].set_pressed_no_signal(i == _accent)


func _on_save() -> void:
	if PlayerProfile.validate_name(_name.text) != PlayerProfile.NameError.OK or not PlayerProfile.name_allowed(_name.text):
		return
	var p := profile
	if p == null:
		p = PlayerProfile.create(_name.text, _emblem, _accent)
	else:
		p.name = _name.text.strip_edges()
		p.emblem = _emblem
		p.accent = _accent
	p.privacy_ack = PlayerProfile.PRIVACY_VERSION if _ack.button_pressed else 0
	var err := p.save(path)
	if err != OK:
		_hint.text = tr("HUD_PROFILE_ERR_SAVE") % error_string(err)
		_hint.add_theme_color_override("font_color", HudPalette.DANGER)
		return
	profile = p
	saved.emit(p)
