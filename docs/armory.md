# Armory: items, build guides and recommendations

This is the working guide for Cybergram's Armory: the shop where heroes spend Lumen.
It covers item data, build guides, the recommendation rules and how to test them.
The plan and the decisions behind it are in
[`docs/plans/armory-build-system.md`](plans/armory-build-system.md).

There is one item system and one recommendation system:

| Piece | File | Runs on |
|---|---|---|
| Items | `ArmoryItemDef` in `assets/data/economy/armory_catalog_slice.tres` | both |
| Purchase rules | `Armory` (`src/gameplay/progression/armory.gd`), called by `ProgressionSystem` | server only |
| Build guides | `RecommendedBuildDef` + `BuildNodeDef` in `assets/data/economy/recommended_builds_slice.tres` | both |
| Recommendations | `BuildAdvisor` + `BuildState` (`src/gameplay/progression/`) | client (shop) and server (bots) |
| Rule tuning | `AdviceRulesDef` in `assets/data/economy/advice_rules.tres` | both |
| Data checks | `ArmoryValidator`, run by `tests/unit/economy/armory_validator_test.gd` | tests |
| Shop screen | `ShopModel` (logic) + `ArmoryPanel` (drawing, input) in `src/ui/hud/` | client |

The server is authoritative. The client only sends a request; the server checks
every rule and answers with a `HeroProgress.Result`.

## Equipment model

- **Mount lines** (`Kind.MOUNT`) sit in a socket (Core, Frame, Barrel) and have
  tiers I–III. Crystals fit Mana guns and Chips fit Mechanical guns.
- **Ammo** (`Kind.AMMO`) sits in the Chamber.
- **Squad upgrades** (`Kind.SQUAD`) last for the match.
- **Consumables** (`Kind.CONSUMABLE`) are carried up to `carry_limit`.

There is no generic six-slot inventory.

**Items on sale** (catalog order = wire id):

| # | Item | Kind / socket | Family | Effect (hero stat) |
|---|---|---|---|---|
| 0 | Med-Pack | Consumable | any | Heal over time |
| 1–2 | Squad Expansion I / II | Squad | any | Squad size |
| 3–4 | Reinforced Cores I / II | Squad | any | Wardling HP |
| 5 | Amplifier Emitters | Squad | any | `wardling_damage_mult` |
| 6 / 8 | Ember Heart / Overclock | Core | Crystal / Chip | `mod_damage` |
| 7 | Flux Coil | Frame | Crystal | Mana regen and delay |
| 9 | Quickload | Frame | Chip | `reload_time` |
| 10–11 | Piercing / Sunder | Ammo | any | Armor pen / anti-Wardling |
| 12 / 13 | Focus Lens / Rifling | Barrel | Crystal / Chip | `falloff_range` (falloff start and end) |
| 14 | Penetrator | Barrel | Chip | `armor_pen_bonus` (adds to ammo pen, cap 60%) |
| 15 | Bastion Weave | Frame | any | `weapon_damage_taken` |
| 16 | Null Weave | Frame | any | `skill_damage_taken` |
| 17 | Harmonic Tether | Squad | any | `wardling_speed_mult`, `wardling_leash_bonus` |
| 18 | Quick Mint | Squad | any | `mint_interval_mult`, `mint_guard` (5 s resist after minting) |
| 19 | Bulwark Protocol | Squad | any | `wardling_guard_dr` (in Hold / Go Capture) |

Where the stats are read: `ServerWorld._resolve_pellets` (falloff range, armor
pen), `HealthComponent.apply_damage` (damage taken by type),
`WardlingWorld._refresh_upgrades` copies the squad stats onto the `Squad`
each tick (speed, leash, mint interval, mint guard, guard DR).

**Known gaps.** The Armory has no per-hero restriction field, so the GDD's
"Focus Lens: not Hex" is kept by the guides only (Hex's guide has no Barrel
node). Bulwark's "+25% body-block radius" is not built yet.

**Rules** (`design/gdd/weapons-and-mods.md` §3.6.4):
- You can shop only in your own HQ zone and only while alive.
- Upgrading a line costs `list(new) − list(held)`.
- Buying into an occupied socket auto-sells the held mount.
- Anything bought during the current visit can be undone for 100%. Since
  v21 this includes squad upgrades and Med-Packs. A later sell of a mount
  pays 60%, rounded down to 5.
