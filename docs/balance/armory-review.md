# Armory economy review (slice catalog, 7 guides)

Reviewer: economy-designer, 2026-10-07. Source run: `docs/balance/armory-report.md`.
Changes nothing. Every number below comes from the report or the files listed. "approx." numbers
are worked out from the report's earned curve (slice 1561 / 2904 / 5810 / 8973 at 5/10/20/30 min).
Re-run `tools/balance/armory_report.gd` to confirm them.

**Health summary: CONCERNS.** No item is mispriced and no strategy is degenerate. Five of seven
guides run out of things to buy and leave 40–57% of earned Lumen unspent.

## 1. Inputs

| Input | Status | Note |
|---|---|---|
| `docs/balance/armory-report.md` | FOUND | Per-buy tables are printed for slice/neutral runs only. The "all" runs show only summary rows. |
| `assets/data/economy/armory_catalog_slice.tres` | FOUND | 20 items. Every price matches GDD §3.8 / §7 and sits inside its band. |
| `assets/data/economy/recommended_builds_slice.tres` | FOUND | 7 builds. Read through its generator `tools/armory/build_guides.py`. |
| `assets/data/economy/advice_rules.tres` | FOUND | Empty. All values are the `advice_rules_def.gd` defaults (5v5 `enemy_tag_threshold` = 2). |
| `assets/data/economy/economy_rules_slice.tres` | FOUND | Only sets `trickle_per_min = 60`. |
| `design/gdd/wardlings-and-economy.md` §7, §18, §19, §26 | FOUND | |
| `design/gdd/weapons-and-mods.md` §3.6, §3.8–3.10 | FOUND | |
| `docs/armory.md` | FOUND | |
| `design/registry/entities.yaml` | FOUND, partial | Registers med_pack, amplifier_emitters, harmonic_tether, quick_mint, bulwark_protocol, both weaves and full_weapon_build. It has no entry for the 12 other catalog items, so they were checked against the GDD tables instead. |
| Match telemetry / bot match logs | ABSENT | Spend under the weak and strong §18 profiles: **NOT ASSESSED**. |
| Med-Pack consumption in the sim | ABSENT (sim never uses one) | Consumable share of the §18 split (~10%): **NOT ASSESSED**. |
| A shared power metric for squad items vs mounts | ABSENT | Comparing value across categories (e.g. Amplifier vs Overclock III): **NOT ASSESSED**. The tier-value table covers same-line steps only. |
| Per-buy detail of the "all" runs | ABSENT | Which weave or item the extra buy was: **NOT ASSESSED**. Only counts and unspent Lumen are known. |

## 2. Findings

Target used: §18 average curve (8,970 at 30:00) and the intended spend split of about 60% gun,
30% squad and 10% consumables/utility. The shares below are % of earned Lumen in the slice/pad/neutral run.

| Hero | Gun | Squad | Med | Unspent | Last buy |
|---|---|---|---|---|---|
| Brannoc | 4,900 (55%) | 2,550 (28%) | 100 | 1,423 (16%) | 25:33 |
| Vesper | 3,300 (37%) | 4,550 (51%) | 100 | 1,023 (11%) | 26:48 |
| Juniper / Liora / Ryker / Sable | 4,900 (55%) | 350 (4%) | 100 | 3,623 (40%) | 18:32 |
| Hex | 3,400 (38%) | 350 (4%) | 100 | 5,123 (57%) | 13:29 |

**F1. Light-squad guides stall at 18:32 (high, guide problem).** Juniper, Liora, Ryker and Sable
each end with 3,623 unspent and a dead zone from 18:32 to 30:00 (21:00–30:00 with 180 s visits).
Report lines 106, 126, 146, 166, 186, 206, 226, 246. Squad spend is 4% against a ~30% target.
Cause: `SQUAD_LIGHT` holds only `reinforced_cores_1`. Every hero has a personal squad (§3, §26
"squad 3 → 5"), so the squad sink is open to them, but no guide node offers it.

**F2. Hex stalls at 13:29 with 5,123 unspent (high, guide problem plus slice scope).** Report lines
69–70 and 85–86. `mana_core(barrel=False)` drops the three Barrel nodes, and nothing replaces their
1,500. Hex's only legal Barrel line, Velocity Facet (CR-7, Liora/Hex), is out of the slice
(§3.10), so Hex's Barrel socket stays empty all match. Hex is not an M1 slice hero (§26), but bots
buy from this guide.

**F3. Ammo and Penetrator are never bought, even in "all" runs (medium, advice-rules data plus
guide).** Report line 359. In 5v5 the `enemy_<tag>` rules need 2 enemy heroes with the tag
(`advice_rules_def.gd`, `enemy_tag_threshold [1, 2]`). `frontline` (Brannoc only) and `squad`
(Vesper only) are each carried by one hero, so `vs_armor`, `vs_squads` and `vs_armor_barrel` can
never fire. Tags carried by two or more heroes (cc 3, zone 2, skill_dps 2, burst 2) do fire, which
is why weaves show up in "all". No guide has an unconditional Chamber node either, so no guide ever
reaches the §3.8 full gun build (Core III + Barrel III + Frame III + Ammo Type). The GDD's own
Brannoc example (§3.9 "Breach Anchor") buys Sunder at about 4:00.

**F4. `squad_expansion_2` is never bought (low, intended design).** Vesper's `sq_size2` (priority
520) ranks below `sq_bulwark` (540). After Bulwark at 26:48, Vesper has 1,023 left against a price
of 1,500. The item is tagged "luxury" with phase "late". §18 calls the shop a sink that lasts to
about minute 45, and §3.8 says no player should complete a full gun and a maxed squad before 30:00.
That makes it a strong-player or long-match sink, as designed.

