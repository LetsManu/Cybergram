class_name LauncherCore
extends RefCounted
## Pure helpers for the launcher: version compare, manifest parsing, sha256
## check, markdown to BBCode, safe zip extraction. No scene or network access,
## so everything here is unit-testable (see tests/test_core.gd).

## Default location of the update manifest (overridable in launcher.cfg).
const DEFAULT_VERSION_URL: String = "http://cyber.djboeck.at:8080/version.json"
## Detached signature of the feed, next to version.json (base64 of an ECDSA
## P-256 / SHA-256 DER signature over the exact bytes of version.json).
const SIG_SUFFIX: String = ".sig"
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
		var listed: Variant = entry.get("files", [])
		if typeof(listed) != TYPE_ARRAY:
			return {"ok": false, "error": "platform %s has a malformed file list" % key}
		var file_name: String = entry["file"]
		if file_name.contains("/") or file_name.contains("\\") or file_name.contains(".."):
			return {"ok": false, "error": "platform %s has an unsafe file name" % key}
		if not is_safe_entry(String(entry["exe"])):
			return {"ok": false, "error": "platform %s has an unsafe exe path" % key}
	return {
		"ok": true, "error": "",
		"version": String(d["version"]).trim_prefix("v"),
		"notes_md": String(d.get("notes_md", "")),
		"platforms": plat_dict,
		"launcher": d.get("launcher", {}) if typeof(d.get("launcher", {})) == TYPE_DICTIONARY else {},
	}


## Checks the feed signature. `body`: the exact bytes of version.json;
## `sig_text`: the content of version.json.sig ("" = none was served);
## `pem`: the pinned public key ("" = built without one).
## Policy (fail closed once a key is pinned):
##   key pinned  -> ok only with a valid signature; missing or bad = refused.
##   no key      -> ok with a warning (cannot verify; legacy / dev builds).
## Returns {"ok": bool, "signed": bool, "message": String}.
static func verify_feed(body: PackedByteArray, sig_text: String, pem: String) -> Dictionary:
	if pem.strip_edges() == "":
		return {"ok": true, "signed": false,
			"message": "Update feed not verified: this launcher was built without a signing key."}
	var key := CryptoKey.new()
	if key.load_from_string(pem, true) != OK:
		return {"ok": false, "signed": false, "message": "The launcher's update key is unreadable. Reinstall the launcher."}
	var sig := Marshalls.base64_to_raw(sig_text.strip_edges()) if sig_text.strip_edges() != "" else PackedByteArray()
	if sig.is_empty():
		return {"ok": false, "signed": false, "message": "The update feed is not signed, so it was not trusted."}
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(body)
	if not Crypto.new().verify(HashingContext.HASH_SHA256, h.finish(), sig, key):
		return {"ok": false, "signed": false, "message": "The update feed signature is invalid, so it was not trusted."}
	return {"ok": true, "signed": true, "message": ""}


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


## Checks an installed folder against the manifest's `files` array
## ([{path,size,sha256}]). Returns the relative paths that are missing or
## whose sha256 differs (empty = intact). Unsafe manifest paths count as bad.
## Extra files in the folder are ignored (saves, logs, mods).
static func verify_files(dir_path: String, files: Array) -> PackedStringArray:
	var bad: PackedStringArray = PackedStringArray()
	for item: Variant in files:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = item
		var rel: String = String(e.get("path", ""))
		if not is_safe_entry(rel) or not sha256_matches(dir_path.path_join(rel), String(e.get("sha256", ""))):
			bad.append(rel)
	return bad


## Recursively copies a directory. Returns "" on success or an error text.
static func copy_tree(from_dir: String, to_dir: String) -> String:
	var err: Error = DirAccess.make_dir_recursive_absolute(to_dir)
	if err != OK:
		return "cannot create %s (%s)" % [to_dir, error_string(err)]
	for sub in DirAccess.get_directories_at(from_dir):
		var r: String = copy_tree(from_dir.path_join(sub), to_dir.path_join(sub))
		if r != "":
			return r
	for file_name in DirAccess.get_files_at(from_dir):
		var src: String = from_dir.path_join(file_name)
		var dst: String = to_dir.path_join(file_name)
		var cerr: Error = DirAccess.copy_absolute(src, dst)
		if cerr != OK:
			return "cannot copy %s (%s)" % [file_name, error_string(cerr)]
	return ""


## Picks this platform's launcher package from the feed's "launcher" section
## if it is newer than `own_version`. Returns {} when there is nothing to do
## or the entry is malformed, else {"version","file","sha256","exe","size"}.
static func launcher_update_for(launcher: Dictionary, platform: String, own_version: String) -> Dictionary:
	if launcher.is_empty() or typeof(launcher.get("version")) != TYPE_STRING:
		return {}
	var plats: Variant = launcher.get("platforms")
	if typeof(plats) != TYPE_DICTIONARY or typeof((plats as Dictionary).get(platform)) != TYPE_DICTIONARY:
		return {}
	var e: Dictionary = (plats as Dictionary)[platform]
	for field in ["file", "sha256", "exe"]:
		if typeof(e.get(field)) != TYPE_STRING:
			return {}
	var f: String = e["file"]
	var exe: String = e["exe"]
	if f.contains("/") or f.contains("\\") or f.contains("..") or not is_safe_entry(exe) or exe.contains("/"):
		return {}
	var v: String = String(launcher["version"]).trim_prefix("v")
	if compare_versions(own_version, v) >= 0:
		return {}
	return {"version": v, "file": f, "sha256": e["sha256"], "exe": exe, "size": int(e.get("size", 0))}
