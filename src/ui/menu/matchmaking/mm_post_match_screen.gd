class_name MmPostMatchScreen
extends Control
## W17B-UI: post-match summary (design "Rating and ranks", "Reports and
## honour after the game").
## - Result title: VICTORY / DEFEAT / REMAKE (voided: no rating change).
## - Your stats (K / D / A plus damage, healing, objectives when the server
##   sends them).
## - Rating: ranked only, the change as a number (+18 / -16) with the medal
##   before -> after and the division progress; calibration shows "x/N".
##   Normal, 3v3 and custom hide it (hidden MMR).
## - Both teams: every human player but you has HONOUR (positive only, once
##   per player) and REPORT (categories only, no free text). Bots have none.
## Display only: client.honour / client.report.

signal closed()

var client: Object
var rules: MatchmakingRulesDef
var result: Dictionary = {}
## player id -> true once honoured / reported (this screen).
var honoured: Dictionary = {}
var reported: Dictionary = {}

var _title: Label
var _sub: Label
var _stats: GridContainer
var _rating_box: VBoxContainer
var _delta: Label
var _medal: Label
var _progress: ProgressBar
var _teams: Array[VBoxContainer] = []
var _continue: Button


func _ready() -> void:
	HudStrings.ensure_loaded()
	if rules == null:
		rules = MatchmakingRulesDef.load_default()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	_build()
	_apply()
	_continue.grab_focus.call_deferred()


func set_result(r: Dictionary) -> void:
	result = r
	_apply()


## What the rating panel shows (MmView.rating_change).
func rating_view() -> Dictionary:
	return MmView.rating_change(StringName(result.get("queue", &"")), result.get("rating", {}),
		bool(result.get("voided", false)))


func honour(id: String) -> void:
	if honoured.has(id):
		return
	honoured[id] = true
	if client != null:
		client.call("honour", result.get("match_id", ""), id)
	_apply()


## Opens the category picker for player `id`.
func open_report(id: String, name_: String) -> void:
	if reported.has(id):
		return
	var t := UiKit.tokens()
	var m := UiKit.modal(self, tr("HUD_MM_REPORT_TITLE") % name_, tr("HUD_MM_REPORT_BODY"), tr("HUD_MM_CANCEL"),
		Callable(), "", Callable())
	m.name = "ReportDialog"
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	var first: Button = null
	for cat: StringName in rules.report_categories:
		var c := cat
		var b := UiKit.button(tr(MmView.REPORT_KEYS.get(cat, "HUD_MM_REPORT_GRIEFING")), func() -> void:
			report(id, c)
			m.close(false), &"secondary", 38)
		b.name = "Cat_" + String(cat)
		list.add_child(b)
		if first == null:
			first = b
	m.card.body.add_child(list)
	m.card.body.move_child(list, 1)
	m.ok_button.add_theme_color_override("font_color", t.text_dim)
	if first != null:
		first.grab_focus.call_deferred()


func report(id: String, category: StringName) -> void:
	if reported.has(id) or not rules.report_categories.has(category):
		return
	reported[id] = true
	if client != null:
		client.call("report", result.get("match_id", ""), id, category)
	_apply()


func _build() -> void:
	var t := UiKit.tokens()
	var bg := UiKit.background()
	UiKit.set_background_layout(bg, 360.0, Vector2(360, 260), 300.0, true)
	add_child(bg)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	add_child(MmKit.place(left, Vector2(64, 56), 440))
	_sub = MmKit.caption("", 12, t.accent)
	left.add_child(_sub)
	_title = MmKit.title("", 64)
	left.add_child(_title)
	left.add_child(UiKit.hairline(true))
	left.add_child(MmKit.caption(tr("HUD_MM_POST_YOUR_STATS")))
	_stats = GridContainer.new()
	_stats.columns = 3
	_stats.add_theme_constant_override("h_separation", 28)
	_stats.add_theme_constant_override("v_separation", 12)
	left.add_child(_stats)
	left.add_child(UiKit.spacer(8))
	_rating_box = VBoxContainer.new()
	_rating_box.name = "Rating"
	_rating_box.add_theme_constant_override("separation", 6)
	left.add_child(_rating_box)
	_rating_box.add_child(MmKit.caption(tr("HUD_MM_POST_RATING")))
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 18)
	_rating_box.add_child(rr)
	_delta = MmKit.mono("", 44)
	rr.add_child(_delta)
	_medal = UiKit.label("", &"heading", t.text)
	_medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.add_child(_medal)
	_progress = MmKit.progress(t.accent, 4)
	_progress.custom_minimum_size.x = 420
	_rating_box.add_child(_progress)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	add_child(MmKit.place(right, Vector2(600, 56), 780))
	for i in 2:
		var head := MmKit.caption(tr("HUD_MM_YOUR_TEAM") if i == 0 else tr("HUD_MM_ENEMY_TEAM"), 11,
			t.accent if i == 0 else t.danger)
		right.add_child(head)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 4)
		right.add_child(rows)
		_teams.append(rows)
	_continue = UiKit.button(tr("HUD_MM_CONTINUE"), func() -> void: closed.emit(), &"play", 52)
	_continue.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_continue.offset_left = -300
	_continue.offset_right = -60
	_continue.offset_top = -100
	_continue.offset_bottom = -48
	_continue.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_continue.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_continue)


