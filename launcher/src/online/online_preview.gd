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
				_scroll_to(main, sc)
		"friends", "party":
			var rail: OnlineRail = main.get("_rail")
			if rail != null:
				rail.social.show_sample(state == "party")
		"crash":
			var cr: CrashReporter = main.get("_crash")
			if cr != null:
				cr.prompt(11, true)
		"privacy":
			main.call("_show_page", "settings")
			_scroll_to(main, main.get("_privacy"))


## Scrolls the settings page so `c` is in view (it may sit under other cards).
static func _scroll_to(main: Node, c: Control) -> void:
	var pages: Dictionary = main.get("_pages")
	var sc: ScrollContainer = pages.get("settings") as ScrollContainer
	if sc == null or c == null:
		return
	await main.get_tree().process_frame
	await main.get_tree().process_frame
	sc.scroll_vertical = int(c.global_position.y - sc.global_position.y + sc.scroll_vertical - 20)
