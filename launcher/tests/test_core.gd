extends SceneTree
## Unit tests for LauncherCore. Run:
##   godot --headless --path launcher -s tests/test_core.gd
## Exits 0 when all checks pass, 1 otherwise.

var _fails: int = 0
var _checks: int = 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("FAIL: ", what)


func _init() -> void:
	# Version compare.
	_check(LauncherCore.compare_versions("0.4.1", "0.4.1") == 0, "equal")
	_check(LauncherCore.compare_versions("0.4.1", "0.5.0") == -1, "minor lower")
	_check(LauncherCore.compare_versions("0.10.0", "0.9.9") == 1, "numeric not lexical")
	_check(LauncherCore.compare_versions("v1.0", "1.0.0") == 0, "v prefix and missing part")
	_check(LauncherCore.compare_versions("0.5.0-rc1", "0.5.0") == -1, "prerelease below release")
	_check(LauncherCore.compare_versions("0.5.0", "0.5.0-rc1") == 1, "release above prerelease")
	_check(LauncherCore.compare_versions("0.5.0-beta", "0.5.0-rc1") == -1, "prerelease order")

	# sha256 check.
	var tmp: String = OS.get_cache_dir().path_join("cybergram_launcher_test.bin")
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("abc")
	f.close()
	var abc: String = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	_check(LauncherCore.sha256_matches(tmp, abc), "sha256 match")
	_check(LauncherCore.sha256_matches(tmp, abc.to_upper()), "sha256 case-insensitive")
	_check(not LauncherCore.sha256_matches(tmp, "00" + abc.substr(2)), "sha256 mismatch")
	_check(not LauncherCore.sha256_matches(tmp + ".missing", abc), "sha256 missing file")
	DirAccess.remove_absolute(tmp)

	# Manifest.
	var good: String = '{"version":"v0.5.0","notes_md":"# Hi","platforms":{"linux":{"file":"a.zip","size":1,"sha256":"x","exe":"g"}}}'
	var m: Dictionary = LauncherCore.parse_manifest(good)
	_check(m["ok"] and m["version"] == "0.5.0", "manifest ok, v stripped")
	_check(not LauncherCore.parse_manifest("nope")["ok"], "manifest garbage")
	_check(not LauncherCore.parse_manifest('{"version":"1"}')["ok"], "manifest without platforms")
	var evil: String = good.replace("a.zip", "../a.zip")
	_check(not LauncherCore.parse_manifest(evil)["ok"], "manifest unsafe file name")

	# URLs, platforms, zip paths.
	_check(LauncherCore.base_url("http://h:8080/version.json") == "http://h:8080/", "base url")
	_check(LauncherCore.platform_key("Windows") == "windows", "platform windows")
	_check(LauncherCore.platform_key("macOS") == "", "platform unsupported")
	_check(LauncherCore.is_safe_entry("a/b.txt"), "safe entry")
	_check(not LauncherCore.is_safe_entry("../x"), "dotdot entry")
	_check(not LauncherCore.is_safe_entry("/etc/x"), "absolute entry")
	_check(not LauncherCore.is_safe_entry("C:/x"), "drive entry")

	# Markdown.
	var bb: String = LauncherCore.markdown_to_bbcode("## Title\n- **bold** and `code`\n[x]")
	_check(bb.contains("[b]Title[/b]"), "md heading")
	_check(bb.contains("[b]bold[/b]") and bb.contains("[code]code[/code]"), "md inline")
	_check(bb.contains("[lb]x]"), "md escapes brackets")

	var wrapped: String = LauncherCore.markdown_to_bbcode("- first line\n  second line\n\npara")
	_check(wrapped.contains("first line second line"), "md joins wrapped lines")
	_check(wrapped.ends_with("\npara"), "md keeps paragraph break")

	# Server status.
	var st: Dictionary = LauncherCore.parse_status('{"online":3,"in_lobby":1,"in_match":2,"updated":5}')
	_check(st.get("online") == 3 and st.get("in_match") == 2, "status parsed")
	_check(LauncherCore.parse_status("{}").is_empty(), "status missing keys")
	_check(LauncherCore.parse_status("<html>").is_empty(), "status garbage")
	st["reachable"] = true
	_check(LauncherCore.status_text(st).contains("3 players"), "status text counts")
	_check(LauncherCore.status_text({"reachable": true}) == "Server reachable", "status text reachable only")
	_check(LauncherCore.status_text({"reachable": false}) == "Server unreachable", "status text down")

	# Verify, copy, settings.
	var base: String = OS.get_cache_dir().path_join("cybergram_launcher_verify")
	LauncherCore.remove_tree(base)
	DirAccess.make_dir_recursive_absolute(base.path_join("sub"))
	var vf: FileAccess = FileAccess.open(base.path_join("sub/a.txt"), FileAccess.WRITE)
	vf.store_string("abc")
	vf.close()
	var files: Array = [{"path": "sub/a.txt", "sha256": abc}, {"path": "gone.txt", "sha256": abc}]
	var bad: PackedStringArray = LauncherCore.verify_files(base, files)
	_check(bad.size() == 1 and bad[0] == "gone.txt", "verify finds the missing file")
	files[0]["sha256"] = "00" + abc.substr(2)
	_check(LauncherCore.verify_files(base, files).size() == 2, "verify finds the corrupt file")
	_check(LauncherCore.verify_files(base, [{"path": "../x", "sha256": abc}]).size() == 1, "verify rejects unsafe path")
	_check(LauncherCore.copy_tree(base, base + "_copy") == "", "copy tree ok")
	_check(FileAccess.get_file_as_string(base + "_copy/sub/a.txt") == "abc", "copy tree content")
	LauncherCore.remove_tree(base)
	LauncherCore.remove_tree(base + "_copy")
	var sp: String = OS.get_cache_dir().path_join("cybergram_launcher_settings_test.cfg")
	var ls: LauncherSettings = LauncherSettings.new(sp)
	ls.install_root = "/x/y"
	ls.username = "neo"
	_check(ls.save_file(), "settings save")
	var ls2: LauncherSettings = LauncherSettings.new(sp).load_file()
	_check(ls2.install_root == "/x/y" and ls2.username == "neo", "settings roundtrip")
	_check(not FileAccess.get_file_as_string(sp).to_lower().contains("token"), "settings hold no token")
	DirAccess.remove_absolute(sp)

	# Launcher self-update selection and swap.
	var lau: Dictionary = {"version": "1.2.0", "platforms": {"linux": {"file": "L.zip", "sha256": "x", "exe": "CybergramLauncher.x86_64", "size": 3}}}
	_check(LauncherCore.launcher_update_for(lau, "linux", "1.1.0").get("version") == "1.2.0", "launcher update offered")
	_check(LauncherCore.launcher_update_for(lau, "linux", "1.2.0").is_empty(), "launcher current: nothing")
	_check(LauncherCore.launcher_update_for(lau, "linux", "2.0.0").is_empty(), "launcher newer than feed: nothing")
	_check(LauncherCore.launcher_update_for(lau, "windows", "1.0.0").is_empty(), "launcher no platform entry")
	_check(LauncherCore.launcher_update_for({}, "linux", "1.0.0").is_empty(), "launcher no section")
	lau["platforms"]["linux"]["file"] = "../L.zip"
	_check(LauncherCore.launcher_update_for(lau, "linux", "1.0.0").is_empty(), "launcher unsafe file name")
	var sb: String = OS.get_cache_dir().path_join("cybergram_selfupd")
	LauncherCore.remove_tree(sb)
	DirAccess.make_dir_recursive_absolute(sb.path_join("new"))
	DirAccess.make_dir_recursive_absolute(sb.path_join("live"))
	for pair in [["new/L.x86_64", "NEW"], ["new/launcher.cfg", "newcfg"], ["live/L.x86_64", "OLD"], ["live/launcher.cfg", "mycfg"]]:
		var wf: FileAccess = FileAccess.open(sb.path_join(pair[0]), FileAccess.WRITE)
		wf.store_string(pair[1])
		wf.close()
	_check(SelfUpdater.apply_update(sb.path_join("new"), sb.path_join("live")) == "", "apply_update ok")
	_check(FileAccess.get_file_as_string(sb.path_join("live/L.x86_64")) == "NEW", "exe replaced")
	_check(FileAccess.get_file_as_string(sb.path_join("live/launcher.cfg")) == "mycfg", "launcher.cfg kept")
	_check(FileAccess.file_exists(sb.path_join("live/L.x86_64.old")), "old exe renamed aside")
	SelfUpdater.cleanup_old(sb.path_join("live"))
	_check(not FileAccess.file_exists(sb.path_join("live/L.x86_64.old")), "cleanup removes .old")
	LauncherCore.remove_tree(sb)

	print("launcher core tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
