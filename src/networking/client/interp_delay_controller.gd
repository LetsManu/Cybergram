class_name InterpDelayController
extends RefCounted
## W16-NET adaptive interpolation delay. Picks how many ticks behind the
## newest snapshot remote entities render, from the measured snapshot arrival
## jitter (ClientNetStats.jitter_p95_ms) and loss:
##   need = 1.5 ticks + p95 lateness (+1 tick when loss >= loss_extra_tick_pct)
##   target = clamp(ceil(need), min_ticks, max_ticks)       (2..5 = 66..166 ms)
## Hysteresis: the target rises at once (a late snapshot would otherwise make
## remotes extrapolate and stutter) but only falls one tick after the need has
## stayed below (target - 1 - margin) for decrease_hold_s. The applied delay
## (`delay`, fractional) slews towards the target at slew_ticks_per_s, so a
## change stretches time slightly instead of jumping.
##
## Example:
##   var c := InterpDelayController.from_config(net)
##   c.update(stats.jitter_p95_ms(), stats.loss_pct(), delta)
##   var render_tick := server_tick_estimate - c.delay

var min_ticks: int = 2
var max_ticks: int = 5
var tick_ms: float = 1000.0 / 30.0
var decrease_hold_s: float = 2.0
var slew_ticks_per_s: float = 2.0
var loss_extra_tick_pct: float = 5.0
## Need must be this far (ticks) below target - 1 before a decrease starts.
var margin_ticks: float = 0.2
## Off: delay stays at the configured fixed value.
var enabled: bool = true

## Target delay in whole ticks.
var target: int = 3
## Applied delay in ticks (slews towards target).
var delay: float = 3.0
## Last computed need in ticks (diagnostics).
var need: float = 0.0
var _below_s: float = 0.0


static func from_config(net: NetConfig) -> InterpDelayController:
	var c := InterpDelayController.new()
	c.min_ticks = net.interp_delay_min_ticks
	c.max_ticks = maxi(net.interp_delay_max_ticks, net.interp_delay_min_ticks)
	c.tick_ms = 1000.0 / net.tick_rate_hz
	c.decrease_hold_s = net.interp_decrease_hold_s
	c.slew_ticks_per_s = net.interp_slew_ticks_per_s
	c.loss_extra_tick_pct = net.interp_loss_extra_tick_pct
	c.enabled = net.adaptive_interp
	c.target = clampi(net.interp_delay_ticks, c.min_ticks, c.max_ticks) if c.enabled else net.interp_delay_ticks
	c.delay = c.target
	return c


## One frame: `jitter_p95_ms` / `loss_pct` from ClientNetStats, `dt` seconds.
func update(jitter_p95_ms: float, loss_pct: float, dt: float) -> void:
	if not enabled:
		return
	need = 1.5 + jitter_p95_ms / tick_ms + (1.0 if loss_pct >= loss_extra_tick_pct else 0.0)
	var want := clampi(ceili(need - 1e-6), min_ticks, max_ticks)
	if want > target:
		target = want
		_below_s = 0.0
	elif target > min_ticks and need < target - 1 - margin_ticks:
		_below_s += dt
		if _below_s >= decrease_hold_s:
			target -= 1
			_below_s = 0.0
	else:
		_below_s = 0.0
	var step := slew_ticks_per_s * dt
	delay = move_toward(delay, float(target), step)


## Applied delay in milliseconds.
func delay_ms() -> float:
	return delay * tick_ms
