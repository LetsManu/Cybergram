class_name LauncherCore
extends RefCounted
## Pure helpers for the launcher: version compare, manifest parsing, sha256
## check, markdown to BBCode, safe zip extraction. No scene or network access,
## so everything here is unit-testable (see tests/test_core.gd).

## Default location of the update manifest (overridable in launcher.cfg).
const DEFAULT_VERSION_URL: String = "http://cyber.djboeck.at:8080/version.json"
## Name of the folder (next to the launcher) that holds the installed game.
const GAME_DIR: String = "game"
## File inside game/ that records the installed version.
const VERSION_FILE: String = "installed_version.txt"


## Compares two version strings such as "0.4.1" or "v0.5.0-rc1".
## Returns -1 if a < b, 0 if equal, 1 if a > b. A pre-release suffix sorts
## before the same release ("0.5.0-rc1" < "0.5.0"). Missing parts count as 0.
static func compare_versions(a: String, b: String) -> int:
	var pa: Dictionary = _parse_version(a)
	var pb: Dictionary = _parse_version(b)
	var na: PackedInt32Array = pa["nums"]
	var nb: PackedInt32Array = pb["nums"]
	for i in range(maxi(na.size(), nb.size())):
		var x: int = na[i] if i < na.size() else 0
		var y: int = nb[i] if i < nb.size() else 0
		if x != y:
			return -1 if x < y else 1
	var ra: String = pa["pre"]
	var rb: String = pb["pre"]
	if ra == rb:
		return 0
	if ra == "":
		return 1
	if rb == "":
		return -1
	return -1 if ra < rb else 1


static func _parse_version(v: String) -> Dictionary:
	var s: String = v.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	var pre: String = ""
	var dash: int = s.find("-")
	if dash >= 0:
		pre = s.substr(dash + 1)
		s = s.substr(0, dash)
	var nums: PackedInt32Array = PackedInt32Array()
	for part in s.split("."):
		nums.append(part.to_int())
	return {"nums": nums, "pre": pre}


