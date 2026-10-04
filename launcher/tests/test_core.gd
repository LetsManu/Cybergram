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

	print("launcher core tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)
