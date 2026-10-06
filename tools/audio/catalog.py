"""W21-A1 audio event catalog: the single table both generators read.

* render_sfx.py renders each FILE entry to assets/audio/<folder>/<stem>_NN.ogg.
* write_event_defs.py writes one AudioEventDef .tres per EVENT entry under
  assets/data/audio/events/ plus the index assets/data/audio/audio_events.tres.

After generation the .tres files are the designer-facing data (tune them in
the editor); re-running write_event_defs.py overwrites them, so tune here
first when a value should survive regeneration.

Naming (audio direction spec §3): [category]_[context]_[name]_[variant].ogg
"""
from __future__ import annotations

from dataclasses import dataclass, field

import sfx_recipes as R

# Owner filters (AudioEventDef.OwnerFilter)
ANY, OWN, ENEMY, ALLY = 0, 1, 2, 3
# Spatial
S2D, S3D = 0, 1
# Buses
WEAPONS, ABILITIES, FOOTSTEPS, WORLD, UI, VOICE, AMBIENT, MUSIC = (
    "Weapons", "Abilities", "Footsteps", "World", "UI", "Voice", "Ambient", "Music")


@dataclass
class FileSpec:
    folder: str
    stem: str
    recipe: object
    params: dict
    variants: int = 1
    target: float = -18.0  # LUFS
    mode: str = "M"        # M = momentary max, I = integrated
    stereo: bool = False
    quality: float = 4.0


@dataclass
class EventSpec:
    id: str
    stem: str               # file stem (shared by several events)
    folder: str
    bus: str
    spatial: int = S2D
    max_distance_m: float = 0.0
    unit_size: float = 10.0
    attenuation: int = 0    # AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
    volume_db: float = 0.0
    vol_jitter_db: float = 1.0
    pitch: float = 1.0
    pitch_jitter: float = 0.03
    priority: int = 2
    far_priority: int = -1
    priority_range_m: float = 0.0
    max_voices: int = 4
    cooldown_ms: int = 0
    owner_filter: int = ANY
    synth_recipe: str = ""
    night_db: float = 0.0
    loop: bool = False
    tags: list = field(default_factory=list)


FILES: list[FileSpec] = []
EVENTS: list[EventSpec] = []


def f(folder, stem, recipe, variants=1, target=-18.0, mode="M", stereo=False, quality=4.0, **params):
    FILES.append(FileSpec(folder, stem, recipe, params, variants, target, mode, stereo, quality))


def e(id_, stem, folder, bus, **kw):
    EVENTS.append(EventSpec(id_, stem, folder, bus, **kw))


