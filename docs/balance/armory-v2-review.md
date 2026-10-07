# Armory v2 economy review (draft GDD `design/gdd/items-and-armory.md`)

Reviewer: economy-designer, 2026-10-07. Read-only review: the GDD, code, data and registry are unchanged.
All numbers are worked out by hand from the GDD tables and the §18 curve, using straight lines between the §18 points
(per-minute rates for weak / average / strong: 0–5 min 146/210/292, 5–10 min 184/266/370, 10–20 min 200/291/404, 20–30 min 217/318/443).
No simulator run backs them yet.

**Health summary: CONCERNS.** The recipe arithmetic is clean: every `Total = combine + Σ parts` checks out for all 24 recipe items. The spending check holds within about 2%.
Three structural issues need owner decisions:
(a) the gear defense has no TTK bound, so the 25% cap applies to offense only;
(b) duplicate Assemblies and the HP line beat the gear Signatures on Lumen;
(c) the draft's balance criteria (AC 15 and AC 16) contradict each other.

## 1. Inputs

| Input | Status | Note |
|---|---|---|
| `design/gdd/items-and-armory.md` §1–§9 + owner questions | FOUND | |
| `docs/plans/armory-v2-recipes-gear.md` | FOUND | Owner answers to Q1–Q4 |
| `wardlings-and-economy.md` §7, §17–§19 | FOUND | Squad sink 6,050 + about 2,300 in licences |
| `weapons-and-mods.md` §3.4, §3.7–§3.8, §4 | FOUND | |
| `heroes.md` §3.1, §5.1–§5.3 | FOUND | |
| `docs/balance/armory-review.md` (v1) | FOUND | |
| `design/registry/entities.yaml` | FOUND | Only v1 entries (weaves, `full_weapon_build`). No v2 entries yet, which is expected. |
| v2 balance report (`armory_report.gd` on the v2 catalog) | ABSENT | First Signature and dead zones per hero/guide: **NOT ASSESSED**. The timings below are hand-computed. |
| Telemetry, match-length distribution | ABSENT | Lumen sink after about 45 min, pick rates: **NOT ASSESSED** |
| Med-Pack use (v1 sim never buys one) | ABSENT | Consumable share of the split: **NOT ASSESSED** |
| Lumen value per point for pool/magazine size, headshot multiplier, armor pen | ABSENT (no component sells these stats) | Efficiency of Wellframe, Reservoir Frame, Anchor Frame and Prism Eye: **NOT ASSESSED**. Pen is priced from Bore Ring. |
| Which skills deal TRUE damage, skill vs weapon damage share | ABSENT | Real value of resist: **NOT ASSESSED** |

## 2. Spending check (recomputed)

