extends SceneTree
## Writes the Armory balance report (tools/balance/armory_sim.gd; docs/armory.md
## "Balance check").
##
## Run: $GODOT --headless --path . -s res://tools/balance/armory_report.gd [-- [--v22] --out docs/balance/armory-report.md]

const ArmorySim := preload("res://tools/balance/armory_sim.gd")
const ArmorySimV2 := preload("res://tools/balance/armory_sim_v2.gd")


func _init() -> void:
	var out_path := ""
	var args := OS.get_cmdline_user_args()
	var k := args.find("--out")
	if k >= 0 and k + 1 < args.size():
		out_path = args[k + 1]
	# --v22: the Armory v2 recipe catalog and guides (armory_sim_v2.gd).
	var text: String = ArmorySimV2.new().report() if args.has("--v22") else ArmorySim.new().report()
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