# ---------------------------------------------------------------- weapons
VOICES = {  # WeaponDef.sfx_voice -> (mechanical?, legacy archetype)
    "rifle": (True, "gun_rifle"), "smg_burst": (False, "gun_smg"), "heavy": (True, "gun_heavy"),
    "zap": (False, "gun_zap"), "tack": (True, "gun_tack"), "glitch": (False, "gun_glitch"),
    "thread": (False, "gun_thread"),
}
for voice, (mech, arche) in VOICES.items():
    stem = f"weapons_{voice}_shot"
    f("weapons", stem, R.gun_shot, 5, -14.0, voice=voice)
    f("weapons", f"weapons_{voice}_tail", R.gun_tail, 2, -24.0, voice=voice,
      bright=2500.0 if mech else 4500.0, length=1.6 if voice == "heavy" else 1.2)
    # own 2D P1; enemy 3D P0 within 30 m (P2 beyond); ally 3D P2. An enemy at 10 m is
    # 3 dB louder than the own shot (unit_size 10 -> 0 dB at 10 m, volume +3).
    e(f"weapon_{voice}_shot_own", stem, "weapons", WEAPONS, priority=1, max_voices=3, owner_filter=OWN,
      vol_jitter_db=0.8, pitch_jitter=0.025, synth_recipe=arche, tags=["weapon"])
    e(f"weapon_{voice}_shot_enemy", stem, "weapons", WEAPONS, spatial=S3D, max_distance_m=120.0, unit_size=10.0,
      volume_db=3.0, priority=0, far_priority=2, priority_range_m=30.0, max_voices=6, owner_filter=ENEMY,
      pitch_jitter=0.04, synth_recipe=arche, tags=["weapon"])
    e(f"weapon_{voice}_shot_ally", stem, "weapons", WEAPONS, spatial=S3D, max_distance_m=90.0, unit_size=8.0,
      volume_db=0.0, priority=2, max_voices=4, owner_filter=ALLY, pitch_jitter=0.04, synth_recipe=arche, tags=["weapon"])
    e(f"weapon_{voice}_tail_own", f"weapons_{voice}_tail", "weapons", WEAPONS, volume_db=-2.0, priority=3,
      max_voices=2, owner_filter=OWN, cooldown_ms=90)
    e(f"weapon_{voice}_tail_remote", f"weapons_{voice}_tail", "weapons", WEAPONS, spatial=S3D, max_distance_m=160.0,
      unit_size=20.0, volume_db=0.0, priority=3, max_voices=2, cooldown_ms=120)
    if mech:
        for part in ("start", "mag_out", "done"):
            pstem = f"weapons_{voice}_reload_{part}"
            f("weapons", pstem, R.reload_part, 2, -22.0, part=part, voice=voice)
            e(f"weapon_{voice}_reload_{part}_own", pstem, "weapons", WEAPONS, priority=1, max_voices=1, owner_filter=OWN,
              synth_recipe="reload_done" if part == "done" else "reload_start")
            e(f"weapon_{voice}_reload_{part}_enemy", pstem, "weapons", WEAPONS, spatial=S3D, max_distance_m=15.0,
              unit_size=4.0, volume_db=2.0, priority=1, max_voices=2, owner_filter=ENEMY)

f("weapons", "weapons_mech_dry", R.dry_fire, 3, -24.0)
e("weapon_dry_fire", "weapons_mech_dry", "weapons", WEAPONS, priority=1, max_voices=1, owner_filter=OWN,
  synth_recipe="dry_fire", cooldown_ms=120)
f("weapons", "weapons_mech_lowammo", R.low_ammo, 1, -26.0, mana=False)
f("weapons", "weapons_mana_lowammo", R.low_ammo, 1, -26.0, mana=True)
e("weapon_low_ammo_mech", "weapons_mech_lowammo", "weapons", WEAPONS, priority=2, max_voices=1, owner_filter=OWN,
  vol_jitter_db=0.0, pitch_jitter=0.0)
e("weapon_low_ammo_mana", "weapons_mana_lowammo", "weapons", WEAPONS, priority=2, max_voices=1, owner_filter=OWN,
  vol_jitter_db=0.0, pitch_jitter=0.0)
f("weapons", "weapons_mana_burnout", R.burnout, 2, -18.0)
e("weapon_burnout_own", "weapons_mana_burnout", "weapons", WEAPONS, priority=1, max_voices=1, owner_filter=OWN)
e("weapon_burnout_enemy", "weapons_mana_burnout", "weapons", WEAPONS, spatial=S3D, max_distance_m=15.0,
  unit_size=4.0, priority=1, max_voices=2, owner_filter=ENEMY)
f("weapons", "weapons_mana_regen", R.mana_regen, 1, -24.0)
e("weapon_mana_regen_own", "weapons_mana_regen", "weapons", WEAPONS, priority=3, max_voices=1, owner_filter=OWN)
for ammo in ("standard", "piercing", "sunder", "mana"):
    st = f"weapons_impact_{ammo}"
    f("weapons", st, R.impact, 3, -18.0, ammo=ammo)
    e(f"impact_{ammo}_victim", st, "weapons", WEAPONS, priority=1, max_voices=2, cooldown_ms=60, owner_filter=OWN)
