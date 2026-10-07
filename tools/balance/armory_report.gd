extends SceneTree
## Writes the Armory balance report (tools/balance/armory_sim.gd; docs/armory.md
## "Balance check").
##
## Run: $GODOT --headless --path . -s res://tools/balance/armory_report.gd [-- [--quick] [--out docs/balance/armory-v2-report.md]]
## (`--v22` is accepted and ignored: the v2 catalog is the only one.)

const ArmorySim := preload("res://tools/balance/armory_sim.gd")
const DEFAULT_OUT := "docs/balance/armory-v2-report.md"


func _init() -> void:
	var out_path := DEFAULT_OUT
	var args := OS.get_cmdline_user_args()
	var k := args.find("--out")
	if k >= 0 and k + 1 < args.size():
		out_path = args[k + 1]
	var quick := args.has("--quick")  # average curve, pad only; written nowhere unless --out is given
	var text: String = ArmorySim.new().report(quick)
	print(text)
	if quick and k < 0:
		quit()
		return
	var abs := out_path if out_path.begins_with("res://") or out_path.is_absolute_path() else "res://" + out_path
	var fa := FileAccess.open(abs, FileAccess.WRITE)
	if fa != null:
		fa.store_string(text)
		fa.close()
		print("[armory_report] wrote %s" % abs)
	else:
		push_error("[armory_report] cannot write %s" % abs)
	quit()
