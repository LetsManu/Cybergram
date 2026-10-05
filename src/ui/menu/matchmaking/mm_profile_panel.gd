class_name MmProfilePanel
extends PanelContainer
## W17B-UI: the matchmaking part of the profile (design "Rating and ranks"):
## ranked medal + visible rating with the division progress, or the
## calibration progress ("Calibrating 3/10" + pips); Normal and 3v3 show
## that their rating is hidden (games played when known); a minimal recent
## match history (queue, hero, result, K/D/A, ranked rating change).
## Fed by client.request_profile() -> profile_received.

var client: Object
var profile: Dictionary = {}

var _ranked_line: Label
var _ranked_sub: Label
var _progress: ProgressBar
var _pips: HBoxContainer
var _others: VBoxContainer
var _history: VBoxContainer
var _empty: Label


func _ready() -> void:
	HudStrings.ensure_loaded()
	theme = UiKit.theme()
	custom_minimum_size = Vector2(420, 0)
	_build()
	_apply()
	if client != null:
		if client.has_signal("profile_received"):
			client.connect("profile_received", set_profile)
		client.call("request_profile")


func set_profile(p: Dictionary) -> void:
	profile = p
	_apply()


func _build() -> void:
	var t := UiKit.tokens()
	var col := UiKit.screen_frame(self, tr("HUD_MM_PROFILE_TITLE"), "", 20)
	col.add_theme_constant_override("separation", 10)
	col.add_child(MmKit.caption(tr("HUD_MM_Q_RANKED")))
	_ranked_line = UiKit.label("", &"title", t.accent_hi)
	_ranked_line.name = "RankedLine"
	col.add_child(_ranked_line)
	_ranked_sub = UiKit.label("", &"small", t.text_dim)
	col.add_child(_ranked_sub)
	_progress = MmKit.progress(t.accent, 4)
	col.add_child(_progress)
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 5)
	col.add_child(_pips)
	col.add_child(UiKit.hairline())
	_others = VBoxContainer.new()
	_others.add_theme_constant_override("separation", 4)
	col.add_child(_others)
	col.add_child(UiKit.hairline())
	col.add_child(MmKit.caption(tr("HUD_MM_HISTORY")))
	_history = VBoxContainer.new()
	_history.add_theme_constant_override("separation", 4)
	col.add_child(_history)
	_empty = UiKit.label(tr("HUD_MM_HISTORY_EMPTY"), &"small", t.text_off)
	col.add_child(_empty)


func _apply() -> void:
	if _ranked_line == null:
		return
	var t := UiKit.tokens()
	var n := int(profile.get("calibration_games", 10))
	var tracks: Dictionary = profile.get("tracks", {})
	var ranked: Dictionary = tracks.get(&"ranked", {})
	_ranked_line.text = MmView.ranked_line(ranked, n)
	var cal := bool(ranked.get("calibrating", true))
	_progress.visible = not ranked.is_empty() and not cal
	_progress.value = float(ranked.get("progress", 0.0))
	_ranked_sub.text = tr("HUD_MM_CALIBRATING_HINT") % n if cal else tr("HUD_MM_DIVISION_PROGRESS")
	for c in _pips.get_children():
		_pips.remove_child(c)
		c.queue_free()
	_pips.visible = cal
	var played := n - int(ranked.get("games_left", n))
	for i in n:
		var p := ColorRect.new()
		p.custom_minimum_size = Vector2(22, 6)
		p.color = t.accent if i < played else t.line_strong
		_pips.add_child(p)
	for c in _others.get_children():
		_others.remove_child(c)
		c.queue_free()
	for q: Array in [[&"normal", "HUD_MM_Q_NORMAL"], [&"all_random", "HUD_MM_Q_ARAM"]]:
		var row := HBoxContainer.new()
		var a := UiKit.label(tr(q[1]), &"body", t.text)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(a)
		var tr_d: Dictionary = tracks.get(q[0], {})
		var txt := tr("HUD_MM_HIDDEN_RATING")
		if tr_d.has("games"):
			txt = tr("HUD_MM_GAMES_HIDDEN") % int(tr_d.games)
		row.add_child(UiKit.label(txt, &"small", t.text_dim, HORIZONTAL_ALIGNMENT_RIGHT))
		_others.add_child(row)
	for c in _history.get_children():
		_history.remove_child(c)
		c.queue_free()
	var hist: Array = profile.get("history", [])
	_empty.visible = hist.is_empty()
	for h: Dictionary in hist.slice(0, 5):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var won := bool(h.get("won", false))
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(3, 30)
		bar.color = t.ok if won else t.danger
		row.add_child(bar)
		var badge := HeroBadge.make(MmView.hero_index(StringName(h.get("hero", &""))), 30.0, t.line_strong)
		row.add_child(badge)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UiKit.label(tr("HUD_MM_POST_VICTORY") if won else tr("HUD_MM_POST_DEFEAT"), &"small",
			t.text if won else t.text_dim))
		v.add_child(UiKit.label(tr(MmView.queue_key(StringName(h.get("queue", &"")))), &"caption", t.text_off))
		row.add_child(v)
		var kda := MmKit.mono("%d/%d/%d" % [int(h.get("kills", 0)), int(h.get("deaths", 0)), int(h.get("assists", 0))], 13, t.text_dim)
		kda.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(kda)
		var d := int(h.get("delta", 0))
		var dl := MmKit.mono(("+%d" % d if d > 0 else str(d)) if StringName(h.get("queue", &"")) == MmView.Q_RANKED else "", 13,
			t.ok if d > 0 else t.danger)
		dl.custom_minimum_size.x = 40
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dl)
		_history.add_child(row)