for tier in (1, 2, 3):
    st = f"weapons_core_layer_t{tier}"
    f("weapons", st, R.core_layer, 1, -22.0 + 2.0 * tier, tier=tier)
    e(f"weapon_core_layer_t{tier}", st, "weapons", WEAPONS, priority=3, max_voices=2, owner_filter=OWN,
      cooldown_ms=60)

# ---------------------------------------------------------------- combat
f("weapons", "weapons_combat_hit", R.hit_tick, 3, -20.0, head=False)
f("weapons", "weapons_combat_headshot", R.hit_tick, 3, -18.0, head=True)
f("weapons", "weapons_combat_kill", R.kill_confirm, 1, -17.0)
f("weapons", "weapons_combat_assist", R.assist, 1, -20.0)
f("weapons", "weapons_combat_death", R.own_death, 1, -17.0)
f("weapons", "weapons_combat_damage", R.damage_taken, 4, -20.0)
f("weapons", "weapons_combat_heartbeat", R.heartbeat, 1, -22.0)
e("combat_hit", "weapons_combat_hit", "weapons", UI, priority=1, max_voices=2, cooldown_ms=35, owner_filter=OWN,
  synth_recipe="ui_click", pitch_jitter=0.02)
e("combat_headshot", "weapons_combat_headshot", "weapons", UI, priority=1, max_voices=2, cooldown_ms=35,
  owner_filter=OWN, pitch_jitter=0.02)
e("combat_kill", "weapons_combat_kill", "weapons", UI, priority=0, max_voices=1, owner_filter=OWN,
  vol_jitter_db=0.0, pitch_jitter=0.0)
e("combat_assist", "weapons_combat_assist", "weapons", UI, priority=1, max_voices=1, owner_filter=OWN,
  vol_jitter_db=0.0, pitch_jitter=0.0)
e("combat_own_death", "weapons_combat_death", "weapons", UI, priority=0, max_voices=1, owner_filter=OWN,
  vol_jitter_db=0.0, pitch_jitter=0.0)
# Damage taken is placed 1.5 m from the listener toward the attacker (3D) so the
# spatializer pans it; unit_size 1.5 keeps it at 0 dB there.
e("combat_damage_taken", "weapons_combat_damage", "weapons", WEAPONS, spatial=S3D, max_distance_m=0.0,
  unit_size=1.5, priority=1, max_voices=2, cooldown_ms=80, owner_filter=OWN)
e("combat_heartbeat", "weapons_combat_heartbeat", "weapons", UI, priority=0, max_voices=1, owner_filter=OWN,
  vol_jitter_db=0.0, pitch_jitter=0.0, cooldown_ms=700)

