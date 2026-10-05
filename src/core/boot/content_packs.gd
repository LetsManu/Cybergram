class_name ContentPacks
extends RefCounted
## Mounts the optional content packs (W15-UPD) before anything loads from them.
##
## An exported game is split into:
##   Cybergram(.exe|.x86_64) + Cybergram.pck   "core", loaded by the engine itself
##   packs/maps.pck                             the map scenes (always installed)
##   packs/heroes_hd.pck                        HD hero texture maps (optional, "Lite" skips it)
##   packs/lang_<code>.pck                      non-English text (optional, none yet)
## Running from source there is no packs/ folder and everything is already in
## res://, so mounting is a no-op. A missing optional pack is fine: heroes fall
## back to flat colours (RiggedHeroModel._bind_maps). A missing `maps` pack is
## logged as an error.

## Packs every exported build ships; the rest are optional.
const REQUIRED: PackedStringArray = ["maps"]
## Folder (next to the executable) that holds the packs.
const PACK_DIR: String = "packs"
## Overrides the pack folder (tests).
const ENV_DIR: String = "CYBERGRAM_PACK_DIR"

static var _mounted: PackedStringArray = PackedStringArray()
static var _done: bool = false


## Mounts every packs/*.pck once per process (later calls return the same list).
## Returns the pack names that were mounted.
static func mount_once() -> PackedStringArray:
	if _done:
		return _mounted
	_done = true
	var dir := pack_dir()
	_mounted = mount_dir(dir)
	if DirAccess.dir_exists_absolute(dir) or OS.has_feature("template"):
		for req in REQUIRED:
			if not _mounted.has(req):
				push_error("content: required pack '%s' is missing in %s; reinstall or repair the game" % [req, dir])
	if not _mounted.is_empty():
		print("content: mounted %s" % ", ".join(_mounted))
	return _mounted


## The pack folder: $CYBERGRAM_PACK_DIR, else <executable dir>/packs.
static func pack_dir() -> String:
	var env := OS.get_environment(ENV_DIR)
	if env != "":
		return env
	return OS.get_executable_path().get_base_dir().path_join(PACK_DIR)


## Mounts every *.pck in `dir` (sorted, so the order is stable) and returns
## their names without the extension. A pack that fails to load is skipped.
static func mount_dir(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f: String in files:
		if not f.ends_with(".pck"):
			continue
		if ProjectSettings.load_resource_pack(dir.path_join(f)):
			out.append(f.get_basename())
		else:
			push_warning("content: could not load pack %s" % f)
	return out


## Names of the packs mounted by mount_once().
static func mounted() -> PackedStringArray:
	return _mounted
