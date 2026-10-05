class_name CareerLayout
extends ScrollContainer
## W21-U2: lays out the CAREER page (the account PROFILE card and the
## matchmaking RANKS panel) so nothing overlaps or is clipped at any window
## size: side by side while they fit, stacked when the window is narrow, and
## a vertical scrollbar when the page is taller than the window. Panels keep
## their own minimum sizes; this container only arranges them.
##
## Example:
##   var page := CareerLayout.new()
##   page.add_panel(profile_screen)
##   page.add_panel(ranks_panel)
##   content.add_child(page)

## Gap between the panels and the page edge, in menu pixels.
@export var gap: int = 24

var _flow: HFlowContainer


func _init() -> void:
	name = "CareerLayout"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, gap)
	add_child(margin)
	_flow = HFlowContainer.new()
	_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.add_theme_constant_override("h_separation", gap)
	_flow.add_theme_constant_override("v_separation", gap)
	margin.add_child(_flow)


## Adds a panel to the page (in order: first = left / top).
func add_panel(panel: Control) -> void:
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_flow.add_child(panel)


## True when the panels are stacked (the wrapped layout): more than one row.
func is_stacked() -> bool:
	if _flow.get_child_count() < 2:
		return false
	return (_flow.get_child(1) as Control).position.y > (_flow.get_child(0) as Control).position.y
