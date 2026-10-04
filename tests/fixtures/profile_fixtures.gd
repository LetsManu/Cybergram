class_name ProfileFixtures
extends RefCounted
## Deterministic player profiles for lobby / profile tests (no randomness).


## 32-hex id made of byte `n` repeated ("0a0a...").
static func id(n: int) -> String:
	return ("%02x" % (n & 0xFF)).repeat(16)


## A valid wire profile {id, key, name, emblem, accent} for player `n`.
static func wire(n: int, name: String) -> Dictionary:
	return {"id": id(n), "key": id(n + 100), "name": name, "emblem": n % PlayerProfile.EMBLEM_COUNT,
		"accent": n % PlayerProfile.ACCENTS.size()}


## A PlayerProfile object for player `n`.
static func profile(n: int, name: String) -> PlayerProfile:
	var p := PlayerProfile.new()
	var w := wire(n, name)
	p.id = w.id
	p.key = w.key
	p.name = name
	p.emblem = w.emblem
	p.accent = w.accent
	return p
