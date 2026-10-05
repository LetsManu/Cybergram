# assets/audio — Cybergram sounds and music

All audio is OGG Vorbis, 44.1 kHz: mono for positional (3D) sounds, stereo
for music, ambient beds, UI and announcer stingers.

## Naming

`[category]_[context]_[name]_[variant].ogg`, variants `_01`, `_02`, ...

```
weapons/              weapons_<voice>_shot_NN, _tail_NN, _reload_{start,mag_out,done}_NN,
                      weapons_mech_dry / _lowammo, weapons_mana_{burnout,lowammo,regen},
                      weapons_impact_<standard|piercing|sunder|mana>, weapons_core_layer_t<1-3>,
                      weapons_combat_<hit|headshot|kill|assist|death|damage|heartbeat>
abilities/<hero>/     abilities_<hero>_<skill>_{cast,impact,loop}_NN; abilities/shared/ explosion
footsteps/            footsteps_<concrete|metal|grate|water>_step_NN, footsteps_body_{jump,land_light,land_heavy},
                      footsteps_water_{splash,wade}
world/                world_wardling_{spawn,attack,death}, world_objective_{capture,contest,lost,uplink_alarm,sudden_death}
ui/                   ui_menu_*, ui_economy_*, ui_flow_*
voice/                voice_stinger_<triumph|alert|streak|neutral> (now);
                      voice_announcer_<line>_01 (recorded lines, later — see below)
music/                music_<state>_<pad|bass|drums|lead>_01 (match states), music_<menu|pick>_mix_01,
                      music_stinger_<victory|defeat|phase|final|sudden_death>_01
ambient/              ambient_<base|lane|jungle|water>_bed_01
```

Which event plays which file, on which bus, with what priority and range is in
`assets/data/audio/events/**` (one `AudioEventDef` per event) and documented
in `design/audio/audio-events.md`.

## Replacing a sound (layer 2)

Put a CC0 recording with the same name in the same folder (any number of
variants `_01` .. `_08`), remove the rendered files it replaces, add a row to
the licence table below, and run `$GODOT --headless --path . --import`. No code
change: the loader probes these names first and falls back to the in-code
synthesizer only when no file exists.

Announcer voice lines are expected as `voice/voice_announcer_<line>_01.ogg`
with `<line>` one of: victory, defeat, sudden_death, uplink_under_attack,
hardpoint_lost, hardpoint_captured, shutdown, triple_kill, double_kill,
first_blood, thirty_seconds. They are silent until the files exist (the synth
stinger and the HUD toast always play). Only original or CC0 voice work; no
text-to-speech imitation of real people.

## Licence and attribution

Only CC0 (public-domain dedication) audio is accepted in this folder.

| Files | Source | Author | Licence |
|---|---|---|---|
| everything currently in `assets/audio/**` (319 files) | rendered by `tools/audio/render_sfx.py` and `tools/audio/render_music.py` from `tools/audio/catalog.py` / `sfx_recipes.py` (see `tools/audio/README.md`) | Cybergram project | CC0 1.0 |

Add one row per imported recording or pack: files, source URL, author, licence
(must be CC0 1.0), date retrieved.
