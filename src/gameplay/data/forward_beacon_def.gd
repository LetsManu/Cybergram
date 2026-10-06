class_name ForwardBeaconDef
extends Resource
## Presentation tuning of the Forward Beacon spawn pad (ForwardBeaconView;
## docs/assets/forward_beacon.md). Gameplay (attunement 15 s, threat radius
## 25 m) is EconomyRulesDef's; this is only how it looks and sounds.

const DEFAULT_PATH := "res://assets/data/world/forward_beacon.tres"

@export_group("Hard-light mast and banner")
## Mast height above the pad (m) and its radius.
@export_range(3.0, 20.0, 0.5) var mast_height_m: float = 9.0
@export_range(0.02, 0.3, 0.01) var mast_radius_m: float = 0.07
## Banner size (width, height) hanging from the mast top.
@export var banner_size_m: Vector2 = Vector2(1.5, 3.4)
@export_group("Halo")
## Spawn halo radius on the ground (m); the pad is placed so the halo lies on level floor.
@export_range(1.0, 6.0, 0.1) var halo_radius_m: float = 2.0
@export_group("States")
## Overall hard-light strength while attuning / ready / under attack.
@export_range(0.0, 1.0, 0.05) var attuning_strength: float = 0.6
@export_range(0.0, 1.0, 0.05) var ready_strength: float = 1.0
@export_range(0.0, 1.0, 0.05) var threat_strength: float = 0.7
## Under-attack blink rate (Hz, at most 3: photosensitivity guideline).
@export_range(0.5, 3.0, 0.1) var strobe_hz: float = 2.0
## Fade time between states (s).
@export_range(0.05, 2.0, 0.05) var fade_s: float = 0.4
@export_group("Light")
## Pad light energy at full strength and its range (m).
@export_range(0.0, 4.0, 0.05) var light_energy: float = 1.2
@export_range(1.0, 20.0, 0.5) var light_range_m: float = 7.0


## The shipped def (defaults when the file is missing).
static func shared() -> ForwardBeaconDef:
	if ResourceLoader.exists(DEFAULT_PATH):
		return load(DEFAULT_PATH) as ForwardBeaconDef
	return ForwardBeaconDef.new()