# ------------------------------------------------------------- abilities
SKILLS = {  # skill id -> (hero, semitones, cast dur, ult, loop?)
    "skill_brannoc_aegis_wall": ("brannoc", 0, 0.7, False, False),
    "skill_brannoc_ram_charge": ("brannoc", 3, 0.6, False, False),
    "skill_brannoc_fortify": ("brannoc", 5, 0.6, False, True),
    "skill_brannoc_earthbreaker": ("brannoc", -2, 1.3, True, False),
    "skill_hex_breach_spike": ("hex", 0, 0.45, False, False),
    "skill_hex_relay_hop": ("hex", 7, 0.35, False, False),
    "skill_hex_static_field": ("hex", -5, 0.6, False, True),
    "skill_hex_zero_day": ("hex", -12, 1.3, True, False),
    "skill_juniper_snare_coil": ("juniper", 0, 0.45, False, False),
    "skill_juniper_tripwire_lattice": ("juniper", 4, 0.5, False, False),
    "skill_juniper_pressure_mine": ("juniper", -3, 0.45, False, False),
    "skill_juniper_killbox": ("juniper", -7, 1.3, True, True),
    "skill_liora_med_pack_drone": ("liora", 0, 0.6, False, False),
    "skill_liora_prism_ward": ("liora", 4, 0.6, False, False),
    "skill_liora_flash_bloom": ("liora", 7, 0.5, False, False),
    "skill_liora_aurora": ("liora", -5, 1.4, True, True),
    "skill_ryker_frag_grenade": ("ryker", 0, 0.4, False, False),
    "skill_ryker_combat_stim": ("ryker", 5, 0.45, False, False),
    "skill_ryker_tactical_slide": ("ryker", 2, 0.4, False, False),
    "skill_ryker_overdrive": ("ryker", -3, 1.2, True, False),
    "skill_sable_phase_shift": ("sable", 0, 0.6, False, False),
    "skill_sable_veilwalk": ("sable", -5, 0.8, False, True),
    "skill_sable_sabotage_charge": ("sable", 3, 0.5, False, False),
    "skill_sable_eclipse_step": ("sable", -9, 1.2, True, False),
    "skill_vesper_threadstep": ("vesper", 0, 0.5, False, False),
    "skill_vesper_marionette_thread": ("vesper", 5, 0.6, False, True),
    "skill_vesper_rally_beacon": ("vesper", -5, 0.7, False, False),
    "skill_vesper_rewrite": ("vesper", -12, 1.4, True, False),
}
LEGACY_CAST = {"brannoc": "shield_up", "hex": "hack_glitch", "juniper": "trap_click", "liora": "heal_chime",
               "ryker": "buff_up", "sable": "shimmer", "vesper": "whoosh"}
for sid, (hero, semis, dur, ult, loop) in SKILLS.items():
    name = sid.replace(f"skill_{hero}_", "")
    folder = f"abilities/{hero}"
    cast = f"abilities_{hero}_{name}_cast"
    hit = f"abilities_{hero}_{name}_impact"
    f(folder, cast, R.ability, 2, -16.0 if not ult else -15.0, hero=hero, gesture="cast", semis=semis, dur=dur, ult=ult)
    f(folder, hit, R.ability, 2, -16.0, hero=hero, gesture="impact", semis=semis + 5, dur=min(dur, 0.7))
    night = -4.0 if ult else 0.0
    legacy = "ult_rise" if ult else LEGACY_CAST[hero]
    e(f"{sid}_cast_own", cast, folder, ABILITIES, priority=1, max_voices=2, owner_filter=OWN, synth_recipe=legacy,
      night_db=night, tags=["ult"] if ult else [])
    # Enemy ult casts are P0 at any range (spec §4); basic casts P1 near, P2 far.
    e(f"{sid}_cast_enemy", cast, folder, ABILITIES, spatial=S3D, max_distance_m=200.0 if ult else 70.0,
      unit_size=30.0 if ult else 10.0, volume_db=2.0, priority=0 if ult else 1, far_priority=0 if ult else 2,
      priority_range_m=30.0, max_voices=3, owner_filter=ENEMY, synth_recipe=legacy, night_db=night,
      tags=["ult"] if ult else [])
    e(f"{sid}_cast_ally", cast, folder, ABILITIES, spatial=S3D, max_distance_m=70.0, unit_size=10.0,
      priority=2, max_voices=3, owner_filter=ALLY, synth_recipe=legacy, night_db=night)
    e(f"{sid}_impact", hit, folder, ABILITIES, spatial=S3D, max_distance_m=70.0, unit_size=10.0, priority=1,
      far_priority=2, priority_range_m=25.0, max_voices=4, synth_recipe=legacy, night_db=night)
    if loop:
        lst = f"abilities_{hero}_{name}_loop"
        f(folder, lst, R.ability, 1, -24.0, hero=hero, gesture="loop", semis=semis - 12, dur=2.0)
        e(f"{sid}_loop", lst, folder, ABILITIES, spatial=S3D, max_distance_m=40.0, unit_size=6.0, priority=2,
          max_voices=4, loop=True, vol_jitter_db=0.0, pitch_jitter=0.0, synth_recipe="beam_loop")