## True when the file at `path` has the (case-insensitive) sha256 `expected`.
static func sha256_matches(path: String, expected: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return FileAccess.get_sha256(path).to_lower() == expected.strip_edges().to_lower()


## Platform key used in version.json ("windows" / "linux"), "" if unsupported.
static func platform_key(os_name: String) -> String:
	match os_name:
		"Windows":
			return "windows"
		"Linux":
			return "linux"
		_:
			return ""


## Parses version.json text. Returns {"ok": bool, "error": String,
## "version": String, "notes_md": String, "platforms": Dictionary}.
## Each platform entry needs file, sha256 and exe (size is informational).
static func parse_manifest(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "version.json is not a JSON object"}
	var d: Dictionary = parsed
	if typeof(d.get("version")) != TYPE_STRING or String(d["version"]) == "":
		return {"ok": false, "error": "version.json has no \"version\""}
	var plats: Variant = d.get("platforms")
	if typeof(plats) != TYPE_DICTIONARY:
		return {"ok": false, "error": "version.json has no \"platforms\""}
	var plat_dict: Dictionary = plats
	for key: String in plat_dict:
		var p: Variant = plat_dict[key]
		if typeof(p) != TYPE_DICTIONARY:
			return {"ok": false, "error": "platform %s is malformed" % key}
		var entry: Dictionary = p
		for field in ["file", "sha256", "exe"]:
			if typeof(entry.get(field)) != TYPE_STRING:
				return {"ok": false, "error": "platform %s lacks \"%s\"" % [key, field]}
		var file_name: String = entry["file"]
		if file_name.contains("/") or file_name.contains("\\") or file_name.contains(".."):
			return {"ok": false, "error": "platform %s has an unsafe file name" % key}
	return {
		"ok": true, "error": "",
		"version": String(d["version"]).trim_prefix("v"),
		"notes_md": String(d.get("notes_md", "")),
		"platforms": plat_dict,
	}


## Parses status.json text into {"has_counts": true, "online", "in_lobby",
## "in_match"} (non-negative ints), or {} when it is not a valid status file.
static func parse_status(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	for key in ["online", "in_lobby", "in_match"]:
		if typeof(d.get(key)) != TYPE_FLOAT and typeof(d.get(key)) != TYPE_INT:
			return {}
	return {
		"has_counts": true,
		"online": maxi(int(d["online"]), 0),
		"in_lobby": maxi(int(d["in_lobby"]), 0),
		"in_match": maxi(int(d["in_match"]), 0),
	}


## One-line text for the server status badge.
static func status_text(info: Dictionary) -> String:
	if not bool(info.get("reachable", false)):
		return "Server unreachable"
	if not bool(info.get("has_counts", false)):
		return "Server reachable"
	return "Server online: %d players (%d in lobby, %d in match)" % [
		info["online"], info["in_lobby"], info["in_match"]]


## Base URL (with trailing slash) that the manifest's file names hang off.
static func base_url(version_url: String) -> String:
	var cut: int = version_url.rfind("/")
	return version_url.substr(0, cut + 1) if cut > 8 else version_url + "/"


## Converts simple markdown (headings, bullets, **bold**, `code`) to BBCode
## for a RichTextLabel. Square brackets in the source are escaped.
static func markdown_to_bbcode(md: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	var prev_flow: bool = false
	for raw in md.replace("\r", "").split("\n"):
		var line: String = raw.replace("[", "[lb]")
		var stripped: String = line.strip_edges(true, false)
		if stripped.begins_with("### "):
			out.append("[b]%s[/b]" % _inline(stripped.substr(4)))
		elif stripped.begins_with("## "):
			out.append("[font_size=20][color=#2fd6ff][b]%s[/b][/color][/font_size]" % _inline(stripped.substr(3)))
		elif stripped.begins_with("# "):
			out.append("[font_size=26][color=#2fd6ff][b]%s[/b][/color][/font_size]" % _inline(stripped.substr(2)))
		elif stripped.begins_with("- ") or stripped.begins_with("* "):
			out.append("  [color=#ff4fa3]•[/color] %s" % _inline(stripped.substr(2)))
		elif stripped != "" and prev_flow:
			# Hard-wrapped markdown: join continuation lines into the paragraph.
			out[out.size() - 1] += " " + _inline(stripped)
		else:
			out.append(_inline(line))
		prev_flow = stripped != "" and not stripped.begins_with("#")
	return "\n".join(out)


static func _inline(s: String) -> String:
	var res: String = ""
	var bold: bool = false
	var code: bool = false
	var i: int = 0
	while i < s.length():
		if s.substr(i, 2) == "**" and not code:
			res += "[/b]" if bold else "[b]"
			bold = not bold
			i += 2
		elif s[i] == "`":
			res += "[/code]" if code else "[code]"
			code = not code
			i += 1
		else:
			res += s[i]
			i += 1
	if bold:
		res += "[/b]"
	if code:
		res += "[/code]"
	return res


## True when a zip entry path is safe to extract below a root (no absolute
## paths, no "..", no drive letters).
static func is_safe_entry(entry: String) -> bool:
	if entry == "" or entry.begins_with("/") or entry.begins_with("\\"):
		return false
	if entry.contains(":") or entry.contains("\\"):
		return false
	for part in entry.split("/"):
		if part == "..":
			return false
	return true


## Extracts every file of `zip_path` below `dest_dir` (created if missing).
## Returns "" on success or an error message. Entries that would escape
## `dest_dir` abort the extraction.
static func extract_zip(zip_path: String, dest_dir: String) -> String:
	var zip: ZIPReader = ZIPReader.new()
	var err: Error = zip.open(zip_path)
	if err != OK:
		return "cannot open zip (%s)" % error_string(err)
	for entry in zip.get_files():
		if not is_safe_entry(entry):
			zip.close()
			return "unsafe path in zip: %s" % entry
		var target: String = dest_dir.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(target)
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var f: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			zip.close()
			return "cannot write %s (%s)" % [target, error_string(FileAccess.get_open_error())]
		f.store_buffer(zip.read_file(entry))
		f.close()
	zip.close()
	return ""


## Deletes a directory tree. Returns true if nothing is left.
static func remove_tree(dir_path: String) -> bool:
	if not DirAccess.dir_exists_absolute(dir_path):
		return true
	for sub in DirAccess.get_directories_at(dir_path):
		remove_tree(dir_path.path_join(sub))
	for file_name in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)
	return not DirAccess.dir_exists_absolute(dir_path)
