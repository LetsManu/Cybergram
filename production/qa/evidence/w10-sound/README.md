# W10-W5 synthesized sound archetypes

Listen-only WAVs of every archetype in `SfxSynth` (22.05 kHz mono, normalized to 0.9 peak).
Regenerate: `godot --headless --path . -s tools/audio/export_sfx_wavs.gd` (also prints synth time, ~60 ms).
Weapon / skill / UI mapping is data: `assets/data/audio/sfx_bank.tres`; weapons pick a voice via `WeaponDef.sfx_voice`.

- Gunshots: gun_rifle (Breakline AR-7), gun_smg (Whisperfang burst), gun_heavy (Ironmaw), gun_zap (Halo Repeater), gun_tack (Tackhammer), gun_glitch (Glitchcaster), gun_thread (Threadcaster)
- Skills: explosion, slam, whoosh (dash/throw), shield_up, heal_chime, buff_up, hack_glitch, shimmer (stealth), trap_click, deploy, ult_rise (ultimates)
- beam_loop: heal beam hum (loops while the beam FX is alive)
- UI (UI bus): ui_buy, ui_sell, ui_levelup, ui_fork, ui_hover, ui_click