f("abilities/shared", "abilities_shared_explosion", R.explosion, 3, -14.0, size=1.0)
e("ability_explosion", "abilities_shared_explosion", "abilities/shared", ABILITIES, spatial=S3D, max_distance_m=120.0,
  unit_size=15.0, priority=0, far_priority=1, priority_range_m=40.0, max_voices=3, synth_recipe="explosion",
  night_db=-4.0, tags=["big"])
f("abilities/liora", "abilities_liora_heal_beam_loop", R.ability, 1, -24.0, hero="liora", gesture="loop", semis=-12, dur=2.0)
e("ability_heal_beam_loop", "abilities_liora_heal_beam_loop", "abilities/liora", ABILITIES, spatial=S3D,
  max_distance_m=40.0, unit_size=6.0, priority=2, max_voices=2, loop=True, vol_jitter_db=0.0, pitch_jitter=0.0,
  synth_recipe="beam_loop")

# ----------------------------------------------------------------- world
for ev in ("spawn", "attack", "death"):
    st = f"world_wardling_{ev}"
    f("world", st, R.wardling, 3, -20.0, event=ev)
    e(f"wardling_{ev}", st, "world", WORLD, spatial=S3D, max_distance_m=40.0, unit_size=6.0, priority=2,
      max_voices=4 if ev == "attack" else 3, cooldown_ms=80 if ev == "attack" else 0)
for ev in ("capture", "contest", "lost", "uplink_alarm", "sudden_death"):
    st = f"world_objective_{ev}"
    f("world", st, R.objective, 1, -18.0, stereo=True, event=ev)
    pri = 0 if ev in ("lost", "uplink_alarm", "sudden_death") else 1
    e(f"objective_{ev}", st, "world", WORLD, priority=pri, max_voices=1,
      cooldown_ms=4000 if ev in ("contest", "uplink_alarm") else 500, vol_jitter_db=0.0, pitch_jitter=0.0)

for ev in ("shield_down", "crack", "breach"):
    st = f"world_generator_{ev}"
    f("world", st, R.generator, 2 if ev == "crack" else 1, -16.0 if ev == "breach" else -18.0, event=ev)
    e(f"generator_{ev}", st, "world", WORLD, spatial=S3D, max_distance_m=70.0, unit_size=10.0,
      priority=0 if ev == "breach" else 1, max_voices=2, cooldown_ms=300)

# ------------------------------------------------------------- footsteps
for surface in ("concrete", "metal", "grate", "water"):
    st = f"footsteps_{surface}_step"
    f("footsteps", st, R.footstep, 5, -20.0, surface=surface)
    e(f"footstep_{surface}_own", st, "footsteps", FOOTSTEPS, volume_db=-10.0, priority=2, max_voices=2,
      owner_filter=OWN, synth_recipe="footstep", pitch_jitter=0.06, vol_jitter_db=1.5)
    # Enemy steps: 3D P0 within 20 m (inaudible beyond); -24 LUFS at 5 m (file -20, unit 5 m, -4 dB).
    e(f"footstep_{surface}_enemy", st, "footsteps", FOOTSTEPS, spatial=S3D, max_distance_m=20.0, unit_size=5.0,
      volume_db=-4.0, priority=0, max_voices=6, owner_filter=ENEMY, synth_recipe="footstep", pitch_jitter=0.06,
      vol_jitter_db=1.5)
for kind in ("jump", "land_light", "land_heavy"):
    st = f"footsteps_body_{kind}"
    f("footsteps", st, R.body_move, 3, -21.0 if kind != "land_heavy" else -18.0, kind=kind)
    e(f"move_{kind}_own", st, "footsteps", FOOTSTEPS, volume_db=-6.0, priority=2, max_voices=1, owner_filter=OWN,
      cooldown_ms=150)
    e(f"move_{kind}_enemy", st, "footsteps", FOOTSTEPS, spatial=S3D, max_distance_m=25.0, unit_size=5.0,
      volume_db=-2.0, priority=1, max_voices=3, owner_filter=ENEMY, cooldown_ms=150)
