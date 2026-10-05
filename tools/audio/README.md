# tools/audio — Cybergram sound generators (W21-A1)

Every shipped sound in `assets/audio/` is rendered offline by the scripts in
this folder. They are our own work and released as CC0 (see
`assets/audio/README.md`).

| File | Does |
|---|---|
| `dsp.py` | DSP primitives (oscillators, filters, FM, Karplus-Strong, reverb, loudness, true peak, OGG writer) |
| `sfx_recipes.py` | One recipe per sound family and the seven hero palettes |
| `catalog.py` | **The event table**: every file (folder, stem, variants, loudness target) and every event (bus, 2D/3D, distance, priority, voices, cooldown, owner filter, fallback) |
| `render_sfx.py` | Renders catalog files to `assets/audio/<folder>/<stem>_NN.ogg` |
| `render_music.py` | Renders the music loops (stems) and stingers to `assets/audio/music/` |
| `write_event_defs.py` | Writes one `AudioEventDef` .tres per event to `assets/data/audio/events/` and the index `assets/data/audio/audio_events.tres` |
| `measure_loudness.py` | Measures every rendered file with ffmpeg `ebur128` (independent of `dsp.py`), prints a per-category table |
| `export_sfx_wavs.gd` | (W10) dumps the in-code SfxSynth fallback archetypes as WAV |

## Regenerate

From the repo root:

```bash
pip install -r tools/audio/requirements.txt   # numpy, scipy, pyloudnorm (pinned)
python3 tools/audio/render_sfx.py             # ~30 s, 3 processes
python3 tools/audio/render_music.py           # ~60 s
python3 tools/audio/write_event_defs.py
python3 tools/audio/measure_loudness.py > production/qa/evidence/w21-a1/loudness.tsv
$GODOT --headless --path . --import           # creates the .ogg.import files
```

`--only <substring>` re-renders a subset (`render_sfx.py --only weapons_rifle`,
`render_music.py --only match_late`).

Tools used: Python 3.11, the pinned packages above, ffmpeg 6.1.1 with
libvorbis (Ubuntu 24.04 build).

## Determinism

* Every file's RNG is `numpy.random.default_rng(crc32(stem) + variant)`; music
  states seed from `crc32(state)`. No wall-clock or global RNG is used.
* The PCM is bit-identical between runs on the same numpy / scipy versions.
  The OGG bytes are written with ffmpeg `+bitexact` and no metadata, so the
  same ffmpeg / libvorbis build gives identical files. A different libvorbis
  may change bytes (not the sound); re-measure loudness after such an upgrade.

## Loudness targets (audio direction spec §5)

Files are normalised to their in-game level so event `volume_db` stays near 0:
one-shots by momentary maximum (400 ms, K-weighted), beds / music / announcer
stingers by integrated loudness; ceiling -1 dBTP (4x oversampled).
Weapon shots -14 LUFS M, footsteps -20 (enemy at 5 m: unit 5 m, -4 dB = -24),
UI about -20, ambient beds -30 I (bus 0.8 = about -32), music stem sum -20 I
(bus 0.7 = about -23; in match a further -6 dB), announcer -16 I.

## Layer 2 (recordings)

Drop CC0 recordings with the same names (`<stem>_01.ogg`, `_02.ogg`, ...) into
`assets/audio/<folder>/`, delete the rendered variants they replace, record the
licence in `assets/audio/README.md`, and run the import. No code change: the
loader probes the convention names first.
