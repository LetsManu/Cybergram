# Secondary motion: bone contract for the glb builder (W14-P2)

Runtime: `SecondaryMotion` (src/gameplay/views/models/secondary_motion.gd) scans the skeleton for
`Sec_<part>_<n>` bones and builds one `SpringBoneSimulator3D` per hero (Medium tier and up). No
`Sec_` bones = no simulator, zero cost. Today's glbs have none, so nothing swings yet.

## Naming
`Sec_<part>[_<side>]_<n>`, n = 1.. from root outwards; each chain is a straight parent -> child run.
Chain root (n=1) is parented to the body bone named below. Parts and tuning keys: coat, hood,
strap, thread, spool, halo, antenna, pack. A single-bone chain gets a 0.2 m virtual tip.
The bones must be skinned (weights on the dangling cloth / strap / prop mesh), and must be
excluded from the Hips-to-Weapon animation clips (no tracks, rest pose only) so the simulator owns them.

## Bones to add (budget: skeleton limit is 32; the art bible allows +10 secondary, raise it to 42)
| Hero | Chains | Parent | Bones |
|---|---|---|---|
| Vesper | Sec_coat_L, Sec_coat_R, Sec_coat_B (coat tails, 3 each) | Hips | 9 |
| Vesper | Sec_thread_1..2 (hanging threads, 3 each), Sec_spool_L/R (1 each) | UpperChest / Hips | 8 |
| Liora | Sec_halo_1 (halo, 1 bone with ring mesh), Sec_hood_1..2 (hood tips, 2 each) | Head / UpperChest | 5 |
| Hex | Sec_antenna_L/R (2 each), Sec_pack_1..2 (1 each) | Head / UpperChest | 6 |
| Ryker, Brannoc | Sec_strap_L/R (2 each), Sec_pack_1 | UpperChest | 5 |
| Sable, Juniper | Sec_coat_L/R (2 each), Sec_hood_1 (2) | Hips / Head | 6 |

Keep per-hero secondary bones <= 10 and skin weights to <= 4 influences as usual.
Chain length 0.15 to 0.35 m per bone reads best at third-person distance.

## Cost
One simulator per hero, Medium+ only, switched off beyond 25 m (`SecondaryMotion.FAR_M`).

## W16: baked cloth
Heroes on the gen pipeline can carry `Cloth_<part>_<chain>_<n>` bones instead: garments
simulated at build time and baked into the clips (design/art/baked-cloth.md). **A part
is either baked cloth or a `Sec_` spring, never both.** Vesper's coat moved from the
planned `Sec_coat_*` chains to baked cloth; `SecondaryMotion` ignores `Cloth_` bones.
