class_name SfxBank
extends RefCounted
## W10-W5: the synthesized stream cache. Every SfxSynth archetype is built once
## (shared(), at first use / client startup) and reused with pitch / gain
## variation chosen by data (SfxBankDef). Presentation only.

const DEF_PATH := "res://assets/data/audio/sfx_bank.tres"

static var _shared: SfxBank

var def: SfxBankDef
var streams: Dictionary = {}  # archetype StringName -> AudioStreamWAV
## Wall-clock cost of the last synthesize_all() in ms (startup budget: 300).
var synth_ms: float = 0.0


static func shared() -> SfxBank:
	if _shared == null:
		_shared = SfxBank.new()
		_shared.def = load(DEF_PATH) as SfxBankDef
		_shared.synthesize_all()
	return _shared


func synthesize_all() -> void:
	var t0 := Time.get_ticks_usec()
	streams.clear()
	for name in SfxSynth.ARCHETYPES:
		streams[name] = SfxSynth.make(name)
	synth_ms = (Time.get_ticks_usec() - t0) / 1000.0


func stream(archetype: StringName) -> AudioStreamWAV:
	return streams.get(archetype)


## {stream, pitch, db} for a WeaponDef.sfx_voice; empty if the voice is unknown.
func weapon_voice(voice: StringName) -> Dictionary:
	var v: Variant = def.weapon_voices.get(voice)
	if v == null:
		return {}
	return {"stream": stream(v["archetype"]), "pitch": float(v["pitch"]), "db": float(v["db"])}


## {stream, pitch} for a skill's cast sound; empty if unmapped.
func skill_cast(skill_id: StringName) -> Dictionary:
	var v: Variant = def.skills.get(skill_id)
	if v == null:
		return {}
	return {"stream": stream(v["cast"]), "pitch": float(v["pitch"])}


func fx_impact(kind: int) -> AudioStreamWAV:
	return stream(def.fx_impacts.get(kind, &""))


func ui_stream(event: StringName) -> AudioStreamWAV:
	return stream(def.ui.get(event, &""))
