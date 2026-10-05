extends SceneTree
## W15-UPD unit tests: per-file manifest, content packs, delta swap with
## rollback, pre-load activation, install management, AppImage feed entry.
##   godot --headless --path launcher -s tests/test_upd.gd
## Exits 0 when all checks pass, 1 otherwise.

var _fails: int = 0
var _checks: int = 0
var _tmp: String = ""


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("FAIL: ", what)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _sha(text: String) -> String:
	return text.sha256_text()


func _entry(path: String, text: String, group: String = "") -> Dictionary:
	var e: Dictionary = {"path": path, "size": text.to_utf8_buffer().size(), "sha256": _sha(text)}
	if group != "":
		e["group"] = group
	return e


func _init() -> void:
	var base: String = OS.get_environment("TMPDIR") if OS.get_environment("TMPDIR") != "" else "/tmp"
	_tmp = base.path_join("cg_upd_test")
	LauncherCore.remove_tree(_tmp)
	_manifest_tests()
	_time_tests()
	_swap_tests()
	_content_tests()
	_preload_tests()
	_install_tests()
	_appimage_tests()
	LauncherCore.remove_tree(_tmp)
	print("launcher upd tests: %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _manifest_tests() -> void:
	_check(ContentManifest.group_of("packs/heroes_hd.pck") == "heroes_hd", "group from pack path")
	_check(ContentManifest.group_of("packs/lang_de.pck") == "lang_de", "language pack group")
	_check(ContentManifest.group_of("Cybergram.pck") == "core", "main pck is core")
	_check(ContentManifest.group_of("packs/sub/x.pck") == "core", "nested pack path is core")
	_check(not ContentManifest.is_optional("maps") and ContentManifest.is_optional("heroes_hd"), "required vs optional")
	_check(ContentManifest.label("heroes_hd") == "HD hero textures", "HD pack label")
	_check(ContentManifest.label("lang_de") == "Language: DE", "language label")
	var files: Array = ContentManifest.files_of({"files": [_entry("Cybergram.x86_64", "exe"),
		_entry("packs/maps.pck", "maps"), _entry("packs/heroes_hd.pck", "hd!")]})
	_check(files.size() == 3 and files[2]["group"] == "heroes_hd" and files[0]["group"] == "core", "files_of fills groups")
	_check(ContentManifest.files_of({"files": [{"path": "../x", "size": 1, "sha256": _sha("x")}]}).is_empty(), "unsafe path rejects list")
	_check(ContentManifest.files_of({"files": [{"path": "x", "size": 1, "sha256": "abc"}]}).is_empty(), "bad sha rejects list")
	_check(ContentManifest.files_of({"files": [{"path": "x", "sha256": _sha("x")}]}).is_empty(), "missing size rejects list")
	_check(ContentManifest.files_of({"files": [_entry("x", "x", "../g")]}).is_empty(), "unsafe group rejects list")
	var g: Dictionary = ContentManifest.groups(files)
	_check(g["heroes_hd"]["size"] == 3 and g["heroes_hd"]["optional"] and not g["core"]["optional"], "group sizes")
	var lite: Array = ContentManifest.select(files, PackedStringArray(["heroes_hd", "maps"]))
	_check(lite.size() == 2 and not ContentManifest.stale(files, lite).is_empty(), "select skips optional only")
	_check(ContentManifest.stale(files, lite) == PackedStringArray(["packs/heroes_hd.pck"]), "stale lists removed file")
	_check(ContentManifest.blob_url("http://h/u/", "blobs", "ab") == "http://h/u/blobs/ab", "blob url")
	_check(ContentManifest.blob_url("http://h/u/", "", "ab") == "http://h/u/blobs/ab", "blob url default")
	_check(ContentManifest.size_text(17143844) == "16.3 MB", "size text MB")
	_check(ContentManifest.size_text(2147483648) == "2.0 GB", "size text GB")
	var d: String = _tmp.path_join("needed")
	_write(d.path_join("Cybergram.x86_64"), "exe")
	_write(d.path_join("packs/maps.pck"), "old maps")
	var need: Array = ContentManifest.needed(d, files)
	_check(need.size() == 2 and need[0]["path"] == "packs/maps.pck", "needed: changed + missing only")
	_check(LauncherDownloader.split_url("http://127.0.0.1:8090/blobs/ab") == {"tls": false, "host": "127.0.0.1", "port": 8090, "path": "/blobs/ab"}, "split url with port")
	_check(LauncherDownloader.split_url("https://x.org")["port"] == 443, "split url https default port")
	_check(LauncherDownloader.split_url("ftp://x").is_empty(), "split url rejects other schemes")
	var m: Dictionary = LauncherCore.parse_manifest(JSON.stringify({"version": "1.0.0", "blobs": "b/",
		"platforms": {"linux": {"file": "a.zip", "sha256": "x", "exe": "Cybergram.x86_64"}},
		"next": {"version": "1.1.0", "activate_at": "2026-10-12T18:00:00Z"}}))
	_check(m["ok"] and m["blobs"] == "b/" and m["next"]["version"] == "1.1.0", "parse_manifest keeps blobs and next")


func _time_tests() -> void:
	_check(ContentManifest.parse_iso_utc("1970-01-01T00:01:00Z") == 60, "iso Z")
	_check(ContentManifest.parse_iso_utc("2026-10-12T18:00:00Z") == 1791828000, "iso date")
	_check(ContentManifest.parse_iso_utc("2026-10-12T20:00:00+02:00") == 1791828000, "iso with offset")
	_check(ContentManifest.parse_iso_utc("2026-10-12T18:00Z") == 1791828000, "iso without seconds")
	_check(ContentManifest.parse_iso_utc("tomorrow") == -1, "iso garbage")
	_check(ContentManifest.local_time_text(1791828000, 120) == "Mon 12 Oct 20:00", "local time with bias")
	var nx: Dictionary = ContentManifest.parse_next({"version": "v1.1.0", "activate_at": "2026-10-12T18:00:00Z",
		"platforms": {"linux": {"exe": "Cybergram.x86_64", "files": [_entry("a", "a")]}}}, "linux")
	_check(nx.get("version", "") == "1.1.0" and nx["activate_at"] == 1791828000, "parse next")
	_check(ContentManifest.parse_next({"version": "1", "activate_at": "soon", "platforms": {}}, "linux").is_empty(), "next with bad time")
	_check(ContentManifest.parse_next({"version": "1", "activate_at": "2026-10-12T18:00:00Z",
		"platforms": {"windows": {"exe": "C.exe", "files": [_entry("a", "a")]}}}, "linux").is_empty(), "next for other platform")


func _swap_tests() -> void:
	var g: String = _tmp.path_join("swap/game")
	var st: String = _tmp.path_join("swap/game.stage")
	var un: String = _tmp.path_join("swap/game.undo")
	_write(g.path_join("a.txt"), "old a")
	_write(g.path_join("gone.txt"), "old gone")
	_write(g.path_join("keep.txt"), "keep")
	_write(st.path_join("a.txt"), "new a")
	_write(st.path_join("sub/b.txt"), "new b")
	DeltaInstaller.fail_after = 2
	var err: String = DeltaInstaller.swap(g, st, un, PackedStringArray(["a.txt", "sub/b.txt"]), PackedStringArray(["gone.txt"]))
	DeltaInstaller.fail_after = -1
	_check(err != "", "simulated failure reported")
	_check(FileAccess.get_file_as_string(g.path_join("a.txt")) == "old a", "rollback restores replaced file")
	_check(FileAccess.get_file_as_string(g.path_join("gone.txt")) == "old gone", "rollback restores removed file")
	_check(not FileAccess.file_exists(g.path_join("sub/b.txt")), "rollback drops new file")
	_write(st.path_join("a.txt"), "new a")
	_write(st.path_join("sub/b.txt"), "new b")
	err = DeltaInstaller.swap(g, st, un, PackedStringArray(["a.txt", "sub/b.txt"]), PackedStringArray(["gone.txt"]))
	_check(err == "", "swap ok: %s" % err)
	_check(FileAccess.get_file_as_string(g.path_join("a.txt")) == "new a" and FileAccess.get_file_as_string(g.path_join("sub/b.txt")) == "new b", "swap installs new files")
	_check(not FileAccess.file_exists(g.path_join("gone.txt")) and FileAccess.file_exists(g.path_join("keep.txt")), "swap removes stale, keeps others")
	_check(not DirAccess.dir_exists_absolute(un) and not DirAccess.dir_exists_absolute(st), "swap cleans stage and undo")


func _updater(root: String) -> Updater:
	var u := Updater.new()
	u.setup(root, "http://127.0.0.1:1/version.json", "Linux")
	u.auto_preload = false
	return u


func _install(root: String, version: String, files: Dictionary) -> void:
	for p: String in files:
		_write(root.path_join("game").path_join(p), files[p])
	_write(root.path_join("game/installed_version.txt"), version + "\n")


func _content_tests() -> void:
	var root: String = _tmp.path_join("content")
	_install(root, "1.0.0", {"Cybergram.x86_64": "exe", "packs/maps.pck": "maps", "packs/heroes_hd.pck": "hd"})
	ContentManifest.save_installed(root.path_join("game"), ContentManifest.files_of({"files": [
		_entry("Cybergram.x86_64", "exe"), _entry("packs/maps.pck", "maps"), _entry("packs/heroes_hd.pck", "hd")]}))
	var u := _updater(root)
	_check(u.skip_groups().is_empty(), "default: everything installed")
	_check(u.group_installed("heroes_hd"), "hd pack recorded")
	_check(u.set_group_enabled("maps", false) != "", "required pack cannot be removed")
	_check(u.set_group_enabled("heroes_hd", false) == "", "remove hd pack")
	_check(not FileAccess.file_exists(root.path_join("game/packs/heroes_hd.pck")), "hd pack file deleted")
	_check(FileAccess.file_exists(root.path_join("game/packs/maps.pck")), "maps pack kept")
	_check(u.skip_groups() == PackedStringArray(["heroes_hd"]), "skip saved to content.cfg")
	_check(not u.group_installed("heroes_hd"), "manifest updated after removal")
	_check(ContentManifest.load_skip(root) == PackedStringArray(["heroes_hd"]), "content.cfg readable")
	_check(u.set_group_enabled("heroes_hd", true) == "" and u.skip_groups().is_empty(), "re-enable clears skip")
	_write(root.path_join(ContentManifest.CONTENT_CFG), "[content]\nskip=PackedStringArray(\"heroes_hd\", \"core\")\n")
	_check(ContentManifest.load_skip(root) == PackedStringArray(["heroes_hd"]), "installer-written cfg cannot skip core")
	u.free()


## A pre-load on disk as the launcher leaves it: feed.json (+ sig), ready.json, blobs.
func _make_preload(root: String, version: String, at_iso: String, files: Dictionary) -> void:
	var listed: Array = []
	for p: String in files:
		listed.append(_entry(p, files[p]))
		_write(root.path_join("preload/blobs").path_join(_sha(files[p])), files[p])
	var feed: Dictionary = {"version": "1.0.0", "platforms": {"linux": {"file": "x.zip", "sha256": "0", "exe": "Cybergram.x86_64"}},
		"next": {"version": version, "activate_at": at_iso, "platforms": {"linux": {"exe": "Cybergram.x86_64", "files": listed}}}}
	_write(root.path_join("preload/feed.json"), JSON.stringify(feed))
	_write(root.path_join("preload/feed.json.sig"), "")
	_write(root.path_join("preload/ready.json"), JSON.stringify({"version": version, "activate_at": ContentManifest.parse_iso_utc(at_iso)}))


func _preload_tests() -> void:
	var root: String = _tmp.path_join("preload")
	_install(root, "1.0.0", {"Cybergram.x86_64": "exe 1.0", "data/same.txt": "same", "data/old.txt": "old"})
	_make_preload(root, "1.1.0", "2026-10-12T18:00:00Z", {"Cybergram.x86_64": "exe 1.1", "data/same.txt": "same", "data/new.txt": "new"})
	ContentManifest.save_installed(root.path_join("game"), ContentManifest.files_of({"files": [
		_entry("Cybergram.x86_64", "exe 1.0"), _entry("data/same.txt", "same"), _entry("data/old.txt", "old")]}))
	var u := _updater(root)
	var texts: Array = []
	u.preload_changed.connect(func(t: String) -> void: texts.append(t))
	u._refresh_preload_text()
	_check(u.preload_text.begins_with("Pre-loaded 1.1.0, ready at "), "pre-load status line: %s" % u.preload_text)
	u.now_override = ContentManifest.parse_iso_utc("2026-10-12T17:59:59Z")
	_check(not u.activate_preload_if_due(), "not activated before activate_at")
	_check(u.installed_version() == "1.0.0", "old version still installed before the time")
	u.now_override = ContentManifest.parse_iso_utc("2026-10-12T18:00:00Z")
	_check(u.activate_preload_if_due(), "activated at activate_at")
	_check(u.installed_version() == "1.1.0", "version is the pre-loaded one")
	_check(FileAccess.get_file_as_string(root.path_join("game/Cybergram.x86_64")) == "exe 1.1", "changed file swapped in")
	_check(FileAccess.get_file_as_string(root.path_join("game/data/new.txt")) == "new", "new file added")
	_check(not FileAccess.file_exists(root.path_join("game/data/old.txt")), "dropped file removed")
	_check(not DirAccess.dir_exists_absolute(root.path_join("preload")), "pre-load cache cleared")
	_check(u.preload_text == "", "status line cleared")
	_check(not u.activate_preload_if_due(), "nothing left to activate")
	# A missing blob blocks activation and leaves the old install alone.
	_make_preload(root, "1.2.0", "2026-10-12T18:00:00Z", {"Cybergram.x86_64": "exe 1.2"})
	DirAccess.remove_absolute(root.path_join("preload/blobs").path_join(_sha("exe 1.2")))
	u.now_override = ContentManifest.parse_iso_utc("2026-10-13T00:00:00Z")
	_check(not u.activate_preload_if_due() and u.installed_version() == "1.1.0", "incomplete pre-load not activated")
	# A pre-load older than the install is discarded.
	_make_preload(root, "1.0.5", "2026-10-12T18:00:00Z", {"Cybergram.x86_64": "exe 1.0.5"})
	_check(not u.activate_preload_if_due() and not DirAccess.dir_exists_absolute(root.path_join("preload")), "stale pre-load discarded")
	# A tampered feed.json (no longer matching ready.json) is discarded.
	_make_preload(root, "1.3.0", "2026-10-12T18:00:00Z", {"Cybergram.x86_64": "exe 1.3"})
	_write(root.path_join("preload/ready.json"), JSON.stringify({"version": "9.9.9", "activate_at": 0}))
	_check(not u.activate_preload_if_due() and u.installed_version() == "1.1.0", "mismatched pre-load refused")
	u.free()


func _install_tests() -> void:
	var root: String = _tmp.path_join("inst")
	_install(root, "1.0.0", {"Cybergram.x86_64": "exe", "packs/maps.pck": "0123456789"})
	ContentManifest.save_skip(root, PackedStringArray(["heroes_hd"]))
	_write(root.path_join("preload/ready.json"), "{}")
	var u := _updater(root)
	var du: Dictionary = u.disk_usage()
	_check(int(du["used"]) >= 13 and int(du["free"]) > 0, "disk usage: used %d free %d" % [du["used"], du["free"]])
	var moved: String = _tmp.path_join("inst_moved")
	_check(u.move_install(moved) == "", "move install")
	_check(u.install_root() == moved and u.installed_version() == "1.0.0", "updater follows the move")
	_check(ContentManifest.load_skip(moved) == PackedStringArray(["heroes_hd"]), "content selection moved")
	_check(FileAccess.file_exists(moved.path_join("preload/ready.json")) and not DirAccess.dir_exists_absolute(root.path_join("game")), "pre-load moved, old folder emptied")
	_install(root, "1.0.0", {"Cybergram.x86_64": "exe"})
	_check(u.move_install(root) != "", "move refuses a folder that already has a game")
	var settings: String = _tmp.path_join("userdata/Cybergram")
	_write(settings.path_join("settings.cfg"), "x")
	_check(u.uninstall_game(true, settings) == "", "uninstall keeping settings")
	_check(u.installed_version() == "" and not DirAccess.dir_exists_absolute(moved.path_join("game")), "game removed")
	_check(not FileAccess.file_exists(moved.path_join(ContentManifest.CONTENT_CFG)), "content.cfg removed")
	_check(FileAccess.file_exists(settings.path_join("settings.cfg")), "settings kept")
	_install(moved, "1.0.0", {"Cybergram.x86_64": "exe"})
	_check(u.uninstall_game(false, settings) == "" and not DirAccess.dir_exists_absolute(settings), "uninstall deleting settings")
	_check(Updater.game_user_dir().ends_with("/Cybergram"), "game settings folder is next to the launcher's")
	u.free()


func _appimage_tests() -> void:
	var sha: String = _sha("appimage")
	var launcher: Dictionary = {"version": "0.11.0", "platforms": {"linux": {"file": "L.zip", "sha256": _sha("z"),
		"exe": "CybergramLauncher.x86_64", "appimage": {"file": "Cybergram-0.11.0-x86_64.AppImage", "sha256": sha, "size": 8}}}}
	var e: Dictionary = LauncherCore.launcher_update_for(launcher, "linux", "0.10.0")
	_check(e.get("appimage", {}).get("sha256", "") == sha, "feed carries the AppImage")
	launcher["platforms"]["linux"]["appimage"]["file"] = "../evil.AppImage"
	_check(not LauncherCore.launcher_update_for(launcher, "linux", "0.10.0").has("appimage"), "unsafe AppImage name ignored")
	var dir: String = _tmp.path_join("appimage")
	_write(dir.path_join("Cybergram.AppImage"), "old")
	_write(dir.path_join("download.part"), "appimage")
	_check(AppImageUpdater.replace(dir.path_join("download.part"), dir.path_join("Cybergram.AppImage"), _sha("wrong")) != "", "AppImage: bad sha refused")
	_check(FileAccess.get_file_as_string(dir.path_join("Cybergram.AppImage")) == "old", "AppImage untouched after bad sha")
	_check(not FileAccess.file_exists(dir.path_join("download.part")), "bad download deleted")
	_write(dir.path_join("download.part"), "appimage")
	_check(AppImageUpdater.replace(dir.path_join("download.part"), dir.path_join("Cybergram.AppImage"), sha) == "", "AppImage replaced")
	_check(FileAccess.get_file_as_string(dir.path_join("Cybergram.AppImage")) == "appimage", "new AppImage in place")
	_check(FileAccess.get_unix_permissions(dir.path_join("Cybergram.AppImage")) & 73 != 0, "new AppImage executable")
	_check(not FileAccess.file_exists(dir.path_join("Cybergram.AppImage.new")), "no .new left")