| Check | Result |
|---|---|
| Reference build "Line Breaker v2" | 12,400 confirmed. It wastes about 12 armor points: Bastion 20 + Harness 13 + Stride 4 = 37 against the 25 cap, about 450 Lumen. |
| Full-build range | The draft's 11,800–13,050 includes impossible combinations. Both 2,400 Signatures are Barrel/Frame parts, so three 850 Assemblies cannot fit. The only Frame Assembly is Wellframe at 850, and a Core holding a Signature cannot also hold a 1,000 Assembly. Feasible range with distinct items: **about 11,900–12,650**. |
| Share of 12,400 at 30:00 | Weak 6,320 = **51%**. Average 8,970 = **72%**. Strong 12,280 = **99%** (full build at about 30:16). Matches the draft. |
| First Signature (Ember Heart path with Piercing, 3,350 spent) | Average gun-first: **about 11:37** (draft 11:45). Strong: about 8:46. Weak: about 16:00. At the draft's own 67.5% item split, the average player gets it at **about 17:10** (about 13:20 without Piercing). |
| Timeline errata | The 8:30 row (Ember + Tempo, 2,550 total) is affordable only at **about 8:46**: 2,481 earned at 8:30. Every other row is affordable as written. |
| Longest unavoidable saving gap | The 1,050 Signature combine, which cannot be split. Average: 3.6 min at 10–20 min, **3.9 min** at 5–10 min. **Weak: 5.25 min (315 s)**, over the 240 s dead-zone line. |
| Sink after the full build | Average: no risk before 30:00. About 6,000 of item capacity is still open, plus the squad sink. Strong: items done at about 30:16, squad (6,050) done at **about 44 min**. After that only Med-Packs (at most 3 carried) and resale churn (40% lost per swap) remain. Matches over about 44 min: **NOT ASSESSED**. |
| v1 dead-zone risk | The capacity is fixed (12.4k vs v1's 6.1k). The v1 cause was **guide content**, not capacity. Guides must list 2 Signatures, 7 Assemblies and the Chamber, or F1 comes back. Verify with the v2 report. |

**AC conflict (high).** AC 15 says the average curve reaches 65–80% of the full build. AC 16 caps items at 60–75% of Lumen, which is 5,380–6,730 Lumen, or **43–54%** of 12,400. Both cannot pass.
The §4.7 reference timeline also fails AC 16: items 7,250 / 8,900 = **81%**, consumables about 2%.

## 3. Price bands and efficiency

Method: each stat is priced at its component rate (dmg 80/pt, fire rate 100/pt, falloff 30/pt, spread or recoil 12.5/pt, HP 12/HP, armor 37.5/pt, resist 33.3/pt, CDR 70/pt, move speed 83.3/pt). Efficiency = stat value ÷ price. An outlier is more than ±20% from its tier median.

| Tier | Efficiency | Median | Outliers |
|---|---|---|---|
| Components | Same stat, one item each | – | **Tempo 100/pt vs Ember 80/pt** for equal throughput (both feed G). Fire rate also burns ammo or mana faster, so it is the weaker stat but costs 25% more. |
| Assemblies | Ember Facet 95%, Pulse 91, Plate Harness 88, Null Cowl 89, Circlet 95, Longsight Ring 75, **Vital Core 127**, Stride Rig 60 (unconditional stats only) | 91% | **Vital Core +40%.** Longsight Ring −18% (watch). Stride Rig: depends on how much the out-of-combat speed is worth, **NOT ASSESSED**. |
| Gear Signatures (stats only) | Bastion 59%, Null Veil 58, Cadence Crown 59, Breaker Sigil 52, **Vigil Core 88**, Barrier Lattice 41 (78 if the 80-point shield counts as HP) | 59% | **Vigil Core +49%** (passive priced at about 310 vs about 1,000 for the others). Barrier Lattice depends on the shield value. |
| Weapon Signatures (stats only) | Ember Heart 61%, Tempest 60, Breaker Bore 66, Flux (Mech) 49, Longsight Lens 45 | about 60% | Longsight Lens −25%: its passive (Long Reach) carries more of the price. Acceptable if intended. |

- **Vigil Core** gives +56% EHP vs weapons at L10, while Bastion Plate gives +47%. Vigil Core is also about equal to Null Veil vs skills (+50% vs +51%), and its HP counts against every damage type. In practice it beats the two specialist Signatures.
- **Combine share.** Assemblies: 28–35%, uniform. Signature final step: Core Signatures 30–31%, gear Signatures **40–43%**. Whole tree: 42–55%. So the gear Signatures carry the biggest lump purchases.
- **Is buying components early always efficient?** Yes. A recipe's total equals the sum of its parts, and every first copy gives stats loose. There are two exceptions:
  - The second Vital Cell for Vital Core is a dead spare. 300 Lumen do nothing until the combine.
  - When all 6 slots are full, you cannot pre-buy components, so the next buy has to be a lump.

## 4. Defensive math (Ryker as attacker; full defense = +250 HP, A_gear 0.25)

| Case | L1 (250 HP, 180 DPS) | L15 (390 HP, 243 DPS) | vs naked mirror |
|---|---|---|---|
| Naked vs naked | 1.39 s | 1.60 s | – |
| Full damage (G 1.333) vs naked | 1.04 s | 1.20 s | **−25%, within the cap** |
| Naked vs full defense | 3.70 s (EHP 667) | 3.51 s (EHP 853) | **+119% to +167%** |
| Full damage, no pen, vs full defense | 2.78 s | 2.63 s | **+65% to +100%** |
| Full damage + P 0.60 + Rend 8 vs full defense | 2.24 s | 2.12 s | +32% (L15) |
| Hybrid vs hybrid (G 1.226 from sockets only + 225 HP, A 0.25; affordable) | – | 2.75 s | +72% |
| **Proposed caps: HP +200, gear armor/resist 0.20.** Full damage + pen vs full defense | 1.97 s | 1.91 s | **+19% (L15)** |
| Proposed caps, no pen | – | 2.28 s | +42% |

- **The cap does not hold both ways.** G only limits offense. Defense can stretch TTK by up to 2.7×, which puts late-game high-DPS duels in the "Low" band (`heroes.md` §5.2).
- **Weapon sockets and open slots are separate budgets.** A hero can hold G 1.226 *and* full defense for about 11,400 Lumen. There is no damage-vs-defense trade-off in a slot, only in Lumen. This is a game-designer question.
- **Proposal:** add a symmetric rule: *full defense vs a full-damage build that bought the counter: TTK ≤ +25%; without the counter: ≤ +50%.* The proposed caps (HP +200, armor/resist 0.20) meet it.
- **Brannoc rule (c).** Base 2.75×. P 0.40 (Piercing alone): exactly **2.50×**. Saturated Piercing (0.52): 2.43×. **P 0.55: 550 / 0.91 = 604 = 2.42×, so it still fails.** P 0.60: 2.39×.
  - Only a cap of 0.40 keeps 2.5×. At that cap, Bore Ring, Breaker Bore and the ammo mods do nothing against base armor.

## 5. Degenerate strategies

| Strategy | Finding | Severity | Recommendation |
|---|---|---|---|
| Component stacking | Blocked by the unique loose-stats rule. Max M_dmg (16+4+5) is exactly 0.25. | OK | Keep |
| **Duplicate Assemblies** | Plate Harness ×2 (1,800) = 26 armor (capped 25) + 50 HP, more than Bastion (2,500) gives in stats. The same holds for Null Cowl ×2 vs Null Veil and Vital Core ×2 vs Vigil Core. The duplicates also leave a Signature free. | **High** | Extend "one active copy" to every non-consumable item id. A full build still fits: 2 Signatures + 4 different gear Assemblies. |
| 6 slots of HP | +250 HP for 2,550 (Vital Core ×3). Pen does not touch HP, and HP is priced 21–49% under the other lines. | Medium | Vital Core HP 90 → **75**, Vigil Core HP 170 → **130** (efficiency 68%, +44% EHP), HP cap → 200 |
| All-resist | Null Cowl + Thread + Circlet reaches the 0.25 cap for 2,150. Hard counter to skill heroes. | Low (watch) | Value is NOT ASSESSED without skill/TRUE damage data. Resist cap 0.20 with the armor cap. |
| Siphon + HP | Siphon heals based on damage dealt, not on max HP: at most 12% × 240 DPS ≈ 29 HP/s. Regen sources pile up (Vigil 2%/s, Lattice refill, Siphon), and that also shrinks the Med-Pack sink. | Low | Monitor the consumable share. Incendiary stays the counter. |
| Ammo mods past the cap | Overcharged Piercing (0.60) maxes pen on its own, so Bore pen is wasted. Brittle (×1.08) and Burn sit outside G: Overcharged Cryo cuts TTK about 27% instead of 25%. The Burn share is NOT ASSESSED. | Medium | Have AC 9 assert TTK ≥ 0.75 × naked TTK with ammo effects included, as v1 rule (a) counted ammo. |

## 6. Owner questions (balance view)

| Q | Recommendation | Why (numbers) |
|---|---|---|
| 1 Signature limit | **2**, knob 2–3 | 12,400 ≈ strong player at 30:16. With 3 Signatures (about 14,000–14,500) the average player holds about 62%, and every passive (power ceiling) rises. Move to 3 only if telemetry shows strong players with nothing to buy after 30 min. |
| 2 Loose weapon components give stats | **Yes** | Lumen spent on parts is never dead, which keeps the saving gaps at 2.5–3.6 min (average). Without it, 1,000–1,700 per recipe sits idle, which brings back v1's dead-zone feel. G cap verified. |
| 3 Unique loose stats | **Yes, and extend it to Assemblies** | See §5: duplicate Assemblies beat Signatures by 700 Lumen. Have the advisor buy the second Vital Cell only together with the combine (550). |
| 6 Pen cuts gear armor | **Yes** | Without it, Brannoc's 0.45 armor (EHP 2,015) cannot be answered. With it: 1,351. Pair it with the HP repricing so HP stacking does not become the counter-counter. |
| 9 Brannoc 2.5× | **Relax rule (c) to ≥ 2.35×, keep the 0.60 cap** | 0.55 does not fix it (2.42×). 2.39× vs 2.5× is a 4% TTK difference. Alternative if 2.5× must stay: a separate pen cap of 0.40 on base armor and 0.60 on gear armor. |
| 10 Spend split 65–70 / 20–25 / ~10 | **Accept as the target for a balanced player**, and fix the ACs | Fix AC 15 to: average reaches **45–55%** of the full build at 30:00 at this split (65–80% for gun-first). Apply AC 16 to balanced guides only. The §4.7 timeline (81% items) is gun-first. |

Other fixes:
- Gear Signature final combine: keep it ≤ 900, or build gear Signatures from 2 Assemblies + ≤ 750 combine. This brings the weak player's gap under 240 s.
- Tempo: 400 → **350**. This moves Pulse 900, Tempest 2,450, Ember Heart 2,550 and Flux 2,450, all inside their bands.
- Registry: register the v2 items after sign-off (draft §9); this review does not edit it.
