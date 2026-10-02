class_name MovementDef
extends Resource
## Hero locomotion tunables shared by HeroMotor on server and client.
## Implements design/gdd/heroes.md §2 (move speeds, Sprint x1.35, Crouch x0.5).
## Values marked PLACEHOLDER are not specified by the GDD yet and are tuning
## starting points for the game-designer.

## Base run speed in m/s. heroes.md §2 table (6.0 = Vesper/Liora/Juniper/Hex).
## Per-hero speed moves to HeroDef.base_stats once StatBlock lands (E4/E10).
@export_range(0.0, 20.0, 0.1) var base_move_speed: float = 6.0
## heroes.md §2: "Sprint = x1.35 move speed". Forward input only, not while crouched.
@export_range(1.0, 3.0, 0.01) var sprint_multiplier: float = 1.35
## heroes.md §2: "Crouch = x0.5".
@export_range(0.1, 1.0, 0.01) var crouch_multiplier: float = 0.5
## PLACEHOLDER. Ground acceleration toward the wish velocity (m/s^2).
@export_range(0.0, 200.0, 0.5) var ground_acceleration: float = 60.0
## PLACEHOLDER. Air acceleration toward the wish velocity (m/s^2).
@export_range(0.0, 200.0, 0.5) var air_acceleration: float = 12.0
## PLACEHOLDER. Gravity (m/s^2).
@export_range(0.0, 100.0, 0.1) var gravity: float = 20.0
## PLACEHOLDER. Take-off speed; apex = v^2 / 2g (6.5 m/s, g 20 -> ~1.06 m).
@export_range(0.0, 30.0, 0.1) var jump_velocity: float = 6.5
## PLACEHOLDER. Seconds after leaving a ledge during which a jump still works.
@export_range(0.0, 1.0, 0.01) var coyote_time_s: float = 0.1
## PLACEHOLDER. Seconds an early jump press is remembered before landing.
@export_range(0.0, 1.0, 0.01) var jump_buffer_s: float = 0.1
## Collision capsule radius (m).
@export_range(0.1, 2.0, 0.01) var capsule_radius: float = 0.4
## Standing capsule height (m).
@export_range(0.5, 4.0, 0.01) var stand_height: float = 1.8
## Crouched capsule height (m).
@export_range(0.5, 4.0, 0.01) var crouch_height: float = 1.2
## Eye height above the feet when standing / crouched (m).
@export_range(0.1, 4.0, 0.01) var stand_eye_height: float = 1.62
@export_range(0.1, 4.0, 0.01) var crouch_eye_height: float = 1.05
## Steepest walkable slope (degrees).
@export_range(0.0, 89.0, 0.5) var max_floor_angle_deg: float = 46.0
## Downward snap distance that keeps the hero glued to ramps and ledges (m).
@export_range(0.0, 2.0, 0.01) var floor_snap_length: float = 0.3
## Pitch clamp (degrees). The server clamps InputCommand.pitch to the same limit.
@export_range(0.0, 90.0, 0.5) var max_pitch_deg: float = 89.0