for kind in ("splash", "wade"):
    st = f"footsteps_water_{kind}"
    f("footsteps", st, R.water, 3, -20.0, kind=kind)
    e(f"water_{kind}_own", st, "footsteps", FOOTSTEPS, volume_db=-6.0 if kind == "splash" else -10.0, priority=2,
      max_voices=1, owner_filter=OWN, synth_recipe="footstep", cooldown_ms=200)

# -------------------------------------------------------------------- ui
UI_EVENTS = {  # name -> (variants, LUFS, legacy archetype)
    "hover": (2, -26.0, "ui_hover"), "click": (2, -21.0, "ui_click"), "back": (1, -21.0, "ui_click"),
    "confirm": (1, -20.0, "ui_buy"), "error": (1, -20.0, "ui_sell"), "buy": (1, -20.0, "ui_buy"),
    "sell": (1, -20.0, "ui_sell"), "denied": (1, -20.0, "ui_sell"), "levelup": (1, -19.0, "ui_levelup"),
    "lumen": (3, -26.0, "ui_hover"), "fork": (1, -20.0, "ui_fork"), "lock": (1, -19.0, "ui_lock"),
    "match_found": (1, -18.0, "ui_levelup"), "ready_check": (1, -18.0, "ui_fork"),
    "countdown_tick": (1, -20.0, "ui_click"), "countdown_go": (1, -18.0, "ui_buy"),
    "victory": (1, -17.0, "ui_levelup"), "defeat": (1, -18.0, "ui_sell"),
}
for name, (n, lufs, legacy) in UI_EVENTS.items():
    ctx = "economy" if name in ("buy", "sell", "denied", "levelup", "lumen", "fork") else \
        ("flow" if name in ("match_found", "ready_check", "countdown_tick", "countdown_go", "victory", "defeat", "lock") else "menu")
    st = f"ui_{ctx}_{name}"
    f("ui", st, R.ui, n, lufs, stereo=True, kind=name)
    e(f"ui_{name}", st, "ui", UI, priority=1 if name in ("victory", "defeat", "match_found", "ready_check") else 2,
      max_voices=2 if name in ("hover", "click", "lumen") else 1, cooldown_ms=40 if name in ("hover", "lumen") else 0,
      vol_jitter_db=0.0, pitch_jitter=0.02 if name in ("hover", "click", "lumen") else 0.0, synth_recipe=legacy)

# -------------------------------------------------------------- announcer
for tier in ("triumph", "alert", "streak", "neutral"):
    st = f"voice_stinger_{tier}"
    f("voice", st, R.announce, 1, -16.0, "I", stereo=True, tier=tier)
    e(f"announce_{tier}", st, "voice", VOICE, priority=0, max_voices=1, vol_jitter_db=0.0, pitch_jitter=0.0)
# Recorded announcer lines (layer 2): files voice/voice_announcer_<line>_01.ogg; silent until present.
ANNOUNCER_LINES = ["victory", "defeat", "sudden_death", "uplink_under_attack", "hardpoint_lost",
                   "hardpoint_captured", "shutdown", "triple_kill", "double_kill", "first_blood", "thirty_seconds"]
for line in ANNOUNCER_LINES:
    e(f"voice_{line}", f"voice_announcer_{line}", "voice", VOICE, priority=0, max_voices=1, vol_jitter_db=0.0,
      pitch_jitter=0.0)

# --------------------------------------------------------------- ambient
for zone in ("base", "lane", "jungle", "water"):
    st = f"ambient_{zone}_bed"
    f("ambient", st, R.ambient_bed, 1, -30.0, "I", stereo=True, quality=2.0, zone=zone)
    e(f"ambient_{zone}_bed", st, "ambient", AMBIENT, priority=3, max_voices=1, loop=True, vol_jitter_db=0.0,
      pitch_jitter=0.0)
