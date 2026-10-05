class_name TicketKeyRing
extends RefCounted
## HMAC keys for match join tickets (W17), addressed by a short key id so keys
## can rotate: the front signs with the key stamped on the match process, and an
## old key is removed only after every process that uses it has ended.
##
## Sources, first match wins (see from_env):
## - CYBERGRAM_TICKET_KEYS_FILE: a file with one "kid:hex" per line;
## - CYBERGRAM_TICKET_KEYS: "kid:hex,kid:hex";
## - none: one random in-memory key (fine for a single host; a restart
##   invalidates outstanding tickets, which live for seconds anyway).
## The first key listed is the active one. Keys are at least 32 bytes.
## Key bytes are never printed: _to_string() shows key ids only.

const ENV_KEYS := "CYBERGRAM_TICKET_KEYS"
const ENV_KEYS_FILE := "CYBERGRAM_TICKET_KEYS_FILE"
const MIN_KEY_BYTES := 32
const MAX_FILE_BYTES := 16384

var active_kid: String = ""
## True when no key was configured and a random one was generated.
var ephemeral: bool = false
var _keys: Dictionary = {}  # kid -> PackedByteArray


## True for a valid key id: 1-16 chars of [a-z0-9_-].
static func valid_kid(kid: String) -> bool:
	if kid.length() < 1 or kid.length() > 16:
		return false
	for i in kid.length():
		var c := kid.unicode_at(i)
		var ok := (c >= 0x61 and c <= 0x7A) or (c >= 0x30 and c <= 0x39) or c == 0x5F or c == 0x2D
		if not ok:
			return false
	return true


## Adds `key` under `kid`. The first key added becomes active, or any key with
## `make_active`. False (nothing added) for a bad id or a short key.
func add_key(kid: String, key: PackedByteArray, make_active: bool = false) -> bool:
	if not valid_kid(kid) or key.size() < MIN_KEY_BYTES:
		return false
	_keys[kid] = key
	if active_kid == "" or make_active:
		active_kid = kid
	return true


## Removes a key (rotation finished). The active key cannot be removed.
func remove_key(kid: String) -> bool:
	if kid == active_kid:
		return false
	return _keys.erase(kid)


func has_key(kid: String) -> bool:
	return _keys.has(kid)


## The key bytes of `kid` (empty when unknown).
func key_for(kid: String) -> PackedByteArray:
	return _keys.get(kid, PackedByteArray())


func kids() -> PackedStringArray:
	return PackedStringArray(_keys.keys())


## Parses "kid:hex" entries separated by commas or newlines. Blank lines and
## lines starting with '#' are skipped. Returns an empty ring on any bad entry
## (a half-loaded key set is worse than a clear failure).
static func parse_spec(text: String) -> TicketKeyRing:
	var ring := TicketKeyRing.new()
	for raw in text.replace("\r", "").replace(",", "\n").split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var parts := line.split(":", true, 1)
		var hx := parts[1].strip_edges().to_lower() if parts.size() == 2 else ""
		if hx == "" or hx.length() % 2 != 0 or not hx.is_valid_hex_number():
			return TicketKeyRing.new()
		if not ring.add_key(parts[0].strip_edges().to_lower(), hx.hex_decode()):
			return TicketKeyRing.new()
	return ring


## A ring with one fresh random key under `kid`.
static func generate(kid: String = "e1") -> TicketKeyRing:
	var ring := TicketKeyRing.new()
	ring.add_key(kid, Crypto.new().generate_random_bytes(MIN_KEY_BYTES))
	ring.ephemeral = true
	return ring


## Loads from `env` (name -> value; pass {} to read the process environment).
## Falls back to a random key when nothing is configured. An unreadable or
## invalid configured source also falls back, and `error` says why.
static func from_env(env: Dictionary = {}) -> TicketKeyRing:
	var file_path := str(env.get(ENV_KEYS_FILE, OS.get_environment(ENV_KEYS_FILE) if env.is_empty() else ""))
	var spec := str(env.get(ENV_KEYS, OS.get_environment(ENV_KEYS) if env.is_empty() else ""))
	if file_path != "":
		var f := FileAccess.open(file_path, FileAccess.READ)
		spec = f.get_buffer(mini(f.get_length(), MAX_FILE_BYTES)).get_string_from_utf8() if f != null else ""
	if spec.strip_edges() != "":
		var ring := parse_spec(spec)
		if ring.active_kid != "":
			return ring
		push_error("[hosting] ticket keys are configured but invalid; using a random key")
	return generate()


func _to_string() -> String:
	return "TicketKeyRing(active=%s, kids=%s%s)" % [active_kid, ",".join(kids()), ", ephemeral" if ephemeral else ""]