func _apply() -> void:
	if _title == null:
		return
	var t := UiKit.tokens()
	var voided := bool(result.get("voided", false))
	var won := bool(result.get("won", false))
	_title.text = (tr("HUD_MM_POST_REMAKE") if voided else (tr("HUD_MM_POST_VICTORY") if won else tr("HUD_MM_POST_DEFEAT"))).to_upper()
	_title.add_theme_color_override("font_color", t.text_dim if voided else (t.accent_hi if won else t.danger))
	_sub.text = "%s  ·  %s" % [tr(MmView.queue_key(StringName(result.get("queue", &"")))),
		MmView.clock(float(result.get("duration_s", 0)))]
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var st: Dictionary = result.get("stats", {})
	for k: Array in [["kills", "HUD_MM_STAT_KILLS"], ["deaths", "HUD_MM_STAT_DEATHS"], ["assists", "HUD_MM_STAT_ASSISTS"],
			["damage", "HUD_MM_STAT_DAMAGE"], ["healing", "HUD_MM_STAT_HEALING"], ["objective", "HUD_MM_STAT_OBJECTIVES"]]:
		if not st.has(k[0]):
			continue
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(MmKit.mono(str(int(st[k[0]])), 24, t.text))
		cell.add_child(MmKit.caption(tr(k[1]), 10))
		_stats.add_child(cell)
	var rv := rating_view()
	_rating_box.visible = bool(rv.visible)
	if rv.visible:
		var r: Dictionary = result.get("rating", {})
		_delta.text = str(rv.text)
		_delta.add_theme_color_override("font_color", t.ok if int(rv.delta) > 0 else (t.danger if int(rv.delta) < 0 else t.text_dim))
		var mb: Dictionary = r.get("medal_before", {})
		var ma: Dictionary = r.get("medal_after", {})
		if ma.is_empty():
			_medal.text = ""
		elif str(mb.get("label", "")) != str(ma.get("label", "")) and not mb.is_empty():
			_medal.text = "%s  →  %s  ·  %d" % [str(mb.label), str(ma.label), int(r.get("after", 0))]
		else:
			_medal.text = "%s  ·  %d" % [str(ma.label), int(r.get("after", 0))]
		_progress.visible = not ma.is_empty()
		_progress.value = float(r.get("progress", 0.0))
	for i in 2:
		for c in _teams[i].get_children():
			_teams[i].remove_child(c)
			c.queue_free()
	var my_team := 0
	for p: Dictionary in result.get("players", []):
		if bool(p.get("me", false)):
			my_team = int(p.team)
	for p: Dictionary in result.get("players", []):
		_teams[0 if int(p.team) == my_team else 1].add_child(_player_row(p))


func _player_row(p: Dictionary) -> Control:
	var t := UiKit.tokens()
	var me := bool(p.get("me", false))
	var bot := bool(p.get("bot", false))
	var id := str(p.get("id", ""))
	var panel := PanelContainer.new()
	panel.name = "Player_" + (id if id != "" else str(p.get("name", "")))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(t.accent, 0.08) if me else Color(t.panel_raised, 0.55)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var badge := HeroBadge.make(MmView.hero_index(StringName(p.get("hero", &""))), 34.0, t.line_strong)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var name_txt := str(p.get("name", ""))
	if bot:
		name_txt = "%s  (%s)" % [name_txt, tr("HUD_MM_BOT_TAG")]
	var nm := UiKit.label(name_txt, &"body", t.text if not bot else t.text_dim)
	nm.custom_minimum_size.x = 200
	nm.clip_text = true
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nm)
	var hero := UiKit.label(MmView.hero_name(StringName(p.get("hero", &""))), &"small", t.text_dim)
	hero.custom_minimum_size.x = 130
	hero.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hero)
	var kda := MmKit.mono("%d / %d / %d" % [int(p.get("kills", 0)), int(p.get("deaths", 0)), int(p.get("assists", 0))], 15, t.text)
	kda.custom_minimum_size.x = 110
	kda.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(kda)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	if me or bot or id == "":
		return panel
	var hon := UiKit.button(tr("HUD_MM_HONOURED") if honoured.has(id) else tr("HUD_MM_HONOUR"), func() -> void: honour(id),
		&"ghost", 30)
	hon.name = "Honour"
	hon.disabled = honoured.has(id)
	row.add_child(hon)
	var nm_s := str(p.get("name", ""))
	var rep := UiKit.button(tr("HUD_MM_REPORTED") if reported.has(id) else tr("HUD_MM_REPORT"),
		func() -> void: open_report(id, nm_s), &"ghost", 30)
	rep.name = "Report"
	rep.disabled = reported.has(id)
	row.add_child(rep)
	return panel
