class_name ContentManifest
extends RefCounted
## Pure helpers for per-file (delta) updates and content packs (W15-UPD).
## No scene or network access, so everything here is unit-testable
## (tests/test_upd.gd).
##
## Feed shape (inside the signed version.json), per platform:
##   files:  [{path, size, sha256, group}]   every file of the build
##   groups: {name: {size, optional}}         informational, recomputed here
## Top level: "blobs": "blobs/" (folder of files named by their sha256, shared
## by every platform and version) and an optional "next" block (pre-load).
## Groups: "core" (exe, Cybergram.pck, ...), "maps", "heroes_hd", "lang_<code>".

const CORE: String = "core"
## Groups every install needs. Everything else is optional.
const REQUIRED_GROUPS: PackedStringArray = ["core", "maps"]
## Install-root file listing the optional groups the player switched off
## (written by the launcher and by the installers' "Lite install").
const CONTENT_CFG: String = "content.cfg"
## File inside game/ with the per-file list of the installed version.
const INSTALLED_MANIFEST: String = ".manifest.json"
const DEFAULT_BLOBS: String = "blobs/"


## Group of a file from its path: packs/<name>.pck -> <name>, else "core".
static func group_of(path: String) -> String:
	if path.begins_with("packs/") and path.ends_with(".pck") and path.count("/") == 1:
		return path.get_file().get_basename()
	return CORE


static func is_optional(group: String) -> bool:
	return not REQUIRED_GROUPS.has(group)


## Player-facing name of a group.
static func label(group: String) -> String:
	match group:
		"core":
			return "Game"
		"maps":
			return "Maps"
		"heroes_hd":
			return "HD hero textures"
	if group.begins_with("lang_"):
		return "Language: %s" % group.substr(5).to_upper()
	return group.capitalize()


## One-line description of a group for the Content settings.
static func blurb(group: String) -> String:
	if group == "heroes_hd":
		return "Detailed hero textures. Turn off for a smaller download on weaker PCs (Lite)."
	if group.begins_with("lang_"):
		return "Text in this language."
	return "Required."


static func _is_sha(s: String) -> bool:
	if s.length() != 64:
		return false
	for c in s.to_lower():
		if not "0123456789abcdef".contains(c):
			return false
	return true


## The validated file list of a platform entry: [{path, size, sha256, group}]
## (group filled in from the path when the feed has none). Returns [] when
## any entry is malformed or unsafe, so a bad list is never half-used.
static func files_of(entry: Dictionary) -> Array:
	var raw: Variant = entry.get("files", [])
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item: Variant in raw:
		if typeof(item) != TYPE_DICTIONARY:
			return []
		var e: Dictionary = item
		var p: String = String(e.get("path", ""))
		var sha: String = String(e.get("sha256", "")).to_lower()
		if not LauncherCore.is_safe_entry(p) or p.ends_with("/") or not _is_sha(sha):
			return []
		if typeof(e.get("size")) != TYPE_FLOAT and typeof(e.get("size")) != TYPE_INT:
			return []
		var g: String = String(e.get("group", group_of(p)))
		if g == "" or g.contains("/") or g.contains(".."):
			return []
		out.append({"path": p, "size": int(e["size"]), "sha256": sha, "group": g})
	return out


## {group: {"size": bytes, "count": files, "optional": bool}} of a file list.
static func groups(files: Array) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in files:
		var g: String = e["group"]
		if not out.has(g):
			out[g] = {"size": 0, "count": 0, "optional": is_optional(g)}
		out[g]["size"] += int(e["size"])
		out[g]["count"] += 1
	return out


## The files to install when the optional groups in `skip` are switched off.
static func select(files: Array, skip: PackedStringArray) -> Array:
	var out: Array = []
	for e: Dictionary in files:
		if not (skip.has(e["group"]) and is_optional(e["group"])):
			out.append(e)
	return out


static func total_size(files: Array) -> int:
	var n: int = 0
	for e: Dictionary in files:
		n += int(e["size"])
	return n


