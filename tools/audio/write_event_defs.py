#!/usr/bin/env python3
"""W21-A1: writes one AudioEventDef .tres per catalog EVENT under
assets/data/audio/events/<folder>/<id>.tres and the index
assets/data/audio/audio_events.tres (AudioEventBankDef). Deterministic.

    python3 tools/audio/write_event_defs.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import catalog  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "assets" / "data" / "audio"
EVENT_SCRIPT = "res://src/gameplay/views/audio/audio_event_def.gd"
BANK_SCRIPT = "res://src/gameplay/views/audio/audio_event_bank_def.gd"


def num(v: float) -> str:
    s = repr(float(v))
    return s[:-2] if s.endswith(".0") else s


def event_tres(e: catalog.EventSpec) -> str:
    lines = [
        '[gd_resource type="Resource" script_class="AudioEventDef" format=3]',
        "",
        f'[ext_resource type="Script" path="{EVENT_SCRIPT}" id="1"]',
        "",
        "[resource]",
        'script = ExtResource("1")',
        f'id = &"{e.id}"',
        f'folder = "{e.folder}"',
        f'file_stem = "{e.stem}"',
    ]
    if e.synth_recipe:
        lines.append(f'synth_recipe = &"{e.synth_recipe}"')
    lines.append(f'bus = &"{e.bus}"')
    if e.spatial:
        lines += [f"spatial = {e.spatial}", f"max_distance_m = {num(e.max_distance_m)}",
                  f"unit_size = {num(e.unit_size)}"]
        if e.attenuation:
            lines.append(f"attenuation = {e.attenuation}")
    lines += [f"volume_db = {num(e.volume_db)}", f"vol_jitter_db = {num(e.vol_jitter_db)}",
              f"pitch = {num(e.pitch)}", f"pitch_jitter = {num(e.pitch_jitter)}",
              f"priority = {e.priority}"]
    if e.far_priority >= 0:
        lines += [f"far_priority = {e.far_priority}", f"priority_range_m = {num(e.priority_range_m)}"]
    lines.append(f"max_voices = {e.max_voices}")
    if e.cooldown_ms:
        lines.append(f"cooldown_ms = {e.cooldown_ms}")
    if e.owner_filter:
        lines.append(f"owner_filter = {e.owner_filter}")
    if e.night_db:
        lines.append(f"night_db = {num(e.night_db)}")
    if e.loop:
        lines.append("loop = true")
    return "\n".join(lines) + "\n"


def main() -> None:
    ids = set()
    paths = []
    for e in catalog.EVENTS:
        assert e.id not in ids, f"duplicate event id {e.id}"
        ids.add(e.id)
        rel = Path("events") / e.folder / f"{e.id}.tres"
        out = DATA / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(event_tres(e))
        paths.append("res://assets/data/audio/" + rel.as_posix())
    head = [f'[gd_resource type="Resource" script_class="AudioEventBankDef" load_steps={len(paths) + 3} format=3]', "",
            f'[ext_resource type="Script" path="{BANK_SCRIPT}" id="1"]',
            f'[ext_resource type="Script" path="{EVENT_SCRIPT}" id="2"]']
    refs = []
    for i, p in enumerate(paths):
        head.append(f'[ext_resource type="Resource" path="{p}" id="e{i}"]')
        refs.append(f'ExtResource("e{i}")')
    body = ["", "[resource]", 'script = ExtResource("1")',
            f'events = Array[ExtResource("2")]([{", ".join(refs)}])',
            "pool_2d = 12", "pool_3d = 20", "pool_loops = 8", "max_variants = 8"]
    (DATA / "audio_events.tres").write_text("\n".join(head + body) + "\n")
    print(f"wrote {len(paths)} event defs")


if __name__ == "__main__":
    main()
