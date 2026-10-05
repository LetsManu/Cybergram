# Release notes format

One file per release: `production/releases/vX.Y.Z.md`. The update feed carries
the newest one, and `launcher/tools/sync_notes.sh` bundles all of them into the
launcher for the NOTES page history (so old notes work offline).

Layout:

- `# Cybergram vX.Y.Z: Title` on the first line, then a short intro.
- `## Section` per topic, with `-` bullets (nesting by 2 spaces), `**bold**`,
  `` `code` ``, links and `![alt](image.png)` (images go in
  `launcher/assets/notes/`).
- A release that is not final says DRAFT in its first lines.

## Per-hero changes ("Changes for your heroes")

The launcher shows each player the notes for the heroes they play most. To
make that work, list balance and kit changes per hero under one section:

```
## Hero changes

### Ryker
- Frag Grenade damage 90 -> 80.

### Vesper
- Conductor squad bonus +2 -> +3.
```

Rules:

- The section title is exactly `## Hero changes`.
- Each hero is a `### Name` heading: the first name (`Ryker`), the full name
  (`Ryker Vance`) or the id stem (`ryker_vance`), case does not matter.
- Heroes with no changes are simply left out; the launcher then says so.
- The launcher matches against the local play history (see
  `src/core/profile/hero_play_history.gd`). That history never leaves the PC.
