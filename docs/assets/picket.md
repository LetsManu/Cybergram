# Picket Wardling: design brief and review notes

## Brief

| | |
|---|---|
| Purpose | Every Wardling on the map (personal squads, Vanguard waves; C15). Up to ~110 at once. |
| Read | A 0.9 m hover-biped toy soldier (art bible §5.3): rounded shell, single holo-LED visor eye, a team mana core in a chrome cage front and back, stubby arms with an emitter, a back fin with tier pips. Never reads as a hero (V4). |
| Faction | Two bakes of the same geometry (§5.3, §10.6 "faction swap"): `picket_c` Concord white porcelain + gold trim + printed serial; `picket_s` Syndicate black iron + brass rivets + sprayed crew tag. |
| Classes | Personal: team owner band (sash); own squad adds a gold knot and a ground ring. Vanguard: pennant pole + flag + shoulder stripe, no sash. Elite (Vesper): gold threads + floating spindle. Turned: violet ring (procedural). |
| Tiers | II: shoulder plates, head crest, outer core ring, 2nd pip. III: + crown of three crystal shards in chrome claws, mana ribbon, 3rd pip. Scale 1.0 / 1.08 / 1.15. |
| Budget | 4k tris (art bible §10.6): body 2.5k; tier III + legs + sash = 3,958. Own-squad sash (+272) and Elite (+548) can exceed it on one Wardling at a time. One 1024 atlas per faction. Auto LODs at import. |
| Animation | Unchanged: procedural hover bob and leg swing (legs are separate pieces rebased to the hip). |
| Built by | `tools/art/world/picket.py` (pieces: body, tier2, tier3, leg_l, leg_r, sash, sash_own, pennant, elite). Optional pieces are baked apart so they do not shade the body. |

## Review log

Findings per iteration are appended below.
