class_name ComfortRulesDef
extends Resource
## Tuning for the Comfort options (W16-COMFORT, owner request: options against
## motion sickness). Data-driven so a designer can retune without code
## (assets/data/app/comfort_rules.tres). The player's own choices live in
## GameSettings' [comfort] section; this resource holds the rules around them.

const DEFAULT_PATH := "res://assets/data/app/comfort_rules.tres"

@export_group("Smooth corrections")
## A reconciliation error below this (metres) is blended into the camera and
## rendered position; at or above it (teleport, respawn, knockback) the view snaps.
@export_range(0.1, 10.0, 0.05) var smooth_threshold_m: float = 1.5
## Seconds over which a blended error fades out (about 95% gone at this time).
@export_range(0.02, 1.0, 0.01) var smooth_time_s: float = 0.1

@export_group("Comfort vignette")
## Horizontal speed (m/s) where the vignette starts and where it is at full
## strength. Sprint is 8.1 m/s, so ordinary running never triggers it.
@export_range(1.0, 40.0, 0.1) var vignette_speed_start_mps: float = 8.5
@export_range(1.0, 40.0, 0.1) var vignette_speed_full_mps: float = 14.0
## |vertical speed| (m/s) where it starts / is full (jump pads, long falls).
## A normal jump takes off at 6.5 m/s.
@export_range(1.0, 40.0, 0.1) var vignette_vertical_start_mps: float = 10.0
@export_range(1.0, 40.0, 0.1) var vignette_vertical_full_mps: float = 18.0
## Level while dashing / sliding or under knockback (0..1 of the setting).
@export_range(0.0, 1.0, 0.05) var vignette_forced_level: float = 1.0
## Fade in / out times (seconds).
@export_range(0.01, 2.0, 0.01) var vignette_fade_in_s: float = 0.12
@export_range(0.01, 3.0, 0.01) var vignette_fade_out_s: float = 0.45
## Edge darkness at setting 100% and full level (0..1 alpha), and the radius
## (fraction of the half-diagonal) where the darkening begins.
@export_range(0.0, 1.0, 0.05) var vignette_max_alpha: float = 0.85
@export_range(0.1, 1.0, 0.05) var vignette_inner_radius: float = 0.45

@export_group("Screen effects")
## Alpha of the calm, static alert frame that replaces pulsing damage / low-HP
## feedback when screen effects are reduced (gameplay info is kept, motion is not).
@export_range(0.0, 1.0, 0.05) var static_alert_alpha: float = 0.5

@export_group("Damage feedback")
## Damage direction indicator: seconds it fades over (it follows the view).
@export_range(0.2, 4.0, 0.05) var indicator_fade_s: float = 1.2
## Alpha floor at 0% screen effects: the indicator is gameplay-critical, so it
## stays visible, just static (a plain fade, no pulse).
@export_range(0.2, 1.0, 0.05) var indicator_min_alpha: float = 0.7
## A hit of this fraction of max HP (or more) counts as a "big hit" (strength 1).
@export_range(0.05, 1.0, 0.05) var big_hit_hp_frac: float = 0.25
## Smallest indicator strength (tiny hits still show).
@export_range(0.0, 1.0, 0.05) var indicator_min_strength: float = 0.25
## Ring radius as a fraction of the viewport height, arc half-width (degrees,
## small / big hit) and line width (px, small / big hit).
@export_range(0.05, 0.5, 0.01) var indicator_ring_radius: float = 0.2
@export_range(5.0, 90.0, 1.0) var indicator_arc_half_deg_min: float = 14.0
@export_range(5.0, 90.0, 1.0) var indicator_arc_half_deg_max: float = 30.0
@export_range(1.0, 30.0, 0.5) var indicator_width_min_px: float = 5.0
@export_range(1.0, 30.0, 0.5) var indicator_width_max_px: float = 11.0
## Seconds of the initial pulse (extra brightness / width) at full effects.
@export_range(0.02, 1.0, 0.01) var indicator_pulse_s: float = 0.18
## A shot's impact within this distance (m) of the own body counts as the hit
## that did the damage (attacker = the shooter); otherwise it is non-directional.
@export_range(0.3, 6.0, 0.1) var attribution_radius_m: float = 2.2
## Seconds the client waits for a SHOT event after an HP drop, and keeps shots.
@export_range(0.0, 0.5, 0.01) var attribution_delay_s: float = 0.08
@export_range(0.1, 2.0, 0.05) var shot_memory_s: float = 0.6
## Damage vignette: edge alpha at a big hit and full effects, fade seconds,
## inner radius; and the thin static tint used at 0% effects (alpha, inner radius).
@export_range(0.0, 1.0, 0.05) var damage_vignette_max_alpha: float = 0.6
@export_range(0.1, 3.0, 0.05) var damage_vignette_fade_s: float = 0.8
@export_range(0.1, 1.0, 0.05) var damage_vignette_inner: float = 0.4
@export_range(0.0, 1.0, 0.05) var damage_static_alpha: float = 0.15
@export_range(0.1, 1.0, 0.05) var damage_static_inner: float = 0.88

@export_group("Damage attribution")
## Which source did the damage (DamageAttribution): a mana bolt that ended within
## this distance (m) of the body; an enemy Wardling in combat within melee range;
## an enemy ability's area / line / projectile within `attribution_fx_margin_m`
## of the body; the line half-width; and the farthest caster of an instant skill.
@export_range(0.3, 6.0, 0.1) var bolt_hit_radius_m: float = 1.6
@export_range(0.5, 10.0, 0.1) var melee_range_m: float = 3.4
@export_range(0.0, 4.0, 0.1) var attribution_fx_margin_m: float = 1.0
@export_range(0.3, 4.0, 0.1) var attribution_line_halfwidth_m: float = 1.6
@export_range(0.5, 6.0, 0.1) var attribution_projectile_radius_m: float = 2.5
@export_range(5.0, 100.0, 1.0) var cast_max_range_m: float = 45.0

@export_group("Viewmodel")
## FOV the viewmodel offsets were authored at; other FOVs scale the offsets by
## tan(fov/2) / tan(ref/2) so the gun keeps its screen footprint.
@export_range(60.0, 120.0, 1.0) var viewmodel_ref_fov_deg: float = 90.0
## Where the camera-recoil kick that the camera does not show is spent on the
## viewmodel: pitch/yaw tilt gain and distance (m) the gun sits from the eye.
@export_range(0.0, 3.0, 0.05) var viewmodel_kick_gain: float = 1.0
@export_range(0.1, 1.0, 0.05) var viewmodel_kick_arm_m: float = 0.3

@export_group("Motion comfort preset")
@export_range(0.0, 1.0, 0.05) var preset_camera_recoil: float = 0.25
@export var preset_weapon_bob: bool = false
@export_range(0.0, 1.0, 0.05) var preset_fx_intensity: float = 0.4
@export var preset_center_dot: bool = true
@export var preset_smooth_corrections: bool = true
@export_range(0.0, 1.0, 0.05) var preset_vignette: float = 0.5
@export var preset_reduce_motion: bool = true
@export_range(70.0, 120.0, 1.0) var preset_fov_min_deg: float = 100.0


## Loads the shipped rules (defaults when the file is missing).
static func load_default() -> ComfortRulesDef:
	var d := load(DEFAULT_PATH) as ComfortRulesDef
	return d if d != null else ComfortRulesDef.new()
