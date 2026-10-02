# Godot 4.7 Verification Notes (architecture.md §15)

- **Engine**: Godot v4.7.stable.official.5b4e0cb0f, Linux x86_64, `physics/3d/physics_engine = "Jolt Physics"` (printed at runtime)
- **Date**: 2026-10-02
- **Author**: gameplay-programmer (E2/E3, autonomous)
- **Retained tests**: `tests/integration/engine/engine_world_isolation_test.gd`, `tests/integration/engine/engine_replay_test.gd`

## Item 2: `SubViewport.own_world_3d` isolation. PASS (no fallback needed)

What I ran: a `SubViewport` with `own_world_3d = true` and `render_target_update_mode = UPDATE_DISABLED` (2x2 px), added to the gdUnit4 test tree.

| Check | Result |
|---|---|
| `vp.find_world_3d() != root.find_world_3d()` | different World3D |
| `.space` RIDs differ | yes |
| `.navigation_map` RIDs differ, sub map valid | yes |
| Ray in the main space through a floor that exists only in the sub world | miss |
| Same ray in the sub space | hit |
| `RigidBody3D` in the never-rendered sub world falls over 10 physics frames | yes, so the space steps |
| `CharacterBody3D` in the sub world passes through main-world floor height and lands on its own floor 3 m lower (`is_on_floor()` true) | yes |

Gotcha: `Viewport.world_3d` returns `null` for the root and for `own_world_3d` viewports. Use `find_world_3d()`.

Conclusion: OFFLINE mode can host `ServerWorld` in a SubViewport. ADR-0002 Alternative 4 (child-process server) is not needed. Item 4 (navigation `velocity_computed` timing) was not exercised; that belongs to E8.

## Item 3: replaying `move_and_slide()` several times per frame under Jolt. PASS, with one caveat

What I ran: a capsule `CharacterBody3D` over a flat floor, a 20° ramp and a 0.4 m step, with gravity, two jumps and a direction change. The live run makes one `move_and_slide()` per physics frame for 90 frames, recording position, velocity and `is_on_floor()`.

| Replay | Result |
|---|---|
| Full replay of all 90 frames inside one frame from the same start | **bit-exact** (0.0 m difference, `is_on_floor()` identical every frame) |
| Partial replay from a mid-run state, restoring only `global_position` and `velocity` (probe at 30 Hz) | drift up to **6.6 mm** (restore at frame 40, on the ramp); `is_on_floor()` matched |
| Partial replay with a "contact priming" step: set the position, do one tiny `move_and_slide()` toward the recorded contact state (down 0.01 m/s if grounded, else up), then restore the position and velocity | exact at 8 of 9 restore points; **45 µm** at the restore right after a sharp direction change |

Cause: `CharacterBody3D` keeps hidden contact state between calls (`was_on_floor`, floor/wall normals, last motion). Script cannot set it, so restoring position and velocity does not fully restore the body.

Consequence for the netcode: reconciliation replay must prime contact state (`HeroMotor.restore()` does this). The remaining error (≤ 45 µm measured; the test bounds it at 1 mm) is 400x below `NetConfig.reconcile_epsilon_m` (0.02 m), so replay cannot trigger a correction loop. The `body_test_motion` fallback motor (risk R2) is not needed.

`move_and_slide()` advances by `get_physics_process_delta_time()`, not by a caller-supplied dt. `HeroMotor` scales the velocity by `dt / physics_dt` around the call, so the motor honours its `dt` argument (an exact 1.0 at runtime, where the physics rate is set to `tick_rate_hz`).

## Not verified here

Items 1 (ENet raw packet API, M2), 4, 5, 6 and 8 (export preset) are not covered. Item 7 (gdUnit4 on 4.7) passes in practice: the suite runs under `tools/ci/run_tests.sh`.
