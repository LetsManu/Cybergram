extends SceneTree
## Writes the Armory balance report (tools/balance/armory_sim.gd; docs/armory.md
## "Balance check").
##
## Run: $GODOT --headless --path . -s res://tools/balance/armory_report.gd [-- --out docs/balance/armory-report.md]

const ArmorySim := preload("res://tools/balance/armory_sim.gd")


func _init() -> void:
	var out_path := ""
	var args := OS.get_cmdline_user_args()
	var k := args.find("--out")
	if k >= 0 and k + 1 < args.size():
		out_path = args[k + 1]
	var text: String = ArmorySim.new().report()
	print(text)
	if out_path != "":
		var abs := out_path if out_path.begins_with("res://") or out_path.is_absolute_path() else "res://" + out_path
		var fa := FileAccess.open(abs, FileAccess.WRITE)
		if fa != null:
			fa.store_string(text)
			fa.close()
			print("[armory_report] wrote %s" % abs)
		else:
			push_error("[armory_report] cannot write %s" % abs)
	quit()
