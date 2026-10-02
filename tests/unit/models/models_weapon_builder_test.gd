extends GdUnitTestSuite
## WeaponModelBuilder (art bible §7.1, weapons-and-mods.md §3.6.1): all 7
## signature weapons expose the four mount sockets plus fx_muzzle / grip_l,
## stay under the viewmodel / 3P budgets, and E13 mounts attach to sockets.

const WEAPONS := [[&"threadcaster"], [&"whisperfang"], [&"tackhammer"], [&"breakline"], [&"ironmaw"],
	[&"halo_repeater"], [&"glitchcaster"]]


func _item(socket: ArmoryItemDef.Socket, family: ArmoryItemDef.Family, id: StringName) -> ArmoryItemDef:
	var it := ArmoryItemDef.new()
	it.id = id
	it.kind = ArmoryItemDef.Kind.MOUNT
	it.socket = socket
	it.family = family
	it.hue = Color(1.0, 0.7, 0.2)
	return it


@warning_ignore("unused_parameter")
func test_weapon_has_sockets_and_fits_budget(key: StringName, test_parameters := WEAPONS) -> void:
	for fp in [true, false]:
		var w := WeaponModelBuilder.build(key, fp, ModelPalette.TEAM_CONCORD)
		add_child(auto_free(w))
		for s in WeaponModel.SOCKETS:
			assert_object(w.socket(s)).is_not_null()
		assert_object(w.socket(&"fx_muzzle")).is_not_null()
		assert_object(w.socket(&"grip_l")).is_not_null()
		var budget := ModelCatalog.WEAPON_FP_TRI_BUDGET if fp else ModelCatalog.WEAPON_TP_TRI_BUDGET
		assert_int(w.triangle_count()).is_greater(100).is_less(budget)
		assert_int(w.mesh_instance_count()).is_less_equal(ModelCatalog.WEAPON_MESH_BUDGET)
		# muzzle is in front of the grip (forward = -Z)
		assert_float(w.socket(&"fx_muzzle").position.z).is_less(-0.3)


@warning_ignore("unused_parameter")
func test_tier3_mounts_attach_to_their_sockets(key: StringName, test_parameters := WEAPONS) -> void:
	var w := WeaponModelBuilder.build(key, true, ModelPalette.TEAM_SYNDICATE)
	add_child(auto_free(w))
	var fam := ArmoryItemDef.Family.CRYSTAL if w.mana else ArmoryItemDef.Family.CHIP
	var items := [_item(ArmoryItemDef.Socket.CORE, fam, &"ember_heart"), _item(ArmoryItemDef.Socket.BARREL, fam, &"focus_lens"),
		_item(ArmoryItemDef.Socket.FRAME, fam, &"flux_coil"), _item(ArmoryItemDef.Socket.CHAMBER, ArmoryItemDef.Family.ANY, &"ammo_sunder")]
	assert_int(w.set_mounts(items, PackedInt32Array([3, 3, 3, 3]))).is_equal(4)
	for s in WeaponModel.SOCKETS:
		assert_int(w.socket(s).get_child_count()).is_equal(1)
	assert_int(w.set_mounts([null, null, null, null], PackedInt32Array([0, 0, 0, 0]))).is_equal(0)


func test_tier_grows_mount_size_not_colour() -> void:
	var it := _item(ArmoryItemDef.Socket.CORE, ArmoryItemDef.Family.CRYSTAL, &"ember_heart")
	var sizes: Array[float] = []
	for t in [1, 2, 3]:
		var n := MountVisuals.build(it, t, true)
		add_child(auto_free(n))
		var box := AABB()
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			box = box.merge((mi as MeshInstance3D).get_aabb())
		sizes.append(box.size.length())
	assert_float(sizes[1]).is_greater(sizes[0])
	assert_float(sizes[2]).is_greater(sizes[1])