## True when the file at `path` has `size` bytes and the sha256 `sha`.
static func file_matches(path: String, size: int, sha: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() != size:
		return false
	f.close()
	return LauncherCore.sha256_matches(path, sha)


## The entries of `files` that are missing or differ below `dir`.
static func needed(dir: String, files: Array) -> Array:
	var out: Array = []
	for e: Dictionary in files:
		if not file_matches(dir.path_join(e["path"]), int(e["size"]), e["sha256"]):
			out.append(e)
	return out


## Paths listed in `old_files` that `new_files` no longer has.
static func stale(old_files: Array, new_files: Array) -> PackedStringArray:
	var keep: Dictionary = {}
	for e: Dictionary in new_files:
		keep[e["path"]] = true
	var out: PackedStringArray = PackedStringArray()
	for e: Dictionary in old_files:
		if not keep.has(e["path"]):
			out.append(e["path"])
	return out


## URL of a blob: <base_url><blobs><sha256>.
static func blob_url(base_url: String, blobs: String, sha: String) -> String:
	var b: String = blobs if blobs != "" else DEFAULT_BLOBS
	if not b.ends_with("/"):
		b += "/"
	return base_url + b + sha


## Unix time of an ISO-8601 UTC time ("2026-10-12T18:00:00Z"; an explicit
## "+hh:mm" / "-hh:mm" offset is honoured). Returns -1 when unreadable.
static func parse_iso_utc(s: String) -> int:
	var t: String = s.strip_edges()
	var re := RegEx.create_from_string("^(\\d{4}-\\d{2}-\\d{2})[T ](\\d{2}:\\d{2}(:\\d{2})?)(\\.\\d+)?(Z|[+-]\\d{2}:?\\d{2})?$")
	var m: RegExMatch = re.search(t)
	if m == null:
		return -1
	var hms: String = m.get_string(2)
	if hms.length() == 5:
		hms += ":00"
	var unix: int = Time.get_unix_time_from_datetime_string(m.get_string(1) + "T" + hms)
	var tz: String = m.get_string(5)
	if tz != "" and tz != "Z":
		var sign: int = -1 if tz.begins_with("+") else 1
		var digits: String = tz.substr(1).replace(":", "")
		unix += sign * (digits.substr(0, 2).to_int() * 3600 + digits.substr(2, 2).to_int() * 60)
	return unix


## Local wall-clock text of a unix time ("Mon 12 Oct 20:00").
## `bias_min` = the local offset from UTC in minutes (system zone by default).
static func local_time_text(unix: int, bias_min: int = 0x7fffffff) -> String:
	var bias: int = bias_min
	if bias == 0x7fffffff:
		bias = int(Time.get_time_zone_from_system().get("bias", 0))
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	var days: PackedStringArray = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months: PackedStringArray = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d %s %02d:%02d" % [days[int(d["weekday"])], int(d["day"]), months[int(d["month"]) - 1],
		int(d["hour"]), int(d["minute"])]


## The feed's "next" block for `platform`, or {} when absent or malformed:
## {"version", "activate_at" (unix), "activate_text" (as in the feed), "files", "exe"}.
static func parse_next(next: Variant, platform: String) -> Dictionary:
	if typeof(next) != TYPE_DICTIONARY:
		return {}
	var n: Dictionary = next
	if typeof(n.get("version")) != TYPE_STRING or typeof(n.get("activate_at")) != TYPE_STRING:
		return {}
	var at: int = parse_iso_utc(String(n["activate_at"]))
	var plats: Variant = n.get("platforms")
	if at < 0 or typeof(plats) != TYPE_DICTIONARY or typeof((plats as Dictionary).get(platform)) != TYPE_DICTIONARY:
		return {}
	var e: Dictionary = (plats as Dictionary)[platform]
	var files: Array = files_of(e)
	var exe: String = String(e.get("exe", ""))
	if files.is_empty() or not LauncherCore.is_safe_entry(exe):
		return {}
	return {"version": String(n["version"]).trim_prefix("v"), "activate_at": at,
		"activate_text": String(n["activate_at"]), "files": files, "exe": exe}


## Optional groups switched off for the install in `root` (content.cfg).
static func load_skip(root: String) -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(root.path_join(CONTENT_CFG)) != OK:
		return PackedStringArray()
	var v: Variant = cfg.get_value("content", "skip", PackedStringArray())
	var out := PackedStringArray()
	if typeof(v) == TYPE_PACKED_STRING_ARRAY or typeof(v) == TYPE_ARRAY:
		for g: Variant in v:
			if is_optional(String(g)) and not out.has(String(g)):
				out.append(String(g))
	return out


static func save_skip(root: String, skip: PackedStringArray) -> bool:
	DirAccess.make_dir_recursive_absolute(root)
	var cfg := ConfigFile.new()
	cfg.set_value("content", "skip", skip)
	return cfg.save(root.path_join(CONTENT_CFG)) == OK


## The per-file list recorded for the installed version ([] when unknown).
static func load_installed(game_dir: String) -> Array:
	var p: String = game_dir.path_join(INSTALLED_MANIFEST)
	if not FileAccess.file_exists(p):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return files_of(parsed)


static func save_installed(game_dir: String, files: Array) -> bool:
	var f: FileAccess = FileAccess.open(game_dir.path_join(INSTALLED_MANIFEST), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"files": files}))
	f.close()
	return true


## Bytes used by a folder tree (0 when missing).
static func tree_size(dir_path: String) -> int:
	if not DirAccess.dir_exists_absolute(dir_path):
		return 0
	var n: int = 0
	for sub in DirAccess.get_directories_at(dir_path):
		n += tree_size(dir_path.path_join(sub))
	for f in DirAccess.get_files_at(dir_path):
		var fa: FileAccess = FileAccess.open(dir_path.path_join(f), FileAccess.READ)
		if fa != null:
			n += fa.get_length()
			fa.close()
	return n


## "1.2 GB" / "340 MB" / "12 KB".
static func size_text(bytes: int) -> String:
	if bytes >= 1073741824:
		return "%.1f GB" % (bytes / 1073741824.0)
	if bytes >= 1048576:
		return "%.0f MB" % (bytes / 1048576.0) if bytes >= 104857600 else "%.1f MB" % (bytes / 1048576.0)
	return "%d KB" % maxi(1, int(ceil(bytes / 1024.0))) if bytes > 0 else "0 KB"
