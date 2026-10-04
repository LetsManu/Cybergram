class_name NameFilterDef
extends Resource
## Offensive / impersonating display-name filter (data:
## assets/data/social/name_filter.tres). A name is refused when, after
## folding case and common digit look-alikes (0->o, 1->i, 3->e, 4->a, 5->s,
## 7->t) and dropping separators, it contains any `blocked` entry. Checked by
## the profile screen (hint) and by the server (authoritative).
##
## Example:
##   var f := load("res://assets/data/social/name_filter.tres") as NameFilterDef
##   f.allows("Neo")  # true

## Lower-case fragments, letters only.
@export var blocked: PackedStringArray = PackedStringArray()


## True when `name` contains no blocked fragment.
func allows(name: String) -> bool:
	var n := fold(name)
	for b in blocked:
		var f := fold(b)
		if f != "" and n.contains(f):
			return false
	return true


## Lower case, digit look-alikes mapped to letters, everything but a-z dropped.
static func fold(s: String) -> String:
	var map := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t"}
	var out := ""
	for ch in s.to_lower():
		var c: String = map.get(ch, ch)
		if c >= "a" and c <= "z":
			out += c
	return out