- The visit ends when you leave the zone or die.

## Wire contract (protocol 21)

- **Item ids.** An item's position in the catalog is its network id
  (`ACTION_BUY` argument, `ProgressState.mount_item`). Never reorder items:
  only append. `tests/unit/economy/armory_transactions_test.gd` pins the
  existing order.
- **Index limits** (the validator enforces them):
  - Squad upgrades must sit below index 32 (`owned_bits`).
  - Mounts must sit below index 128.
  - Every item must sit below index 256.
- **Requests:**
  - `ACTION_BUY` arg: `index | tier << 8`. Tier 0 means "the next tier".
  - `ACTION_SELL` arg: a socket (sell or undo a mount), or
    `InputCommand.UNDO_ITEM_FLAG | index` (undo a squad upgrade or Med-Pack
    bought this visit).
- **Results.** Every client Armory request bumps `ProgressState.shop_seq`
  and sets `shop_result`. The panel compares these to show the exact
  outcome (`ShopModel.result_key`).
- **Undo state.** `visit_owned_bits` and `visit_medpacks` say which squad
  upgrades and Med-Packs can still be undone.
- **Advisor signals.** `signals` carries the `SIG_*` bits for the advisor
  (below).

## Adding an item

1. **Design first.** Add the item to the owning GDD
   (`design/gdd/weapons-and-mods.md` or `wardlings-and-economy.md`). Price it
   inside its band (§19: Minor 250–400, Standard 600–900, Major 1,400–1,800)
   and update `design/registry/entities.yaml`.
2. **Add the data.** Append an `ArmoryItemDef` to the end of the catalog
   `.tres`. Fill in:
   - `id`, `display_name`, `effect_text`, `kind`, `socket`, `family`
   - `prices` (one per tier), and `stat`/`op`/`values` (plus `stat2` if needed)
   - `requires` and `carry_limit` where they apply
   - The guide fields: `category`, `tags`, `counter_tags`, `keywords`,
     `phase`, `beginner`, `situational`, `unique_group`, `explain_key`
3. **Add the text.** Give the `explain_key` (and `name_key`/`effect_key`,
   if used) an English line in `assets/localization/hud.csv`. Keys start with
   `HUD_`.
4. **Add the icon.** Give the item a glyph in `src/ui/hud/shop_icons.gd`.
5. **Check it.** Run the validator and the economy tests (see Testing).

**Adding a tier** to a line means adding one price and one value
(`values`/`values2`) to that item. Prices must rise from tier to tier, and the
validator checks this. Guides that target the new tier need `target = 4`.

## Build guides

A `RecommendedBuildDef` can be used in one of two ways:

- **Simple.** `item_ids`/`targets` is an ordered list. The shop recommends
  the first step not yet owned whose item fits the gun. This is the old
  behaviour, unchanged.
- **Guide.** `nodes` holds `BuildNodeDef`s. Fill these in for each node:

