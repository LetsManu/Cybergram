class_name FriendList
extends RefCounted
## The local friends list (design/ux/lobby-and-social.md §2.4), saved in
## user://friends.cfg. A friend is added by name ("Neo") or Riot-ID style
## ("Neo#1A2B"); the player id is filled in once the server or the lobby
## roster has seen a matching player (resolve()).
##
## Example:
##   var f := FriendList.load_from(FriendList.DEFAULT_PATH)
##   f.add("Neo#1A2B")
##   f.resolve("0a1b...", "Neo")   # id seen in a lobby / presence reply
##   f.save(FriendList.DEFAULT_PATH)

const DEFAULT_PATH := "user://friends.cfg"
const MAX_FRIENDS: int = 50

## One friend. `id` is "" until seen; `tag` is "" when added by plain name.
class Friend:
	extends RefCounted
	var name: String = ""
	var tag: String = ""
	var id: String = ""

	## "Name#TAG" when the tag is known, else the name.
	func label() -> String:
		var t := tag if tag != "" else PlayerProfile.tag_of(id)
		return "%s#%s" % [name, t] if t != "" else name

var friends: Array[Friend] = []


## Loads `path` (missing file = empty list). Invalid rows are skipped.
static func load_from(path: String) -> FriendList:
	var out := FriendList.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	for section in cfg.get_sections():
		var f := Friend.new()
		f.name = str(cfg.get_value(section, "name", ""))
		f.tag = str(cfg.get_value(section, "tag", "")).to_upper()
		f.id = str(cfg.get_value(section, "id", ""))
		if PlayerProfile.validate_name(f.name) != PlayerProfile.NameError.OK:
			continue
		if f.id != "" and not PlayerProfile.is_hex_id(f.id):
			f.id = ""
		if out.friends.size() < MAX_FRIENDS:
			out.friends.append(f)
	return out


## Writes the list to `path`. Returns the ConfigFile error code.
func save(path: String) -> int:
	var cfg := ConfigFile.new()
	for i in friends.size():
		var s := "friend_%d" % i
		cfg.set_value(s, "name", friends[i].name)
		cfg.set_value(s, "tag", friends[i].tag)
		cfg.set_value(s, "id", friends[i].id)
	return cfg.save(path)


## Parses "Name" or "Name#TAG" into [name, tag]; empty Array when invalid.
static func parse(text: String) -> Array:
	var t := text.strip_edges()
	var tag := ""
	var at := t.rfind("#")
	if at >= 0:
		tag = t.substr(at + 1).to_upper()
		t = t.substr(0, at)
		if tag.length() != 4 or not tag.is_valid_hex_number():
			return []
	if PlayerProfile.validate_name(t) != PlayerProfile.NameError.OK:
		return []
	return [t, tag]


## Adds a friend by "Name" / "Name#TAG". Returns the new entry, or null when
## the text is invalid, the list is full or the friend is already listed.
func add(text: String) -> Friend:
	var p := parse(text)
	if p.is_empty() or friends.size() >= MAX_FRIENDS:
		return null
	for f in friends:
		if f.name.to_lower() == String(p[0]).to_lower() and (f.tag == p[1] or p[1] == "" or f.tag == ""):
			return null
	var f := Friend.new()
	f.name = p[0]
	f.tag = p[1]
	friends.append(f)
	return f


## Adds a friend whose id is already known (e.g. "+" on a lobby row).
func add_known(id: String, name: String) -> Friend:
	if not PlayerProfile.is_hex_id(id) or find_id(id) != null or friends.size() >= MAX_FRIENDS:
		return null
	if PlayerProfile.validate_name(name) != PlayerProfile.NameError.OK:
		return null
	var f := Friend.new()
	f.name = name
	f.tag = PlayerProfile.tag_of(id)
	f.id = id
	friends.append(f)
	return f


func remove(f: Friend) -> void:
	friends.erase(f)


func find_id(id: String) -> Friend:
	for f in friends:
		if f.id == id:
			return f
	return null


## A player `id` named `name` was seen: fills the id of an unresolved friend
## that matches (name case-insensitive, and the tag when one was given), and
## refreshes the stored name of a resolved one. Returns true when it changed.
func resolve(id: String, name: String) -> bool:
	if not PlayerProfile.is_hex_id(id):
		return false
	var known := find_id(id)
	if known != null:
		if known.name != name and PlayerProfile.validate_name(name) == PlayerProfile.NameError.OK:
			known.name = name
			return true
		return false
	for f in friends:
		if f.id == "" and f.name.to_lower() == name.to_lower() \
				and (f.tag == "" or f.tag == PlayerProfile.tag_of(id)):
			f.id = id
			f.name = name
			f.tag = PlayerProfile.tag_of(id)
			return true
	return false


## Ids of resolved friends.
func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in friends:
		if f.id != "":
			out.append(f.id)
	return out


## Friends without an id yet.
func unresolved() -> Array[Friend]:
	var out: Array[Friend] = []
	for f in friends:
		if f.id == "":
			out.append(f)
	return out
