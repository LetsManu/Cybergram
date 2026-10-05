# Polish sprint, 2026-10-05 (60 min, 17:14–18:14 UTC)

- **Branch:** `claude/polish-sprint`, based on the integration branch at 11211e9 (v0.13.1 candidate, new HUD). Not merged, released or deployed.
- **Owner brief:** bindings-aware hints, then four player questions:
  - Where do I go next?
  - What is my squad doing?
  - Why can't I act right now?
  - What does my progress give me?
- **Constraints:** the screen centre stays clear for aiming, and the existing UI kit, focus states, UiSfx and reduce motion are kept.

**Kinds of evidence**
- **Code:** checked by reading the code.
- **Test:** an automated test. *watched failing* means it was run against the unfixed code first and failed.
- **Screen:** a real game frame captured in a headless bots match, in `production/qa/evidence/polish-sprint/`.
- **Not played:** no human played through it with a mouse or pad.

## Current state (from code, `project.godot`, `project.yaml`)

- **Versions:** game 0.13.1 (protocol 17); Godot 4.7, Forward+, Jolt.
- **Released and built:**
  - matchmaking front, PLAY flow, draft and ranks
  - the rebuilt Shardline Front with jungle and city life
  - the v0.12 HUD (variant D)
- **Not yet merged:** the W16 hero rebuilds and the first-person viewmodels, which are finished on their branches.
- **README:** it partly describes an older state (M1 slice), so this report goes by the code.

## Fixes

| # | Finding | Kind | Fix | Proof |
|---|---|---|---|---|
| 1 | `[F] ARMORY` and `DRY - [R] RELOAD` showed F and R after rebinding Interact or Reload. The key letters were baked into the strings. | Bindings | The strings take `%s`, filled by `HudContext.prompt()` through the existing `key_label()`, which gives the current key or the pad glyph. | Test, watched failing (`hud_key_prompts_test`) |
| 2 | The Armory panel opened only on a physical **F** or pad Y, while the prompt names Interact. A rebound Interact did nothing. | Bindings | The panel toggles on the `interact` action (keyboard and pad). `open_shop` (B) still opens it. | Test, watched failing on the old physical-F logic |
| 3 | The Fork choice on a pad showed `[1]` / `[2]`. Pads have no fork binding; input picks the fork with the skill 1 / 2 buttons (LB / RB). | Bindings, gamepad | `HudContext.fork_key()` mirrors the rule in `PlayerInputSource`. | Test (shows the old label is "1") |
| 4 | Pressing a skill that was cooling or locked gave no feedback at all, so the press was silently swallowed. | Why can't I act | The slot flashes an amber rim for 0.45 s. A cooldown shows NOT READY; a locked skill turns its level gate amber. Quick-spend (Alt), menus and death don't count as a press. Nothing is drawn at the screen centre. | Test (logic); code (input edges) |
| 5 | The squad headline always showed the first pip's command (FOLLOW / ATTACK …), even while every Wardling was walking back or dissolving. | Squad | The headline reads the replicated state. It shows DISSOLVING or RETURNING in amber, otherwise the command of the first live member. | Test |
| 6 | Sudden Death kept the objective card, task cue and squad strip on screen; hud.md §12 says they are hidden. At match end the whole combat HUD stayed behind the banner. | Where next / clarity | A pure `HudRoot.context_visibility()` with tests. SD keeps the front strip, which shows the alive pips and ring timer. The end screen shows only the result. | Test; screen (`sd-720.png`, `end-720.png`) |
| 7 | `+N SP` didn't say how to spend the points during play. The death screen did. | Progress | A key chip with the bound quick-spend modifier sits next to the SP badge (Alt, or the pad glyph). It is drawn only where it fits. | Screen (`normal-1080.png`) |
| 8 | At 720p the Lumen gain `+24` ran into `RES 63%`; the gap was a fixed 30 px. | Layout 720p | The gap reserves the width of a 2–3 digit gain. | Screen (`normal-720.png`, `normal-1080.png`) |

**Already correct (checked, nothing changed):**
- **Skill bar keys:** they already used `key_label()`, so they show the current binding or pad glyph, refreshed on rebind and on device switch (code).
- **Med-Pack and reload chips:** the same (code).
- **Fork keys on keyboard:** they already followed the fork bindings (code and test).
- **Squad pips:** they come from replicated state, with F/H/A/C, `!`, R and D letters, never colour only (code).
- **Remake vote:** it uses fixed F1/F2 and the pad D-pad. The label says exactly that, and the keys are not rebindable actions (code).
- **Armory panel internals:** the arrows, Q/E tabs and 1–3 are panel keys and are labelled as such (code).

## Found, not fixed (next steps)

1. **720p death screen.** The row "+1 SP · Skill points can be spent while dead · [Alt]" and the spawn cards overlap the skill bar's level labels (`dead-720.png`). This was already there before the sprint. The death screen needs a short-height layout that moves the SP row above the spawn cards, or hides the skill bar's gate labels while dead.
2. **720p SP key chip.** It is hidden because the vitals panel is too narrow. At 720p the brass `+` corner chips on the skill slots remain the only in-combat cue.
3. **Where do I go next, far from objectives.** The objective card appears only within `tracker_range_m` of a hardpoint. Away from objectives, the lane strip and the world plates are the guide. A compact "next objective" line (Dota-style context) would close that gap.
4. **Blocked reasons not covered:** mana or Burnout for skills (skills have no cost; Burnout is shown on the weapon panel), and silence or stun (no such state is sent to the client).
5. **1080p capture.** The movie writer records at the project viewport size. True 1080p frames need a temporary `override.cfg` (viewport 1920×1080), which was used here and then deleted.

## Regression (last 15 min)

- **Test suite:** `tools/ci/run_tests.sh` ran 1159 cases with 0 failures and 0 orphans. `check_deps` passed.
- **Online and matchmaking:** `launcher/tests/online_e2e.sh` PASS and `tools/ci/matchmaking_e2e.sh` PASS, both against a local test server: front, warm pool, two scripted clients, rated result, crash void.
- **Screenshots:** `normal-720`, `normal-1080`, `sd-720`, `end-720` and `dead-720` were captured and reviewed.
- **Not played:**
  - a real gamepad (pad paths are covered by tests through the binding layer only)
  - changing keys in the settings menu by hand
  - the full menu → match → death → end → new match loop with input
  - reduce motion on screen (the deny pulse changes colour only and has no motion; the existing reduce-motion paths are unchanged)