**F5. Builds are duplicated (medium-low, guide plus slice scope).** Juniper = Ryker and Liora = Sable
(Jaccard 1.00, line 363). All four have the same costs and timeline, because the Crystal and Chip
lines cost the same and they share `mech_core`/`mana_core` + `SQUAD_LIGHT`. The slice offers one
line per socket per family (§3.10), so mounts cannot be told apart yet. The squad tail is the one
place a guide can differ.

**F6. Tier III steps return 23–37% of Tier I value per Lumen (low, intended design).** Lines
365–377. Values of 6/11/16% match the §3.6.2 power shares of ~40/70/100% across the Minor, Standard
and Major bands, so the drop-off is the design. Side effect: the light guides buy +5% damage for
900 (c3) before any squad item.

**F7. The slice re-tune holds (healthy).** The model curve is within 1% of §18 (1561/2904/5810/8973
vs 1550/2880/5790/8970), and slice vs gdd unspent differs by ≤ 10 Lumen in every row. The §26
trickle 60 offsets the missing Sentinels as intended.

**F8. Brannoc has two dead zones, 15:56–20:27 and 25:33–30:00 (low, guide).** The first is saving
for Bulwark (1,400). He ends with 1,423 unspent.

## 3. Proposed changes (ranked)

All of these except #5 are guide content in `tools/armory/build_guides.py`, followed by
regenerating the guides and running `-a res://tests/unit/economy`. No canon value changes. Every
proposed node uses an existing catalog item at its GDD price.

| # | Change | Rationale | Expected effect (approx.) |
|---|---|---|---|
| 1 | `SQUAD_LIGHT`: add optional, `core=False` LATE nodes after `c3` at priorities 370–340: `sq_dmg` amplifier_emitters (700) → `sq_size` squad_expansion_1 (800) → `sq_hp2` reinforced_cores_2 (750, req. `sq_hp`) → `sq_tether` harmonic_tether (300). | §18 split has squad at ~30%. Today it is 4%. | Light four: unspent 3,623 → **~1,023**. Buys at ~20:50 / 23:25 / 25:45 / 26:40 (pad). No dead zone over 240 s. Squad share **~32%**. 180 s visits: buys at 21:00 / 24:00 / 27:00, same 1,023 left. |
| 2 | Hex: give the barrel-less path its own squad tail, the #1 nodes plus `sq_mint` quick_mint (250) and `sq_bulwark` bulwark_protocol (1,400, req. `sq_hp2`, `c3`). | Moves the 1,500 Barrel budget Hex cannot spend in the slice to the squad sink. | Hex: unspent 5,123 → **~923**. Last buy ~27:05. Dead zone 13:29–30:00 removed. Squad share ~51% (commander-like, see Q2). |
| 3 | Brannoc: add an unconditional Chamber node `ammo` → ammo_sunder (650), CORE, after `c2`. | §3.9 Breach Anchor example. §3.8 counts the Ammo Type in the full build. | Brannoc: unspent 1,423 → **~773**. Sunder leaves the never-bought list. Core-path done moves ~2 min later. Check the validator accepts a `situational=true` item on an unconditional node. |
| 4 | Vesper: swap priorities so `sq_size2` (Squad Expansion II) outranks `sq_bulwark`. Owner choice, see Q4. | Squad size is the commander identity (§13). 7,950 − 1,400 + 1,500 = 8,050 ≤ 8,973, so it fits by 30:00. | Expansion II bought ~27:00. Bulwark no longer bought by Vesper. Unspent ~923. |
| 5 | `advice_rules.tres` (advisor tuning, not GDD canon): set the 5v5 `enemy_tag_threshold` to 1, **or** add a per-tag threshold (code). Owner choice, see Q3. | A threshold of 2 cannot be met by a tag carried by one hero (F3). | Piercing, Penetrator and Sunder can fire in "all" runs. Size of the effect: **NOT ASSESSED** until re-run. A threshold of 1 also fires weaves on any single cc/zone hero. |
| 6 | No change to tier prices or values. | F6 is the §3.6.2 design. | None. |

Deferred, canon (GDD + registry first): append Velocity Facet (CR-7, 250 / 600 / 1,400) as catalog
item 20, keeping the wire ids append-only, when Hex enters scope. That needs a §3.10 scope change and
a registry entry. The catalog has no per-hero restriction field, so "Liora, Hex only" would be kept
by the guides, as Focus Lens is.

Registry: the 12 unregistered catalog items (Section 1) appear in both GDDs and in `docs/armory.md`.
I recommend registering them with their GDD prices. Owner approval is needed, and this review does
not edit the registry.

## 4. Open questions for the owner

1. **Light heroes: gun-first or balanced?** #1 appends squad buys after the gun lines, so the gun is
   complete at ~18:30. Putting Amplifier and Expansion I before the Tier III steps would follow the
   §3.8 "balanced spender finishes the gun at ~28–32 min" intent instead. Which pacing do you want?
2. **Hex:** is a squad-heavy tail (~51% squad) acceptable until Velocity Facet is in scope, or
   should Hex wait for the Barrel line?
3. **5v5 threat threshold:** lower it to 1 for all tags, or ask for a per-tag threshold so one
   Brannoc can trigger Piercing without one cc hero triggering Null Weave?
4. **Vesper capstone:** Squad Expansion II or Bulwark Protocol by 30:00 (not both for the average
   player)?
5. **Default ammo:** should guides other than Brannoc carry an unconditional Ammo Type (§3.8 full
   build), or does ammo stay counter-only?
