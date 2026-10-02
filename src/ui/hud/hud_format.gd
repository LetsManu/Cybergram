class_name HudFormat
extends RefCounted
## Pure text formatters for the HUD (unit-tested in tests/unit/ui). Numbers
## only; words go through tr() at the call site.


## Match clock "m:ss" (negative clamps to 0:00; minutes are not capped).
static func clock(seconds: float) -> String:
	var s := maxi(floori(seconds), 0)
	return "%d:%02d" % [s / 60, s % 60]


## Integer with thousands separators: 1240 -> "1,240", -5000 -> "-5,000".
static func thousands(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


## Cooldown label (hud.md §4.4): "" when ready, tenths at ≤ 3 s, whole seconds
## (rounded up) above.
static func cooldown(seconds: float) -> String:
	if seconds <= 0.0:
		return ""
	if seconds <= 3.0:
		return "%.1f" % (ceilf(seconds * 10.0 - 0.0001) / 10.0)
	return str(ceili(seconds))


## Whole percent of `frac`, rounded up so a nearly-dead bar never reads 0%
## (only exactly 0 does); clamped to 0..100.
static func percent(frac: float) -> int:
	if frac <= 0.0:
		return 0
	return clampi(ceili(frac * 100.0 - 0.0001), 1, 100)


## "212 / 279".
static func pair(a: int, b: int) -> String:
	return "%d / %d" % [a, b]


## Whole seconds left, rounded up (respawn timer, Death hold).
static func seconds_up(seconds: float) -> int:
	return maxi(ceili(seconds - 0.0001), 0)


## Kills / deaths column "7 / 3".
static func kd(kills: int, deaths: int) -> String:
	return "%d / %d" % [kills, deaths]


## Shortens `name` to at most `max_chars` (kill feed: names truncate, icons never).
static func truncate(name: String, max_chars: int) -> String:
	if max_chars <= 1 or name.length() <= max_chars:
		return name
	return name.substr(0, max_chars - 1) + "…"
