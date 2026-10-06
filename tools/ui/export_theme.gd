extends SceneTree
## P4: writes the UI kit Theme (UiKit.build_theme(), built from
## assets/ui/ui_kit_tokens.tres) to assets/ui/ui_kit_theme.tres so designers
## can open it in the Godot theme editor and controls can preview it. The code
## stays the source of truth: change tokens or UiKit, then re-run this.
## Usage: godot --headless --path . -s res://tools/ui/export_theme.gd

const OUT := "res://assets/ui/ui_kit_theme.tres"


func _init() -> void:
	var th := UiKit.build_theme()
	var err := ResourceSaver.save(th, OUT)
	print("export_theme: %s -> %s" % [OUT, error_string(err)])
	quit(0 if err == OK else 1)
