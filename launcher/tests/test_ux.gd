extends SceneTree
## Tests for the W15-UX launcher pieces. Run:
##   godot --headless --path launcher -s tests/test_ux.gd
## Exits 0 when all pass, 1 otherwise.

var _fails: int = 0
var _checks: int = 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("FAIL: ", what)


func _init() -> void:
	_md()
	_notes()
	_history()
	_dirs()
	_settings_file()
	_syscheck()
	print("launcher ux tests: %d checks, %d failed" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


func _md() -> void:
	var t: UiKitTokens = UiKitTokens.new()
	var b: String = MdBbcode.convert("# Title\n\n## Sec\n\nHello **bold** and `code` and *it*.\nwrapped line\n\n- one\n- two\n  - nested\n- three\n\n1. a\n2. b\n", t)
	_check(b.contains("[b]Title[/b]"), "h1 bold")
	_check(b.contains("font_size=%d" % MdBbcode.H2_SIZE), "h2 size")
	_check(b.contains("[b]bold[/b]"), "bold")
	_check(b.contains("[code]code[/code]"), "inline code")
	_check(b.contains("[i]it[/i]"), "italic")
	_check(b.contains("it[/i]. wrapped line"), "paragraph lines joined")
	_check(b.count("[ul") == 2 and b.count("[/ul]") == 2, "nested list tags balanced")
	_check(b.contains("[ol type=1]a") and b.contains("[/ol]"), "numbered list")
	_check(MdBbcode.convert("a [b] c", t).contains("[lb]b[rb]"), "brackets escaped")
	_check(MdBbcode.convert("[go](https://x.y/z)", t).contains("[url=https://x.y/z]go[/url]"), "https link")
	_check(not MdBbcode.convert("[go](javascript:alert)", t).contains("[url"), "non-http link dropped")
	_check(MdBbcode.convert("![pic](nope.png)", t).contains("[i]pic[/i]"), "missing image falls back to alt")
	_check(MdBbcode.convert("![i](res://icon.svg)", t).contains("[img width="), "existing image embedded")
	_check(MdBbcode.convert("```\na [x]\n```", t).contains("a [lb]x[rb]"), "fence escaped")
	_check(MdBbcode.convert("**open", t).ends_with("[/b]"), "unclosed bold closed")
	_check(MdBbcode.convert("", t) == "", "empty")


func _notes() -> void:
	_check(ReleaseNotes.version_of_file("v0.10.0.md") == "0.10.0", "version of file")
	_check(ReleaseNotes.version_of_file("README.md") == "", "readme is not notes")
	var md: String = "# Cybergram v1: X\n\nintro\n\n## A\n- a\n\n## Hero changes\n\n### Ryker\n- r1\n- r2\n\n### Vesper Loom\n- v1\n\n## B\n- b\n"
	var hs: Dictionary = ReleaseNotes.hero_sections(md)
	_check(hs.size() == 2, "two hero sections")
	_check(String(hs["Ryker"]) == "- r1\n- r2", "hero text")
	_check(ReleaseNotes.section_for(hs, "ryker_vance").begins_with("- r1"), "first name matches id stem")
	_check(ReleaseNotes.section_for(hs, "vesper_loom").begins_with("- v1"), "full name matches")
	_check(ReleaseNotes.section_for(hs, "sable") == "", "no section for sable")
	_check(not ReleaseNotes.heading_matches("Hex", "hexagon_x"), "no loose prefix")
	_check(ReleaseNotes.hero_sections("## A\n- x").is_empty(), "no hero section")
	_check(ReleaseNotes.hero_display("juniper_quill") == "Juniper Quill", "display name")
	var base: Array[Dictionary] = [{"version": "0.9.0", "md": "a"}, {"version": "0.10.0", "md": "b"}]
	var m: Array[Dictionary] = ReleaseNotes.merge(base, [{"version": "0.11.0", "md": "c"}, {"version": "0.9.0", "md": "z"}] as Array[Dictionary])
	_check(m.size() == 3 and m[0]["version"] == "0.11.0" and m[2]["md"] == "z", "merge newest first, extra wins")
	_check(ReleaseNotes.is_draft("# x (DRAFT)"), "draft")
	var all: Array[Dictionary] = ReleaseNotes.load_all()
	_check(all.size() >= 2, "bundled notes load")
	var dir: String = OS.get_cache_dir().path_join("cg_notes_test")
	DirAccess.make_dir_recursive_absolute(dir)
	ReleaseNotes.cache("9.9.9", "# cached", dir)
	_check(ReleaseNotes.read_dir(dir).size() == 1, "cache round trip")
	DirAccess.remove_absolute(dir.path_join("v9.9.9.md"))


func _history() -> void:
	var path: String = OS.get_cache_dir().path_join("cg_hist_test.cfg")
	var cfg: ConfigFile = ConfigFile.new()
	for h in [["a", 5, 100, 10], ["b", 9, 300, 20], ["c", 2, 100, 30], ["d", 1, 5, 40]]:
		cfg.set_value(h[0], "matches", h[1])
		cfg.set_value(h[0], "minutes", h[2])
		cfg.set_value(h[0], "last_played", h[3])
	cfg.save(path)
	var e: Array[Dictionary] = HeroHistory.read_file(path)
	_check(e.size() == 4, "history read")
	_check(",".join(HeroHistory.mains(e)) == ",".join(["b", "a", "c"]), "top 3 by minutes, matches break ties")
	_check(",".join(HeroHistory.mains(e, "d")) == ",".join(["d", "b", "a"]), "pinned first")
	_check(",".join(HeroHistory.mains(e, "b")) == ",".join(["b", "a", "c"]), "pinned not duplicated")
	_check(HeroHistory.read_file(path + ".none").is_empty(), "missing file empty")
	_check(HeroHistory.mains([] as Array[Dictionary]).is_empty(), "no history no mains")
	DirAccess.remove_absolute(path)


func _dirs() -> void:
	_check(GameUserDir.resolve("Windows", "C:\\Users\\a\\AppData\\Roaming", "", "") == "C:/Users/a/AppData/Roaming/Godot/app_userdata/Cybergram", "windows dir")
	_check(GameUserDir.resolve("Linux", "", "", "/home/a") == "/home/a/.local/share/godot/app_userdata/Cybergram", "linux dir")
	_check(GameUserDir.resolve("Linux", "", "/x", "/home/a") == "/x/godot/app_userdata/Cybergram", "xdg dir")
	_check(GameUserDir.resolve("Plan9", "", "", "") == "", "unknown os")


func _settings_file() -> void:
	var path: String = OS.get_cache_dir().path_join("cg_game_settings_test.cfg")
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("look", "sensitivity_deg", 0.2)
	cfg.set_value("hud", "scale", 1.5)
	cfg.set_value("display", "vsync", false)
	cfg.save(path)
	_check(GameSettingsFile.write_values(path, {"window_mode": 2, "quality": 1, "width": 1600, "height": 900}), "write ok")
	var back: ConfigFile = ConfigFile.new()
	back.load(path)
	_check(is_equal_approx(float(back.get_value("look", "sensitivity_deg")), 0.2), "look kept")
	_check(is_equal_approx(float(back.get_value("hud", "scale")), 1.5), "hud kept")
	_check(back.get_value("display", "vsync") == false, "foreign display key kept")
	var v: Dictionary = GameSettingsFile.read_values(path)
	_check(v["window_mode"] == 2 and v["quality"] == 1 and v["width"] == 1600, "values read back")
	GameSettingsFile.write_values(path, {"quality": 3})
	v = GameSettingsFile.read_values(path)
	_check(v["quality"] == 3 and v["window_mode"] == 2, "partial write keeps the rest")
	var bad: String = path + ".bad"
	var f: FileAccess = FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("[[[ not a cfg")
	f.close()
	_check(not GameSettingsFile.write_values(bad, {"quality": 0}), "broken file is not overwritten")
	_check(FileAccess.get_file_as_string(bad) == "[[[ not a cfg", "broken file untouched")
	_check(GameSettingsFile.read_values(path + ".none")["quality"] == 2, "defaults when missing")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(bad)


func _syscheck() -> void:
	var q: Callable = func(gpu: String, ram_gb: int, vk: bool = true) -> int:
		return int(SystemCheck.recommend({"gpu": gpu, "ram_mb": ram_gb * 1024, "vulkan": vk})["quality"])
	_check(q.call("llvmpipe (LLVM)", 32) == SystemCheck.Quality.LOW, "software is low")
	_check(q.call("NVIDIA GeForce RTX 4070", 32, false) == SystemCheck.Quality.LOW, "no vulkan is low")
	_check(q.call("NVIDIA GeForce RTX 4070", 4) == SystemCheck.Quality.LOW, "little ram is low")
	_check(q.call("Intel(R) UHD Graphics 620", 8) == SystemCheck.Quality.LOW, "igpu 8gb low")
	_check(q.call("Intel(R) UHD Graphics 620", 16) == SystemCheck.Quality.MEDIUM, "igpu 16gb medium")
	_check(q.call("NVIDIA GeForce RTX 4070", 32) == SystemCheck.Quality.ULTRA, "high end ultra")
	_check(q.call("NVIDIA GeForce GTX 1060", 16) == SystemCheck.Quality.HIGH, "mid discrete high")
	_check(q.call("NVIDIA GeForce GTX 1060", 8) == SystemCheck.Quality.MEDIUM, "mid discrete 8gb medium")
	_check(q.call("", 16) == SystemCheck.Quality.MEDIUM, "unknown gpu medium")
