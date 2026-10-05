class_name RecoveryCode
extends RefCounted
## One-time account recovery codes (W21-N1, PRIVACY.md): Crockford base32
## groups, e.g. "7KQ2M-X4D9P-0RTB8-HV3NC" (4 x 5 characters = 100 bit from
## the CSPRNG). Only a PBKDF2 hash of the canonical form is stored
## (AccountService, record in the account's `password.recovery`). Typing is
## forgiving: case, spaces and dashes do not matter, and the look-alikes
## I / L read as 1 and O as 0 (Crockford's rules). Group count and length
## come from AuthRulesDef.
##
## Example:
##   var code := RecoveryCode.generate(rules)         # shown to the player once
##   var canon := RecoveryCode.normalize(typed, rules)  # "" when it cannot be a code

## Crockford base32 alphabet (no I, L, O, U).
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


## A fresh code, formatted in dash-separated groups. 32 divides 256, so
## `byte & 31` is an unbiased pick.
static func generate(rules: AuthRulesDef) -> String:
	var n := rules.recovery_groups * rules.recovery_group_len
	var raw := Crypto.new().generate_random_bytes(n)
	var s := ""
	for i in n:
		s += ALPHABET[raw[i] & 31]
	return format(s, rules)


## Canonical form (upper case, no separators, look-alikes mapped) or "" when
## the text cannot be a code of this length.
static func normalize(text: String, rules: AuthRulesDef) -> String:
	var out := ""
	for ch: String in text.to_upper():
		var c := ch
		if c == "-" or c == " " or c == "\t":
			continue
		if c == "I" or c == "L":
			c = "1"
		elif c == "O":
			c = "0"
		if not ALPHABET.contains(c):
			return ""
		out += c
	return out if out.length() == rules.recovery_groups * rules.recovery_group_len else ""


## "ABCDEFGHJK..." -> "ABCDE-FGHJK-...".
static func format(canonical: String, rules: AuthRulesDef) -> String:
	var parts := PackedStringArray()
	var g := rules.recovery_group_len
	for i in range(0, canonical.length(), g):
		parts.append(canonical.substr(i, g))
	return "-".join(parts)


## Entropy of a code in bits (tests, docs).
static func bits(rules: AuthRulesDef) -> int:
	return rules.recovery_groups * rules.recovery_group_len * 5


## The stored record for a code hash (no plaintext).
static func record(hash: PackedByteArray, salt: PackedByteArray, iterations: int, now_unix: int) -> Dictionary:
	return {"algo": "pbkdf2-hmac-sha256", "hash": hash.hex_encode(), "salt": salt.hex_encode(),
		"iterations": iterations, "created_at": now_unix}
