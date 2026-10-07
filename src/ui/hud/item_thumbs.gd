class_name ItemThumbs
extends Node
## Rendered item thumbnails for the Armory v2 shop (design/gdd/items-and-armory.md
## §3.9; owner mockup design/ux/reference/armory-v2-owner-mockup.webp): each
## recipe item's 3D part, built by the C6 visuals (MountVisuals for gun-socket
## parts, GearVisuals for open-slot items and belt components), is rendered
## once into a small SubViewport and its texture cached. The Crystal / Chip
## form follows the hero's gun (§3.3). Items without a mesh (ammo, mods, squad
## upgrades, the Med-Pack) and headless runs return null: the caller draws
## the ShopIcons line art instead.
##
## Example: var tex := thumbs.texture(catalog, index, true)

const SIZE: int = 160
## Camera direction (from the part towards the camera) and framing margin.
const VIEW_DIR := Vector3(0.55, 0.35, 1.0)
const MARGIN: float = 1.25

var _cache: Dictionary = {}


## Thumbnail of catalog item `index` in its Crystal (`mana`) or Chip form, or null.
func texture(cat: ArmoryCatalogDef, index: int, mana: bool) -> Texture2D:
	var key := "%d:%d" % [index, int(mana)]
	if _cache.has(key):
		return _cache[key]
	var it := cat.at(index) if cat != null else null
	var tex: Texture2D = null
	if it != null and it.is_recipe_item() and DisplayServer.get_name() != "headless" and is_inside_tree():
		tex = _render(it, mana)
	_cache[key] = tex
	return tex


func _render(it: ArmoryItemDef, mana: bool) -> Texture2D:
	var tier := BuildVisuals.visual_tier(it)
	var part: Node3D = GearVisuals.build(it, tier, mana, false) if it.uses_open_slot() \
		else MountVisuals.build(it, tier, mana)
	if part == null:
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(part)
	var box := AABB()
	var first := true
	for n in part.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if part is MeshInstance3D and (part as MeshInstance3D).mesh != null:
		var pb: AABB = part.global_transform * (part as MeshInstance3D).get_aabb()
		box = pb if first else box.merge(pb)
		first = false
	if first:
		vp.queue_free()
		return null
	part.position -= box.get_center()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	vp.add_child(key)
	key.look_at_from_position(Vector3(2.0, 3.0, 2.5), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.light_color = Color(0.6, 0.8, 1.0)
	vp.add_child(rim)
	rim.look_at_from_position(Vector3(-2.5, 1.0, -2.0), Vector3.ZERO, Vector3.UP)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var ext := maxf(box.size.x, maxf(box.size.y, box.size.z))
	cam.size = maxf(ext * MARGIN, 0.01)
	cam.near = 0.01
	cam.far = ext * 20.0 + 1.0
	vp.add_child(cam)
	cam.look_at_from_position(VIEW_DIR.normalized() * ext * 6.0, Vector3.ZERO, Vector3.UP)
	cam.current = true
	return vp.get_texture()
