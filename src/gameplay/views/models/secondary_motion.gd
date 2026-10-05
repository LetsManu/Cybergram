class_name SecondaryMotion
extends RefCounted
## Secondary motion (W14-P2): spring / jiggle chains on coat tails, straps, hood
## tips, Vesper's threads and spools, Liora's halo, antennae and backpack parts.
## Driven by one SpringBoneSimulator3D (4.4+, verified present in 4.7) per hero.
## Chains are discovered by bone name: `Sec_<part>_<n>` (n = 1.. along the chain,
## `part` may carry a side, e.g. Sec_coat_L_1). The contract with the glb builder
## is in design/art/secondary-motion.md. A glb without such bones gets no
## simulator at all (zero cost), so this is safe before P1 adds the bones.
## Tiers: Low off, Medium and up on; heroes beyond FAR_M are switched off.

const PREFIX := "Sec_"
const FAR_M: float = 25.0
## Spring tuning per part family: stiffness, drag, gravity (m/s^2 scale).
const PART_TUNING := {
	"coat": {"stiffness": 0.6, "drag": 0.35, "gravity": 0.6},
	"hood": {"stiffness": 0.8, "drag": 0.4, "gravity": 0.4},
	"strap": {"stiffness": 1.0, "drag": 0.5, "gravity": 0.5},
	"thread": {"stiffness": 0.25, "drag": 0.2, "gravity": 0.9},
	"spool": {"stiffness": 0.7, "drag": 0.4, "gravity": 0.5},
	"halo": {"stiffness": 1.4, "drag": 0.6, "gravity": 0.0},
	"antenna": {"stiffness": 1.2, "drag": 0.25, "gravity": 0.1},
	"pack": {"stiffness": 1.0, "drag": 0.5, "gravity": 0.4},
}
const DEFAULT_TUNING := {"stiffness": 0.8, "drag": 0.4, "gravity": 0.5}


## True for the tiers that run spring bones.
static func enabled_for(lvl: int) -> bool:
	return lvl >= GfxQuality.MEDIUM


## Groups bone names into chains: {chain id: [bone names ordered by n]}.
## Pure; unit-tested. Names not matching Sec_<part>_<n> are ignored.
static func find_chains(bone_names: PackedStringArray) -> Dictionary:
	var found := {}
	for n in bone_names:
		if not n.begins_with(PREFIX):
			continue
		var idx := n.rfind("_")
		var tail := n.substr(idx + 1)
		if idx <= PREFIX.length() or not tail.is_valid_int():
			continue
		var id := n.substr(0, idx)
		if not found.has(id):
			found[id] = []
		found[id].append([int(tail), n])
	var out := {}
	for id in found:
		var arr: Array = found[id]
		arr.sort_custom(func(a, b): return a[0] < b[0])
		out[id] = arr.map(func(p): return p[1])
	return out


## Part family of a chain id ("Sec_coat_L" -> "coat").
static func part_of(chain_id: String) -> String:
	return chain_id.trim_prefix(PREFIX).split("_")[0]


## Builds the simulator under `skeleton`; returns null when Low tier, the class
## is missing, or the skeleton has no Sec_ bones.
static func attach(skeleton: Skeleton3D, lvl: int) -> SpringBoneSimulator3D:
	if skeleton == null or not enabled_for(lvl) or not ClassDB.class_exists("SpringBoneSimulator3D"):
		return null
	var names := PackedStringArray()
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	var chains := find_chains(names)
	if chains.is_empty():
		return null
	var sim := SpringBoneSimulator3D.new()
	sim.name = "SpringBones"
	skeleton.add_child(sim)
	sim.setting_count = chains.size()
	var k := 0
	for id in chains:
		var bones: Array = chains[id]
		var t: Dictionary = PART_TUNING.get(part_of(id), DEFAULT_TUNING)
		sim.set_root_bone_name(k, bones[0])
		sim.set_end_bone_name(k, bones[bones.size() - 1])
		sim.set_stiffness(k, t.stiffness)
		sim.set_drag(k, t.drag)
		sim.set_gravity(k, t.gravity)
		sim.set_radius(k, 0.03)
		if bones.size() == 1:  # a lone bone needs a virtual tip to swing
			sim.set_extend_end_bone(k, true)
			sim.set_end_bone_length(k, 0.2)
		k += 1
	return sim


## Distance LOD: spring only near the camera.
static func should_run(dist_m: float) -> bool:
	return dist_m <= FAR_M
