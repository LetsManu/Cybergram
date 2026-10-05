# Cybergram UI Kit: Art Direction (v0.8, W12-K1)

> Status: implemented by `src/ui/theme/ui_kit.gd` + `assets/ui/ui_kit_tokens.tres`.
> Shared by the game menus, the lobby and the launcher. Owner of tokens: UI kit.

## 1. Intent

The client shell should feel like a premium MOBA client (League client first,
Valorant / Apex second): a persistent top bar, one dominant glowing PLAY call
to action, a big hero banner, layered dark panels over a slowly moving
background, and short, crisp motion. The identity stays Cybergram's own:
neon-violet "leyfall" light on night ink, a restrained brass secondary, a
moving perspective grid with a skyline glow. No Riot assets, names, icons or
sounds are used; we copy *patterns*, not art.

## 2. Tokens (one palette for game and launcher)

All values live in `assets/ui/ui_kit_tokens.tres` (`UiKitTokens` resource).
The launcher loads the same file; never hard-code these colours.

| Token | Value | Use |
|---|---|---|
| `bg_deep` | `#05060D` | window clear colour, behind the shader |
| `bg` | `#0A0D1A` | background shader base |
| `panel` | `#0E1224` @ 0.86 | cards, sidebars |
| `panel_raised` | `#151A33` @ 0.94 | headers, hovered rows, modals |
| `panel_sunken` | `#060813` @ 0.92 | inputs, tracks |
| `line` | `#C9D4E3` @ 0.18 | 1 px frames |
| `line_strong` | `#C9D4E3` @ 0.38 | dividers, frames of focused groups |
| `accent` | `#8E5CFF` (leyfall violet) | primary actions, selection, glow |
| `accent_hi` | `#B794FF` | hover / pressed text, focus ring |
| `gold` | `#D9B26A` (brass) | secondary accent: frames of hero cards, header ticks, the PLAY rim |
| `cyan` | `#3FD8F2` | info, links, "online" network state |
| `text` | `#EAF3FF` | body |
| `text_dim` | `#A8B2C7` | secondary text |
| `text_off` | `#6B7286` | disabled, hints |
| `ok` / `warn` / `danger` | `#4CE38A` / `#FFB534` / `#FF4A3D` | status (same as HudPalette) |