| Field | Meaning |
|---|---|
| `id` | Unique in the build; other nodes name it in `requires` |
| `item_id`, `target` | Own this item at this tier (mounts) or count (consumables) |
| `section` | OPENING, EARLY, SPIKE, CORE, SQUAD, CONSUMABLE, DEFENSIVE, OFFENSIVE, UTILITY, COUNTER, LATE |
| `priority` | Higher means sooner. Ties keep the data order |
| `requires` | Nodes that must be done (or no longer block) first |
| `alternatives` | Items that satisfy this node instead |
| `conditions` | Rule ids. If set, the node is situational and only offered while one of them matches |
| `reason_key` | "Why" text (falls back to the item's `explain_key`, then the section) |
| `core` | Counts toward build progress |
| `optional` | Never blocks later nodes |
| `fallback` | Offered only when an item in `requires` can't be bought by this hero (wrong family, disabled) |
| `skippable` | Later nodes go on once this node is outside its window or its conditions stopped matching |
| `min_s`/`max_s` | Match-time window |
| `expert` | Shown only in the expert detail view |

A guide never breaks when the player ignores it:
- An owned alternative satisfies its node.
- An item this hero can't buy counts as passed.
- Recommendations never block a purchase.

**Authoring all guides.** Edit the spec in `tools/armory/build_guides.py`,
then run `python3 tools/armory/build_guides.py`. It writes the `.tres`; you
can also edit that file in the Godot editor. Re-import afterwards (see
Commands) and run the validator.

**Adding a branch.** Add nodes with a `section`, `requires` pointing at the
node they follow, and, when the branch depends on the situation, `conditions`
and `skippable = true`.

## Custom builds (private, on this PC)

Players can keep their own builds next to the hero guide. They are stored in
`user://builds.json` only and never reach a server.

| Piece | File |
|---|---|
| Store, file format, export / import, warnings | `CustomBuildStore` (`src/gameplay/progression/custom_build_store.gd`) |
| My builds tab logic | `BuildsViewModel` (`src/ui/hud/builds_view_model.gd`) |
| Drawing and keys | `ArmoryPanel` (My builds tab) |

- **File.** Versioned JSON: `{"version": 1, "selected": {hero: id}, "builds": [...]}`.
  Each build has `id`, `hero`, `name`, `notes` and `steps`; a step is
  `{"item", "target", "section", "alts", "note"}`. A damaged or foreign file
  is refused and left on disk; the shop then starts with no custom builds.
- **Warnings, never deletions.** Unknown items, a tier the line does not have,
  an item that does not fit the gun, unknown alternatives: all are listed
  under the build, and the build is kept as written.
- **Using a build.** The build in use replaces the hero guide in the
  Recommended tab and the path strip. It becomes a guide of ordered nodes
  (each step needs the one before), so the same `BuildAdvisor` reads it.
  Alternatives work as in the guides.
- **Editing in the Armory** (My builds tab): Enter / A uses a build;
  N / L3 makes a new build from the hero guide's core path; D / R3
  duplicates; Delete / X twice deletes; C copies a build string, V pastes
  one (only builds for this hero are accepted). In the catalog tabs,
  + / RT adds the focused item (next tier) to the build in use and - / LT
  removes it. With the hero guide in use, + first makes a copy of it.
- **Sharing.** `CustomBuildStore.export_string()` gives one line
  (`CGB1:` + base64 JSON). There is no online sharing.
- **Not built yet.** Renaming and notes have store calls
  (`rename`, `set_notes`) but no text field in the panel; new builds are
  named "My build N".

## Bots

Bots shop through the same path as players (`BotBrain._decide_shop`). While on
the Armory pad (or in the Sanctum), a bot builds a `BuildState` from its server
wallet and both teams' heroes, asks `BuildAdvisor` for its hero's default
guide, and sends the top step as `ACTION_BUY`. It saves for that step rather
than buying something lower. It only re-evaluates when Lumen, purchases,
Med-Packs or the advice signals change, so a refused request is not repeated.
Each purchase is logged in the bot log (`t<tick> h<id> buy <item> x<target>
(<node>)`) and by the server's `armory.*` lines. Test:
`tests/integration/bots/bot_match_test.gd` (`test_bots_shop_their_guides_through_action_buy`).

## Recommendation rules (BuildAdvisor)

**Scoring.** A node's score is `priority` plus the bonus of every matched rule
(`AdviceRulesDef.bonus`). Three rules are added automatically:
`core_tier_ready`, `affordable_now` and `counters_enemy`. The latter matches
when the item's `counter_tags` meet the enemy team's tags.

**Headline reason.** The reason shown is the strongest situational rule
(`HUD_ADVICE_R_<RULE>`). Failing that, it is the node's `reason_key`, then
the item's `explain_key`, then the section text.

| Rule id | Matches when |
|---|---|
| `taking_weapon_damage` / `taking_skill_damage` | The server signal: gunfire or ability damage within `damage_window_s` of at least `damage_threshold_frac` × max HP |
| `died_often` | At least `deaths_threshold` deaths within `deaths_window_s` |
| `low_health` | HP below `low_health_frac` |
| `team_behind` / `team_ahead` | Resonance deficit ≥ `behind_deficit`, or average level lead ≥ `ahead_levels` |
| `objective_soon` | The next Surge is within `objective_soon_s` |
| `enemy_<tag>` | At least `enemy_tag_threshold` enemy heroes carry the tag (3v3 uses 1, 5v5 uses 2) |
| `team_lacks_sustain` / `team_lacks_frontline` | No allied healer / tank |
| `core_tier_ready`, `affordable_now`, `counters_enemy` | Automatic (see above) |

`HeroDef.tags` holds hero threat tags: cc, burst, sustain, weapon_dps,
skill_dps, mobility, zone, squad, frontline. `HeroDef.roles` holds roles.

**Adding a situational rule:**
1. Add the id to `BuildAdvisor.RULES` and its matching logic to
   `_rule_matches`.
2. If the rule needs server state, add a `SIG_*` bit and compute it in
   `ProgressionSystem.refresh_signals`.
3. Add its bonus to `advice_rules.tres` (`AdviceRulesDef.bonus`).
4. Add the reason text `HUD_ADVICE_R_<ID>` to `hud.csv`.
5. Add a test in `tests/unit/economy/build_advisor_test.gd`.

**Debugging a decision.** `BuildAdvisor.evaluate(...).trace` lists:
- every node offered, with its score, matched rules and cost;
- every node skipped, with the reason;
- the final pick.

## Testing purchases

All Armory tests can be run in one go:

```
$GODOT --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/economy --ignoreHeadlessMode -c
```

What each suite covers:

- `armory_test.gd`: the rules without a world.
- `armory_transactions_test.gd`:
  - undo, the result channel, forged and repeated requests
  - `price_of`, the wire round-trip, the pinned catalog order
- `armory_validator_test.gd`: the data checks.
- `armory_new_items_test.gd`: Barrel, Weave and squad items: stats, combat hooks, guide branches.
- `custom_builds_test.gd` and `builds_view_model_test.gd`: private builds and the My builds tab.
- `build_advisor_test.gd`: recommendations.
- `shop_model_test.gd`: shop logic.

## Balance check

`tools/balance/armory_report.gd` spends every hero's default guide along the
average-player Lumen curve (wardlings-and-economy.md §18; the model in
`tests/unit/economy/economy_curve_test.gd`). It buys through the same path as a
bot: `BuildState.from_hero`, then `BuildAdvisor.best()`, then `Armory.buy`.

```
$GODOT --headless --path . -s res://tools/balance/armory_report.gd -- --out docs/balance/armory-report.md
```

- **Runs:** slice rules and GDD defaults; always on the pad (when a step becomes
  affordable) or one visit every 180 s; no enemy threat tags or all six other
  heroes' tags.
- **Output:** the purchase timeline, first spike and core-done times, dead
  zones (over 240 s without a purchase), Lumen unspent at 30:00, items no guide
  names or no run buys, build overlap between heroes, and tier steps whose
  Lumen value is out of line.
- The report only observes. The economy designer's reading and proposals are
  in `docs/balance/armory-review.md`; canon values change through the GDD and
  `design/registry/entities.yaml` first.

Rerun the report after changing prices, items or guides.

## Screenshots

Each preset spawns the hero on the Armory pad with Lumen and opens the panel:

- `--map slice --debug-armory`: the Recommended tab.
- `--map slice --debug-armory-catalog`: the All tab with the expert detail.
- `--map slice --debug-armory-builds`: My builds with a sample build (in
  memory only; `user://builds.json` is not touched).

`RESOLUTION=1920x1080 tools/ci/capture_scene.sh "" out.png 120 --map slice --debug-armory`
renders at 1080p (720p by default). Run `--import` first after editing
`hud.csv`, or new keys show raw. The current set and the open issues are in
`docs/item-shop-polish.md`.

## Logs

The server writes one OpsLog line per Armory request:

- **Events:** `armory.buy`, `armory.sell`, `armory.undo`, or `armory.reject`
  with the result name.
- **Fields:** the hero net id (never account data), the hero def, the item,
  the result, and Lumen before and after.

Logging is switched by `ProgressionSystem.armory_log`. Lumen spent is kept per
hero in `HeroProgress.spent_lumen`.
