extends SceneTree
## Owner tool: review post-match reports (W17-MM, PRIVACY.md "Reports and
## honour"). Run through review_reports.sh, or directly:
##   godot --headless --path . --script res://tools/server/review_reports.gd -- list
## Reports folder: --dir <dir>, else env CYBERGRAM_REPORTS_DIR, else
## "reports" next to CYBERGRAM_DATA_DIR (Docker: /data/reports), else
## user://reports. Commands: see ReportReview.USAGE.


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var dir := ""
	var i := args.find("--dir")
	if i >= 0 and i + 1 < args.size():
		dir = String(args[i + 1])
		args.remove_at(i + 1)
		args.remove_at(i)
	if dir == "":
		dir = OS.get_environment("CYBERGRAM_REPORTS_DIR")
	if dir == "" and OS.get_environment("CYBERGRAM_DATA_DIR") != "":
		dir = OS.get_environment("CYBERGRAM_DATA_DIR").get_base_dir().path_join("reports")
	if dir == "":
		dir = "user://reports"
	var store := ReportStore.new(dir)
	if store.open() != OK:
		printerr("cannot open reports folder %s" % dir)
		quit(1)
		return
	var res := ReportReview.run(store, args, int(Time.get_unix_time_from_system()))
	if res.code == 0:
		print(res.text)
	else:
		printerr(res.text)
	quit(res.code)