Rule: violet is the only "do this" colour; brass is decoration and rank; cyan
is information. One filled violet element per screen (the PLAY button or the
screen's primary action).

## 3. Type scale

Display face: **Orbitron** (SIL OFL 1.1, `assets/fonts/orbitron/`, licence
beside it), used only for titles, nav tabs and the PLAY button, uppercase, with
+1..+4 px letter spacing. Body: Godot's default font (Noto Sans).

| Role | Size | Face |
|---|---|---|
| `display` | 44 | Orbitron Bold, spacing +4 |
| `title` | 26 | Orbitron SemiBold, +2 |
| `heading` | 18 | Orbitron Medium, +1 (card header strips) |
| `nav` | 14 | Orbitron Medium, +2 |
| `body` | 15 | default |
| `small` | 13 | default |
| `caption` | 11 | default, uppercase for labels |

## 4. Spacing, radii, frames

- Spacing scale: 4, 8, 12, 16, 24, 32 (`space_xs`..`space_xxl`).
- Radii: 2 px on cards and inputs (sharp, technical), 0 on the top bar.
- Primary buttons use **clipped corners** (top-left and bottom-right bevel,
  `bevel` = 10 px), drawn by `UiKit.BevelBox` (a StyleBox subclass).
- Frames: 1 px `line`; a focused / selected item gets a 1 px `accent` frame
  plus a soft outer glow (shadow in accent @ 0.35, size 8).
- Card header strip: 32 px `panel_raised` band, 2 px brass tick on the left,
  heading text in Orbitron.

## 5. Motion

| Token | ms | Use |
|---|---|---|
| `motion_fast` | 120 | hover / press scale and glow |
| `motion_base` | 200 | panel and tab transitions, toasts in |
| `motion_slow` | 320 | screen transitions (fade + 24 px slide) |

Easing: `TRANS_CUBIC` / `EASE_OUT` in, `EASE_IN` out. Background shader and
hero turntable are slow ambient loops (grid 0.05 cells/s, turntable 12 deg/s).

**Reduced motion** (`GameSettings.reduce_motion`, Video tab): every kit tween
is skipped (the end state is applied at once), the background shader freezes
its time uniform, and the turntable stops. `UiKit.tween()` is the single gate.

## 6. Sound

Hover and click go through `UiSfx.attach()` (UI bus). Kit buttons attach it
automatically; never play UI sounds directly.

## 7. Input

Every kit control is focusable; the focus ring is a 2 px `accent_hi` frame
(visible on gamepad / keyboard focus only, Godot draws `focus` on keyboard
focus). Tabs: LB / RB and Ctrl+Tab. Back: Esc / B.

## 8. LoL reference (patterns to follow)

The League of Legends client is the main reference. Follow the patterns
below; keep Cybergram's palette, font and cyberpunk identity.

### 8.1 Client shell (main menu, implemented)

- **Persistent top bar** (64 px, `panel` with a 1 px line at the bottom):
  - Far left: a big glowing **PLAY** button (beveled, violet fill, brass
    rim, pulsing outer glow unless reduce motion). It opens a **mode-select
    panel** (Online / Vs Bots / Practice Range / Tutorial) with mode cards and
    a **CONFIRM** button, like PLAY then queue select.
  - Centre: text nav tabs **HOME, HEROES, PROFILE, SETTINGS** (Orbitron, the
    active one gets a violet underline and brighter text).
  - Right: the account chip (emblem inside a status ring: violet = account,
    dim = guest / signed out; clicking opens the profile), then small square
    quick buttons (settings, quit).
- **Social sidebar** on the right edge: header with online count, search /
  add field, friends grouped **Online / In lobby / In match / Offline**, a
  status dot per row; collapsible to a 48 px icon strip (toggle at its top).
- **Home tab**: a large hero banner (the 3D hero showcase in one SubViewport,
  slow turntable, hero name, role and weapon, arrows + badge strip to choose
  the hero) with **news tiles** ("What's new") below it.
- **Frame style ("Hextech"-like, our own)**: thin 1 px accent frames, beveled
  corners on primary buttons, brass secondary accent, subtle hover glow,
  150-250 ms motion, layered dark panels over the animated background.

### 8.2 Lobby (for the lobby agent): champ-select layout

- Top centre: phase title ("Choose your hero", "Lock in!") in `title`, and a
  countdown bar under it (violet fill draining; turns `warn` under 10 s).
- Left column: your team's slots: hero portrait (HeroBadge), name, status
  line (Picking... / Locked) with a brass frame when locked.
- Right column: the enemy team, mirrored.
- Centre: the hero grid with a search field and role filter icons; the
  selected hero's 3D model large behind the grid (reuse `HeroShowcase`).
- Bottom centre: a big **LOCK IN** button (`UiKit.button(..., "primary")`,
  beveled).
- Bottom left: team chat (`UiKit.card()` with header).
- After everyone locks: a short finalization phase (3-5 s), a lock-in flash
  per player (accent glow tween on the slot, skipped under reduce motion) and
  a UiSfx click per lock.

### 8.3 Launcher (for the launcher agent): Riot-client style

- Left sidebar (72-88 px) with the game tile (logo mark, selected state in
  violet).
- Big key art: reuse the menu background shader (`UiKit.background()`), plus
  a hero render if available.
- A persistent **PLAY panel bottom-left**; the update progress bar lives
  inside the PLAY button (fill drawn behind the label; label shows
  "UPDATE 42%").
- News cards (`UiKit.card()`), account chip top-right (same chip as the menu).
- Load the tokens from `res://assets/ui/ui_kit_tokens.tres`; the launcher's
  old cyan / pink accents go away (cyan only for information).

## 9. Kit API (summary)

Doc comments in `src/ui/theme/ui_kit.gd` are the reference. All static.

| Call | What |
|---|---|
| `UiKit.tokens()` | `UiKitTokens` from `res://assets/ui/ui_kit_tokens.tres` (colours, type scale, spacing, motion) |
| `UiKit.theme()` | cached Theme: Button, OptionButton, CheckBox / CheckButton (toggle), HSlider, LineEdit, PopupMenu, scrollbars, tooltip, ProgressBar. Set it on your root Control |
| `UiKit.label(text, role, color, align)` | roles `display / title / heading / nav / body / small / caption` (first four use Orbitron) |
| `UiKit.button(text, cb, kind, height)` | kinds `primary / secondary / ghost / danger / play`; hover tween, press state, focus ring, UiSfx |
| `UiKit.style_button(b, kind)` / `swatch_button(b, colour)` | style an existing button / a colour swatch |
| `UiKit.icon_button(glyph, cb, tooltip, side)` | square ghost button with a `UiIcon` glyph (gear, close, minus, left/right/up/down, friends, play, check, ring, target) |
| `UiKit.tab_bar(labels, cb, selected, nav)` / `tab_button(text, nav)` | underline tabs (ButtonGroup) |
| `UiKit.line_edit(placeholder, max)` | sunken input |
| `UiKit.card(title, pad)` | `UiCard`: panel + header strip; content in `.body`, actions in `.header_right` |
| `UiKit.screen_frame(panel, title, subtitle, pad)` | turns a PanelContainer into a kit screen (header strip + padded body column, returned) |
| `UiKit.avatar(icon, ring_colour, side)` | emblem inside a status ring (account chip) |
| `UiKit.toast(parent, text, kind, seconds)` | top-centre toast lane; kinds info / ok / warn / danger |
| `UiKit.modal(parent, title, body, ok, on_ok, cancel, on_cancel, danger)` | `UiModal` dialog, Esc / B cancel |
| `UiKit.transition_in(node)` / `transition_out(node, then)` | fade (+ slide outside containers) |
| `UiKit.animate(owner, target, prop, value, ms)` | the one tween gate; null + instant under reduce motion |
| `UiKit.background()` / `refresh_background(bg)` | the animated shader background (frozen under reduce motion) |
| `UiKit.reduce_motion()` | `GameSettings.reduce_motion` (tests: `UiKit.force_reduce_motion`) |

Reusable menu pieces: `HeroShowcase` (one-SubViewport 3D hero stage +
badges, `src/ui/menu/hero_showcase.gd`), `FriendsPanel` (grouped,
collapsible sidebar). `MenuStyle` and `SettingsTheme` remain as thin shims
over the kit for older call sites (lobby); new code calls `UiKit`.
