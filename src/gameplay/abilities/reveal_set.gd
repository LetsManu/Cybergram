class_name RevealSet
extends RefCounted
## W11-M1 Reveal (heroes.md §4: Snare Charge, Alarm Net, Coil Mastery...). A hero
## revealed TO a team is visible to that team through walls until a tick.
## Server-only state; per-recipient visibility is written into each peer's
## snapshot (SkillStatusBits.REVEALED), never into the shared entity state.

## key (net_id, viewer_team) -> expiry tick
var _until: Dictionary = {}


## Reveals hero `net_id` to `viewer_team` for `ticks` from `tick` (extends, never shortens).
func reveal(net_id: int, viewer_team: int, ticks: int, tick: int) -> void:
	if ticks <= 0:
		return
	var k := Vector2i(net_id, viewer_team)
	_until[k] = maxi(int(_until.get(k, 0)), tick + ticks)


func is_revealed(net_id: int, viewer_team: int, tick: int) -> bool:
	return tick < int(_until.get(Vector2i(net_id, viewer_team), 0))


## Net ids currently revealed to `viewer_team`.
func revealed_ids(viewer_team: int, tick: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in _until:
		if k.y == viewer_team and tick < int(_until[k]):
			out.append(k.x)
	return out


func clear_hero(net_id: int) -> void:
	for k in _until.keys():
		if k.x == net_id:
			_until.erase(k)


func step(tick: int) -> void:
	for k in _until.keys():
		if tick >= int(_until[k]):
			_until.erase(k)
