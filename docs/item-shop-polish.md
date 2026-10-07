# Armory panel: visual polish pass

Screenshots of the Armory panel at 1280x720 and 1920x1080, what each one
showed, what was fixed and what is still open. Every screenshot listed here was
looked at. Evidence lives in `production/qa/evidence/armory-builds/`.

How to capture (docs/armory.md "Screenshots"):

```
RESOLUTION=1920x1080 tools/ci/capture_scene.sh "" out.png 120 --map slice --debug-armory
```

Presets: `--debug-armory` (Recommended), `--debug-armory-catalog` (All tab,
expert detail), `--debug-armory-builds` (My builds, sample build in memory).
The hero is Vesper on the slice map at 0:01 with 2,550 Lumen and a few mounts
bought by the debug setup.

## Screens

| Screen | 720p | 1080p |
|---|---|---|
| Recommended | `recommended-vesper-720.png` | `recommended-vesper-1080.png` |
| Catalog (All, expert detail) | `catalog-expert-vesper-720.png` | `catalog-expert-vesper-1080.png` |
| My builds | `my-builds-vesper-720.png` | `my-builds-vesper-1080.png` |

## Fixed

| Where | Problem seen | Fix |
|---|---|---|
| Tabs | With the ninth tab (My builds) the labels ran off the panel, then into each other | Tab font and padding shrink to fit the row |
| Search box | The sort hint sat on top of the tabs | Sort hint moved inside the search box |
| Build strip | 20 steps squeezed into thin overlapping slices | Shows only the steps that fit, with the next step in view and a "steps a-b of n" hint |
| Buy / sell buttons | Sell was 30 px wide and its label spilled out | Buy 58% / sell the rest; labels shrink, then wrap |
| Key hints (My builds) | Wrapped onto a second line under the buttons | One full-width line; "Saved on this PC only" moved under the build title |
| Item cards | Tier pips ran into the reason line; reasons cut down to "T.." | Pips moved to the price line; a reason shorter than 8 characters is skipped |
| Detail title / kind line | Long names ran past the panel edge | Shrink to fit, then cut with ".." |
| Weapon HUD (bottom right) | "BARREL" ran into its tier pips | All four slots stack the label above the pips when one does not fit |
| Warnings | A broken "!" glyph | Diamond bullet |
| Detail tier table, 720p | EFFECT and PRICE headers and values drawn on top of each other | PRICE column shows only when it clears the effect text; Tier I's upgrade cell then carries the price |
| Detail pane, 720p | "Undo refunds ..." line ran into the buy / sell buttons | Lines below the tier table stop at the pane bottom (the value is on the button) |
| Detail pane | One-tier items said their effect twice | The effect line is skipped when the description already says it |

## Open (not fixed in this pass)

| Where | Observation | Why left |
|---|---|---|
| Cards, 720p | Long names and reasons are cut ("Reinforced Co..", "Tougher Wardlings hold y..") | The full text is in the detail pane; a second card line would cost a row of cards |
| Build strip | Tier numerals under the chip icons are small at 720p | Readable at 1080p; a bigger numeral needs taller chips |
| Catalog key hints, 720p | Two lines | Fits; one line would need a smaller font than the HUD minimum |
| Panel top | The match timer's "Mids unlock" line shows behind the Lumen label | The HUD timer draws under the panel; moving the panel down costs a row |
| Grid | Empty band under the third card row when the strip is short | Rows are whole cards; a partial row would scroll |
| My builds | No text field to rename a build or edit notes | Not built yet (docs/armory.md "Known gaps") |
