extends SceneTree
## W10-W5: writes every synthesized archetype as a WAV for listening, and prints
## the startup synth time. Run: godot --headless --path . -s tools/audio/export_sfx_wavs.gd

func _init() -> void:
	var dir := "res://production/qa/evidence/w10-sound"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var bank := SfxBank.new()
	bank.synthesize_all()
	print("synth_ms=%.1f archetypes=%d" % [bank.synth_ms, bank.streams.size()])
	for k in bank.streams:
		(bank.streams[k] as AudioStreamWAV).save_to_wav("%s/%s.wav" % [dir, k])
	quit()
