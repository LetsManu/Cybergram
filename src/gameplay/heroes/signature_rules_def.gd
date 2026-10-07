class_name SignatureRulesDef
extends Resource
## Numbers of the 14 Signature passives (design/gdd/items-and-armory.md §3.5.3,
## §7 "Passive values"). Every value SignaturePassives reads lives here;
## assets/data/economy/signature_rules.tres is the tuned copy (shared() loads it
## once, defaults = the GDD values). All [TUNE], safe range ±40% each (§7).

## Default tuned rules.
const RULES_PATH := "res://assets/data/economy/signature_rules.tres"

@export_group("Weapon Signatures")
## Kindle (Ember Heart): share of the magazine (Mech, from nothing) or of the
## pool (Mana) refilled on a hero kill or assist.
@export_range(0.0, 1.0, 0.01) var kindle_refill_frac: float = 0.30
## Overdrive Loop (Tempest Heart): continuous fire for this long, shots at most
## `overdrive_gap_s` apart, turns it on.
@export_range(0.0, 10.0, 0.05) var overdrive_after_s: float = 1.5
@export_range(0.05, 5.0, 0.05) var overdrive_gap_s: float = 0.9
## Spread bloom multiplier while on (-40%).
@export_range(0.0, 1.0, 0.01) var overdrive_bloom_mult: float = 0.60
## Pellet weapons (Ironmaw) shrink the cone instead (-10%).
@export_range(0.0, 1.0, 0.01) var overdrive_pellet_cone_mult: float = 0.90
## True Line (Prism Eye): rounds refunded per head hit on a hero (Mech; Mana
## refunds the shot's mana cost).
@export_range(0, 10) var true_line_rounds: int = 1
## Long Reach (Longsight Lens): slow and duration of hits on a hero beyond the
## weapon's base falloff_start (refresh, no stack; shared slow cap).
@export_range(0.0, 1.0, 0.01) var long_reach_slow: float = 0.10
@export_range(0.0, 10.0, 0.1) var long_reach_s: float = 1.0
## Rend (Breaker Bore): gear-armor points per hit, duration (refresh) and maximum.
@export_range(0.0, 0.2, 0.005) var rend_per_hit: float = 0.02
@export_range(0.0, 20.0, 0.1) var rend_s: float = 4.0
@export_range(0.0, 0.2, 0.005) var rend_max: float = 0.08
## Deep Reserve (Reservoir Frame): Mech Supply Cache refill multiplier (+50%).
@export_range(1.0, 5.0, 0.05) var deep_reserve_refill_mult: float = 1.5
## Cold Start (Flux Coil): idle time without firing, Mana regen multiplier.
@export_range(0.0, 30.0, 0.1) var cold_start_idle_s: float = 3.0
@export_range(1.0, 5.0, 0.05) var cold_start_regen_mult: float = 2.0
## Planted (Anchor Frame): time standing still (or crouched), the horizontal
## speed (m/s) below which the hero counts as still, recoil and knockback / pull
## multipliers.
@export_range(0.0, 10.0, 0.05) var planted_still_s: float = 0.5
@export_range(0.0, 2.0, 0.01) var planted_speed_eps: float = 0.1
@export_range(0.0, 1.0, 0.01) var planted_recoil_mult: float = 0.75
@export_range(0.0, 1.0, 0.01) var planted_knockback_mult: float = 0.50

@export_group("Gear Signatures")
## Brace (Bastion Plate): share of max HP lost to weapon damage within
## `brace_window_s` that triggers it; the DR it grants, how long, cooldown.
@export_range(0.0, 1.0, 0.01) var brace_threshold: float = 0.35
@export_range(0.1, 10.0, 0.1) var brace_window_s: float = 2.0
@export_range(0.0, 0.7, 0.01) var brace_dr: float = 0.15
@export_range(0.0, 10.0, 0.1) var brace_s: float = 2.5
@export_range(0.0, 120.0, 0.5) var brace_cooldown_s: float = 20.0
## Grounding (Null Veil): Root, Stun, Silence and Slow durations multiplier (-25%).
@export_range(0.0, 1.0, 0.01) var grounding_mult: float = 0.75
## Regrowth (Vigil Core): delay without damage, then max-HP share per second.
@export_range(0.0, 30.0, 0.5) var regrowth_delay_s: float = 5.0
@export_range(0.0, 0.2, 0.005) var regrowth_frac_s: float = 0.02
## Lattice (Barrier Lattice): overshield points, refill delay without damage.
@export_range(0.0, 500.0, 1.0) var lattice_shield: float = 80.0
@export_range(0.0, 30.0, 0.5) var lattice_delay_s: float = 6.0
## Resonant Cast (Cadence Crown): share of each basic skill's remaining cooldown
## cut when the ultimate is cast.
@export_range(0.0, 1.0, 0.01) var resonant_cut: float = 0.25
## Siegebreaker (Breaker Sigil): weapon damage bonus vs Ward Generators and an
## Exposed Uplink (target-class modifier, not an ammo effect).
@export_range(0.0, 1.0, 0.01) var siege_bonus: float = 0.15


static var _shared: SignatureRulesDef


## The shared tuned rules (loaded once; GDD defaults if the file is missing).
static func shared() -> SignatureRulesDef:
	if _shared == null:
		_shared = load(RULES_PATH) as SignatureRulesDef if ResourceLoader.exists(RULES_PATH) else null
		if _shared == null:
			_shared = SignatureRulesDef.new()
	return _shared
