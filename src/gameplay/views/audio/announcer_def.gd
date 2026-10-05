class_name AnnouncerDef
extends Resource
## W21-A1: announcer lines and queue rules (assets/data/audio/announcer.tres;
## design/audio/audio-events.md §Announcer).

## Line id -> {"priority": int, "repeat_s": float (optional, else default_repeat_s),
## "text": HUD_ key for the toast, "stinger": AudioEventDef id, "voice": AudioEventDef id}.
@export var lines: Dictionary = {}
## Pending line id -> the line that replaces it when it arrives (double -> triple).
@export var upgrades: Dictionary = {}
@export_range(1, 8) var queue_max: int = 3
## A queued line older than this is dropped.
@export var max_wait_s: float = 4.0
## Silence between two lines.
@export var gap_s: float = 0.4
@export var default_repeat_s: float = 8.0
## Only lines at or above this priority interrupt a playing line.
@export var interrupt_priority: int = 90
## Toast display time and the fallback line length when no stream length is known.
@export var toast_s: float = 2.2
@export var line_s: float = 1.2
## Callout rules (MatchCallouts): multi-kill window, shutdown streak, "30 s to start".
@export var multikill_window_s: float = 10.0
@export_range(2, 10) var shutdown_streak: int = 3
@export var countdown_line_s: float = 30.0
## Uplink "under attack": integrity loss (fraction of max) inside one window.
@export var uplink_drop_frac: float = 0.005
