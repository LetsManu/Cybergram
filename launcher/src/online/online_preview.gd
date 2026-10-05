class_name OnlinePreview
extends RefCounted
## Screenshot states for tests/capture_online.sh (W15): the launcher started
## with `--online-preview <state>` fills sample data or opens a dialog so each
## online screen can be captured without a real account. Sample data only;
## nothing is sent. Never used by players (the flag is undocumented for them).

const ARG: String = "--online-preview"


## The requested state from the command line ("" = none).
static func requested() -> String:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = a.find(ARG)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else ""


## Applies `state` to the launcher `main` (its main.gd node).
static func apply(main: Node, state: String) -> void:
	match state:
		"diag":
			main.call("_show_page", "settings")
			var sc: SupportCard = main.get("_support")
			if sc != null:
				sc.create(false)
		"crash":
			var cr: CrashReporter = main.get("_crash")
			if cr != null:
				cr.prompt(11, true)
		"privacy":
			main.call("_show_page", "settings")
