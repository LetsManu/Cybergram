# Armory v2: LoL-style shop, item recipes, body gear (DRAFT for owner review)

Status: proposal, not approved. Nothing here is canon until the owner signs off
and the GDDs (`weapons-and-mods.md`, `wardlings-and-economy.md`,
`game-concept.md` C14) and `design/registry/entities.yaml` are updated first.

## Owner decisions (2026-10-07)

1. **Shop layout like LoL:** Recommended / All Items / Item Sets. No fixed
   build paths: Recommended adapts to the match, Item Sets are the player's
   own (today's My builds).
2. **Weapons get built from recipes:** small components combine into bigger
   parts, LoL style. The gun shows what is built, so each player's weapon looks
   different (USP: "you can read a build off the gun").
3. **Body gear:** new hero slots for Health, Armor (vs weapons) and Resist
   (vs skills). Visible on the hero model (Pillar 4 "Power You Can See").
4. **Counter items:** per-trait thresholds. Done (commit a69e5af).

## What stays

- Lumen, the Armory zone, the buy / sell / same-visit undo rules, the server
  purchase path and result channel, BuildAdvisor (it learns recipes),
  the bots' buy path, private builds (renamed Item Sets), the balance report.
- Gun families: Crystals for Mana guns and Chips for Mechanical guns.
- Ammo as the strongest visual channel (tracer colour + impact per type).

## Proposed item model

| Tier (LoL analog) | Example | Price | Holds where | Visible as |
|---|---|---|---|---|
| **Component** (basic) | Ember Shard (+damage), Lens Ring (+range), Plate Shard (+HP) | 250–450 | Kit rail (see Q1) | small clip-on module |
| **Assembly** (epic) | Ember Facet = Ember Shard + Lens Ring + 300 | 800–1,100 | Kit rail or its socket | medium part on its socket |
| **Signature** (legendary) | Ember Heart (damage + on-kill passive), Longshot Heart (damage + range) | 2,400–3,200 total | its gun socket / body slot | large part, idle motion, unique sound |

- **Recipe rule (LoL):** buying an item uses the components you own; you pay
  only the missing ones plus the combine cost. The shop shows the recipe
  tree (item, its parts below, owned parts ticked).
- **Branching:** one component feeds several finished items (an Ember Shard
  builds into the damage Heart, the sustain Heart or the range Heart). That is
  where the build variety comes from: same start, different weapon.
- **Unique passives:** every Signature item has one named passive; only one
  Signature per socket. A "unique group" keeps two of the same passive from
  stacking.
- Today's three tiers map onto this: Tier I = Component, Tier II = Assembly,
  Tier III = Signature. Existing lines become the first recipe trees.

## Slots

| Group | Slots | Holds |
|---|---|---|
| Gun | Core, Barrel, Frame | one finished part each (Assembly or Signature) |
| Gun | Chamber | Ammo Type + Ammo Mod (all 6 types, 5 mods from the GDD) |
| Body (new) | Plating, Shell, Ward (see Q2) | Health / weapon armor / skill resist items |
| Kit rail (new, see Q1) | 3 | Components and Assemblies still being built |

Squad upgrades and Med-Packs stay as they are.

## Shop UI (LoL layout)

- **Recommended:** sections Starter / Core / Situational / Ammo, with 2–3
  choices per core step instead of one path; reasons stay ("enemy has
  frontline", "taking skill damage"). Reads the enemy team and the match.
- **All Items:** stat filters on the left (Damage, Fire rate, Range,
  Handling, Health, Armor, Resist, Squad, Consumable), grid grouped by tier
  (Components / Assemblies / Signatures), recipe tree on the right with
  "builds into" below.
- **Item Sets:** today's My builds, renamed; keeps copy / paste.

## Delivery (each step its own commits, tests and screenshots)

1. GDD + registry rewrite of the item model, slots and recipes; content list
   (economy-designer + game-designer); owner sign-off.
2. Data + server: recipe fields on `ArmoryItemDef`, combine pricing, kit rail
   and body slots in `HeroProgress`, protocol 22 (new catalog, new slot
   bits), validator, hardening tests.
3. Advisor + bots: recipes in BuildAdvisor (buy components toward the next
   finished item), guides rewritten, balance report rerun.
4. Shop UI: three tabs, stat filters, recipe tree, Item Sets.
5. Visuals: component / assembly / signature parts on the gun, body gear
   on the 7 hero models (attach markers), all ammo tracers and impacts.
6. Balance pass, screenshots at 720p / 1080p, release (server + clients
   together).

## Open questions for the owner

- **Q1 Where do unfinished parts live?** (a) LoL-style kit rail with 3 free
  slots, parts shown on a belt / back rail; (b) a component sits directly in
  the socket it builds toward (no free slots, simpler, but no cross-socket
  recipes).
- **Q2 Body slots:** three typed slots (Plating / Shell / Ward) or two free
  defense slots?
- **Q3 First content size:** suggested 10 components, 10 assemblies, 14
  signatures, 6 ammo types, 5 ammo mods, 6 body items.
- **Q4 Release:** ship v2 as one release (protocol 22) or keep protocol 21
  live first and ship v2 later?
