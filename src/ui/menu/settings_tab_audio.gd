class_name SettingsTabAudio
extends SettingsTab
## Audio tab: Master, Effects, UI, Music, Voice (announcer) and Ambient bus
## volumes, plus night mode and reduced music (W21-A1, design/audio/audio-events.md).


func build() -> void:
	section(tr("HUD_SET_TAB_AUDIO"))
	slider(tr("HUD_SET_VOL_MASTER"), 0.0, 1.0, 0.05, s.master_volume, "%.0f%%",
		func(v: float) -> void: s.master_volume = v, 100.0)
	slider(tr("HUD_SET_VOL_EFFECTS"), 0.0, 1.0, 0.05, s.effects_volume, "%.0f%%",
		func(v: float) -> void: s.effects_volume = v, 100.0)
	slider(tr("HUD_SET_VOL_MUSIC"), 0.0, 1.0, 0.05, s.music_volume, "%.0f%%",
		func(v: float) -> void: s.music_volume = v, 100.0)
	slider(tr("HUD_SET_VOL_VOICE"), 0.0, 1.0, 0.05, s.voice_volume, "%.0f%%",
		func(v: float) -> void: s.voice_volume = v, 100.0)
	slider(tr("HUD_SET_VOL_AMBIENT"), 0.0, 1.0, 0.05, s.ambient_volume, "%.0f%%",
		func(v: float) -> void: s.ambient_volume = v, 100.0)
	slider(tr("HUD_SET_VOL_UI"), 0.0, 1.0, 0.05, s.ui_volume, "%.0f%%",
		func(v: float) -> void: s.ui_volume = v, 100.0)
	section(tr("HUD_SET_AUDIO_MIX"))
	check(tr("HUD_SET_NIGHT_MODE"), s.night_mode, func(v: bool) -> void: s.night_mode = v)
	check(tr("HUD_SET_REDUCE_MUSIC"), s.reduce_music, func(v: bool) -> void: s.reduce_music = v)
