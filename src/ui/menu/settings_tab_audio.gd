class_name SettingsTabAudio
extends SettingsTab
## Audio tab: Master, Effects and UI bus volumes.


func build() -> void:
	section(tr("HUD_SET_TAB_AUDIO"))
	slider(tr("HUD_SET_VOL_MASTER"), 0.0, 1.0, 0.05, s.master_volume, "%.0f%%",
		func(v: float) -> void: s.master_volume = v, 100.0)
	slider(tr("HUD_SET_VOL_EFFECTS"), 0.0, 1.0, 0.05, s.effects_volume, "%.0f%%",
		func(v: float) -> void: s.effects_volume = v, 100.0)
	slider(tr("HUD_SET_VOL_UI"), 0.0, 1.0, 0.05, s.ui_volume, "%.0f%%",
		func(v: float) -> void: s.ui_volume = v, 100.0)
