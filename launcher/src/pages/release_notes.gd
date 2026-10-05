class_name ReleaseNotes
extends RefCounted
## The patch notes library of the NOTES page: the notes bundled with the
## launcher (res://assets/notes/v*.md, copied from production/releases by
## launcher/tools/sync_notes.sh), a small cache of notes seen through the
## update feed (so a version newer than the bundle still shows offline), and
## the per-hero section convention ("## Hero changes" with "### Name").
##
## An entry is {"version": "0.10.0", "md": String}. Lists are newest first.

const BUNDLE_DIR: String = "res://assets/notes"
const CACHE_DIR: String = "user://notes_cache"


## "v0.10.0.md" -> "0.10.0"; "" when the name is not a notes file.
static func version_of_file(file_name: String) -> String:
	if not (file_name.begins_with("v") and file_name.ends_with(".md")):
		return ""
	var v: String = file_name.trim_prefix("v").trim_suffix(".md")
	var parts: PackedStringArray = v.split(".")
	if parts.size() < 2:
		return ""
	for p in parts:
		if not p.is_valid_int():
			return ""
	return v


## Reads every v*.md in `dir` (missing folder = empty list).
static func read_dir(dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		var v: String = version_of_file(f)
		if v == "":
			continue
		var fa: FileAccess = FileAccess.open(dir.path_join(f), FileAccess.READ)
		if fa != null:
			out.append({"version": v, "md": fa.get_as_text()})
	return out


## Bundled notes plus the feed cache, newest first. Cache wins for a version
## present in both (it came from the signed feed).
static func load_all(bundle_dir: String = BUNDLE_DIR, cache_dir: String = CACHE_DIR) -> Array[Dictionary]:
	return merge(read_dir(bundle_dir), read_dir(cache_dir))


## Merges `extra` over `base` by version and sorts newest first.
static func merge(base: Array[Dictionary], extra: Array[Dictionary]) -> Array[Dictionary]:
	var by_ver: Dictionary = {}
	for e in base:
		by_ver[String(e["version"])] = e
	for e in extra:
		if String(e["md"]).strip_edges() != "":
			by_ver[String(e["version"])] = e
	var out: Array[Dictionary] = []
	for k in by_ver:
		out.append(by_ver[k])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return LauncherCore.compare_versions(String(a["version"]), String(b["version"])) > 0)
	return out


## Remembers notes that came through the feed (best effort).
static func cache(version: String, md: String, cache_dir: String = CACHE_DIR) -> void:
	var v: String = version.trim_prefix("v")
	if version_of_file("v%s.md" % v) == "" or md.strip_edges() == "":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	var fa: FileAccess = FileAccess.open(cache_dir.path_join("v%s.md" % v), FileAccess.WRITE)
	if fa != null:
		fa.store_string(md)


## Title of a notes file without the version prefix ("Shardline Front (pre-alpha)").
static func short_title(md: String) -> String:
	var head: String = String(LauncherCore.split_notes(md)["headline"])
	return LauncherCore.headline_title(head) if head != "" else ""


## True when the notes are marked as a draft (first lines mention DRAFT).
static func is_draft(md: String) -> bool:
	return md.left(400).to_upper().contains("DRAFT")


## Hero sections: {"Ryker": "- bullet\n- bullet", ...} read from the
## "## Hero changes" section ("### Name" blocks). Empty when there is none.
static func hero_sections(md: String) -> Dictionary:
	var out: Dictionary = {}
	var in_heroes: bool = false
	var cur: String = ""
	for raw in md.replace("\r", "").split("\n"):
		var l: String = raw.strip_edges(true, false)
		if l.begins_with("## "):
			in_heroes = l.substr(3).strip_edges().to_lower() == "hero changes"
			cur = ""
		elif in_heroes and l.begins_with("### "):
			cur = l.substr(4).strip_edges()
			out[cur] = ""
		elif in_heroes and cur != "":
			out[cur] = String(out[cur]) + raw + "\n"
	for k in out:
		out[k] = String(out[k]).strip_edges()
	return out


## True when a heading ("Ryker", "Ryker Vance", "ryker_vance") names the hero
## `hero` (an id stem like "ryker_vance"). Matches the whole name or its first
## word, case-insensitively.
static func heading_matches(heading: String, hero: String) -> bool:
	var h: String = heading.strip_edges().to_lower().replace(" ", "_")
	var stem: String = hero.strip_edges().to_lower().trim_prefix("hero_")
	if h == "" or stem == "":
		return false
	return h == stem or h == stem.get_slice("_", 0) or stem.begins_with(h + "_")


## The section text for `hero` from `sections` ("" = none).
static func section_for(sections: Dictionary, hero: String) -> String:
	for k in sections:
		if heading_matches(String(k), hero):
			return String(sections[k])
	return ""


## "ryker_vance" -> "Ryker Vance".
static func hero_display(hero: String) -> String:
	var words: PackedStringArray = hero.trim_prefix("hero_").split("_")
	var out: PackedStringArray = PackedStringArray()
	for w in words:
		out.append(w.capitalize())
	return " ".join(out)
