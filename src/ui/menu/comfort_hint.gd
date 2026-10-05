class_name ComfortHint
extends HBoxContainer
## First-launch hint (W16-COMFORT): one dismissible line pointing to Settings >
## Comfort. Shown once: GameSettings.comfort_hint_seen is saved when it is
## dismissed or opened (same first-run flag pattern as tutorial_done).

signal open_requested

var _s: GameSettings


## Builds the hint; returns false (and frees nothing) when it was already shown.
static func should_show(s: GameSettings) -> bool:
	return not s.comfort_hint_seen


func _ready() -> void:
	_s = GameSettings.shared()
	visible = should_show(_s)
	var open := UiKit.button(tr("HUD_COMFORT_HINT"), func() -> void:
		_dismiss()
		open_requested.emit(), &"secondary", 36)
	add_child(open)
	var x := UiKit.button("×", _dismiss, &"secondary", 36)
	x.tooltip_text = tr("HUD_COMFORT_HINT_DISMISS")
	add_child(x)
	add_theme_constant_override("separation", 6)


func _dismiss() -> void:
	_s.comfort_hint_seen = true
	_s.save()
	visible = false
