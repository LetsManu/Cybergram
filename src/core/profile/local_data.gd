class_name LocalData
extends RefCounted
## The player's data rights over what this game stores on their machine
## (design/ux/lobby-and-social.md §4, PRIVACY.md): export() writes one
## readable JSON with everything (profile, friends, mutes / blocks /
## reports, menu preferences); delete_all() removes those files. The server
## keeps nothing after a disconnect, so there is nothing to delete there.
##
## Example:
##   var files := LocalData.Files.defaults()
##   var out := LocalData.export_json(files, "user://my_cybergram_data.json")
##   LocalData.delete_all(files)

const EXPORT_PATH := "user://my_cybergram_data.json"


## The local files that hold personal data.
class Files:
	extends RefCounted
	var profile: String = PlayerProfile.DEFAULT_PATH
	var friends: String = FriendList.DEFAULT_PATH
	var moderation: String = LocalModeration.DEFAULT_PATH
	var menu: String = "user://menu.cfg"

	static func defaults() -> Files:
		return Files.new()

	func all() -> PackedStringArray:
		return PackedStringArray([profile, friends, moderation, menu])


## Everything stored locally as one Dictionary (what export_json writes).
static func collect(files: Files) -> Dictionary:
	var out := {"exported_unix_time": int(Time.get_unix_time_from_system()),
		"note": "Everything Cybergram stores about you on this computer. The server keeps nothing after you disconnect."}
	var p := PlayerProfile.load_or_null(files.profile)
	if p != null:
		out["profile"] = {"player_id": p.id, "private_key": p.key, "display_name": p.name, "emblem": p.emblem,
			"accent_colour": p.accent, "privacy_notice_acknowledged_version": p.privacy_ack}
	var friends: Array = []
	for f in FriendList.load_from(files.friends).friends:
		friends.append({"name": f.name, "tag": f.tag, "player_id": f.id})
	out["friends"] = friends
	var m := LocalModeration.load_from(files.moderation)
	out["muted"] = m.muted
	out["blocked"] = m.blocked
	out["reports_recorded_locally"] = m.reports
	var menu := ConfigFile.new()
	if menu.load(files.menu) == OK:
		var prefs := {}
		for s in menu.get_sections():
			for k in menu.get_section_keys(s):
				prefs["%s/%s" % [s, k]] = menu.get_value(s, k)
		out["menu_preferences"] = prefs
	return out


## Writes collect() as indented JSON to `path`. Returns the absolute OS path,
## or "" on failure.
static func export_json(files: Files, path: String = EXPORT_PATH) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(collect(files), "  "))
	f.close()
	return ProjectSettings.globalize_path(path)


## Deletes every local data file (and an earlier export). Returns how many
## files were removed.
static func delete_all(files: Files, export_path: String = EXPORT_PATH) -> int:
	var n := 0
	var paths := files.all()
	paths.append(export_path)
	for path in paths:
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK:
			n += 1
	return n
