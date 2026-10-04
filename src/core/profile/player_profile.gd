class_name PlayerProfile
extends RefCounted
## The local player's identity (design/ux/lobby-and-social.md §2.1): a display
## name, a code-drawn emblem, an accent colour, a stable random id and a
## private key, saved in user://profile.cfg. There are no accounts: the id is
## generated once on first launch; the key only ever goes to the server, which
## refuses a second key for the same id (so a copied id cannot take a slot).
## Name validation is shared by client and server (the server re-validates).
##
## Example:
##   var p := PlayerProfile.load_or_null(PlayerProfile.DEFAULT_PATH)
##   if p == null: p = PlayerProfile.create("Neo", 3, 1)
##   p.save(PlayerProfile.DEFAULT_PATH)
##   p.display_id()  # "Neo#1A2B"

const DEFAULT_PATH := "user://profile.cfg"
const NAME_MIN: int = 3
const NAME_MAX: int = 16
## Bytes in an id / key (hex strings are twice as long).
const ID_BYTES: int = 16
## Code-drawn emblems (EmblemIcon draws index 0..EMBLEM_COUNT-1).
const EMBLEM_COUNT: int = 12
## Accent colour presets, readable on the dark panels (art bible §4.2 family).
const ACCENTS: Array[Color] = [
	Color("#2E86FF"), Color("#00C2D1"), Color("#4CE38A"), Color("#B6F23A"), Color("#FFC93C"),
	Color("#FF8A1F"), Color("#FF4A3D"), Color("#FF3B7A"), Color("#B07CFF"), Color("#EAF3FF"),
]

## Validation results of validate_name().
enum NameError { OK, TOO_SHORT, TOO_LONG, BAD_CHAR, BAD_SPACE }

## 32 hex chars, lower case.
var id: String = ""
## 32 hex chars, private.
var key: String = ""
var name: String = ""
var emblem: int = 0
var accent: int = 0


## A fresh profile with a new random id and key. `name_` must be valid.
static func create(name_: String, emblem_: int, accent_: int) -> PlayerProfile:
	var p := PlayerProfile.new()
	p.id = random_hex(ID_BYTES)
	p.key = random_hex(ID_BYTES)
	p.name = name_.strip_edges()
	p.emblem = clampi(emblem_, 0, EMBLEM_COUNT - 1)
	p.accent = clampi(accent_, 0, ACCENTS.size() - 1)
	return p


## A valid generated profile ("Pilot-1A2B") for automated runs (--auto-ready).
static func generated() -> PlayerProfile:
	var p := create("Pilot", randi() % EMBLEM_COUNT, randi() % ACCENTS.size())
	p.name = "Pilot-" + p.tag()
	return p


## Loads `path`; null when missing or invalid (first launch).
static func load_or_null(path: String) -> PlayerProfile:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return null
	var p := PlayerProfile.new()
	p.id = str(cfg.get_value("profile", "id", ""))
	p.key = str(cfg.get_value("profile", "key", ""))
	p.name = str(cfg.get_value("profile", "name", ""))
	p.emblem = int(cfg.get_value("profile", "emblem", 0))
	p.accent = int(cfg.get_value("profile", "accent", 0))
	return p if p.is_valid() else null


## Writes the profile to `path`. Returns the ConfigFile error code.
func save(path: String) -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "id", id)
	cfg.set_value("profile", "key", key)
	cfg.set_value("profile", "name", name)
	cfg.set_value("profile", "emblem", emblem)
	cfg.set_value("profile", "accent", accent)
	return cfg.save(path)


## The fields the lobby protocol sends ({id, key, name, emblem, accent}).
func to_wire() -> Dictionary:
	return {"id": id, "key": key, "name": name, "emblem": emblem, "accent": accent}


## True when every field is in range.
func is_valid() -> bool:
	return is_hex_id(id) and is_hex_id(key) and validate_name(name) == NameError.OK \
		and emblem >= 0 and emblem < EMBLEM_COUNT and accent >= 0 and accent < ACCENTS.size()


## 4-char tag shown after the name (Riot-ID style "Name#TAG").
func tag() -> String:
	return tag_of(id)


## "Name#TAG".
func display_id() -> String:
	return "%s#%s" % [name, tag()]


## Accent colour of this profile.
func accent_color() -> Color:
	return accent_of(accent)


## Tag of an id (first 4 hex digits, upper case).
static func tag_of(id_: String) -> String:
	return id_.substr(0, 4).to_upper()


## Accent preset colour (out of range: the first preset).
static func accent_of(index: int) -> Color:
	return ACCENTS[index] if index >= 0 and index < ACCENTS.size() else ACCENTS[0]


## Checks a display name: NAME_MIN..NAME_MAX characters of A-Z a-z 0-9 _ - .
## and single inner spaces (no leading / trailing / double spaces).
static func validate_name(n: String) -> NameError:
	if n.length() < NAME_MIN:
		return NameError.TOO_SHORT
	if n.length() > NAME_MAX:
		return NameError.TOO_LONG
	if n.begins_with(" ") or n.ends_with(" ") or n.contains("  "):
		return NameError.BAD_SPACE
	for i in n.length():
		var c := n.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) \
			or c == 95 or c == 45 or c == 46 or c == 32
		if not ok:
			return NameError.BAD_CHAR
	return NameError.OK


## True for a 32-char lower-case hex string.
static func is_hex_id(s: String) -> bool:
	if s.length() != ID_BYTES * 2:
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


## `n` cryptographically random bytes as lower-case hex.
static func random_hex(n: int) -> String:
	return Crypto.new().generate_random_bytes(n).hex_encode()
