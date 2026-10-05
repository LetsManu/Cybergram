class_name UiCard
extends PanelContainer
## Kit card (design/ux/ui-kit.md §4): a layered dark panel with an optional
## header strip (raised band, brass tick, Orbitron heading, a right-hand slot
## for actions). Put content in `body`.
##
## Example:
##   var c := UiKit.card(tr("HUD_NEWS_TITLE"))
##   c.body.add_child(UiKit.label(tr("HUD_NEWS_1"), &"body"))
##   c.header_right.add_child(UiKit.icon_button(&"close", close))

## Content column.
var body: VBoxContainer
## Header row (null when the card has no title).
var header: PanelContainer
var title_label: Label
## Right-aligned slot in the header (buttons, counters).
var header_right: HBoxContainer


## `title` "" = no header strip. `pad` = body padding.
func setup(title: String, pad: int) -> UiCard:
	var t := UiKit.tokens()
	add_theme_stylebox_override("panel", UiKit.panel_box(t.panel, 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	if title != "":
		header = PanelContainer.new()
		var hb := StyleBoxFlat.new()
		hb.bg_color = t.panel_raised
		hb.border_color = t.line
		hb.border_width_bottom = 1
		hb.content_margin_left = t.space_m
		hb.content_margin_right = t.space_s
		hb.content_margin_top = 4
		hb.content_margin_bottom = 4
		header.add_theme_stylebox_override("panel", hb)
		header.custom_minimum_size.y = t.header_height
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", t.space_s)
		header.add_child(row)
		var tick := ColorRect.new()
		tick.color = t.gold
		tick.custom_minimum_size = Vector2(3, 16)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tick)
		title_label = UiKit.label(title, &"heading")
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_label.clip_text = true
		row.add_child(title_label)
		header_right = HBoxContainer.new()
		header_right.add_theme_constant_override("separation", 4)
		row.add_child(header_right)
		col.add_child(header)
	var m := MarginContainer.new()
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, pad)
	col.add_child(m)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", t.space_s)
	m.add_child(body)
	return self
