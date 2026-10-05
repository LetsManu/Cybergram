class_name SettingsTheme
extends RefCounted
## Compatibility shim: the settings look is the UI kit's theme
## (src/ui/theme/ui_kit.gd). New code calls UiKit directly.

## Selection / focus accent (legacy constant; the kit token is UiKit.tokens().accent).
const ACCENT := Color("#8E5CFF")


## The shared kit theme.
static func build() -> Theme:
	return UiKit.theme()


## Tab content frame style.
static func frame() -> StyleBoxFlat:
	var t := UiKit.tokens()
	return UiKit.panel_box(t.panel, 16)
