extends GdUnitTestSuite
## Data hook (art bible §13 swap path): every HeroDef / WeaponDef / WardlingDef
## in assets/data resolves to a procedural model through ModelCatalog, every
## hero's model holds the model of its WeaponDef, and the views swap their
## greybox for the model (HeroView, WardlingView, FirstPersonRig).

const HEROES_DIR := "res://assets/data/heroes/"
const WEAPONS_DIR := "res://assets/data/weapons/"
const WARDLINGS_DIR := "res://assets/data/wardlings/"


func _defs(dir: String, type: Variant) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"):
			continue
		var r := load(dir + f)
		if is_instance_of(r, type):
			out.append(r)
	return out


func test_every_hero_def_resolves_and_carries_its_weapon_model() -> void:
	var heroes := _defs(HEROES_DIR, HeroDef)
	assert_int(heroes.size()).is_greater(0)
	for h in heroes:
		var hd := h as HeroDef
		var k := ModelCatalog.hero_key(hd)
		assert_str(String(k)).override_failure_message("HeroDef %s has no model" % hd.id).is_not_empty()
		var m := HeroModelBuilder.build(k, ModelPalette.TEAM_CONCORD)
		add_child(auto_free(m))
		assert_object(m.weapon).is_not_null()
		if hd.weapon != null:
			assert_str(String(m.weapon.key)).is_equal(String(ModelCatalog.weapon_key(hd.weapon)))


func test_every_weapon_def_resolves_to_a_model_with_sockets() -> void:
	var weapons := _defs(WEAPONS_DIR, WeaponDef)
	assert_int(weapons.size()).is_greater(0)
	for w in weapons:
		var k := ModelCatalog.weapon_key(w as WeaponDef)
		assert_str(String(k)).override_failure_message("WeaponDef %s has no model" % (w as WeaponDef).id).is_not_empty()
		var wm := WeaponModelBuilder.build(k, false, ModelPalette.TEAM_SYNDICATE)
		add_child(auto_free(wm))
		assert_bool(wm.mana).is_equal((w as WeaponDef).feed_kind == WeaponDef.FeedKind.MANA)
		for s in WeaponModel.SOCKETS:
			assert_object(wm.socket(s)).is_not_null()


func test_every_wardling_def_resolves() -> void:
	var defs := _defs(WARDLINGS_DIR, WardlingDef)
	assert_int(defs.size()).is_greater(0)
	for d in defs:
		assert_str(String(ModelCatalog.wardling_key(d as WardlingDef))).is_not_empty()


func test_model_id_overrides_the_id() -> void:
	var hd := HeroDef.new()
	hd.id = &"hero_unknown_prototype"
	assert_str(String(ModelCatalog.hero_key(hd))).is_empty()
	hd.model_id = &"hex"
	assert_str(String(ModelCatalog.hero_key(hd))).is_equal("hex")


func test_hero_view_swaps_greybox_for_identity_model() -> void:
	var v := HeroView.new()
	add_child(auto_free(v))
	assert_object(v.model).is_not_null()  # baseline until identity is known
	v.set_hero(load(HEROES_DIR + "hero_brannoc.tres"), ModelPalette.TEAM_SYNDICATE)
	await get_tree().process_frame
	assert_str(String(v.model.key)).is_equal("brannoc")
	assert_int(v.model.team).is_equal(ModelPalette.TEAM_SYNDICATE)
	v.apply(Vector3(1, 0, 0), 0.5, true)
	assert_vector(v.scale).is_equal(Vector3.ONE)  # crouch is a pose on the model


func test_first_person_rig_builds_viewmodel_and_mounts_on_sockets() -> void:
	var rig := FirstPersonRig.new()
	rig.setup(LookSettings.new())
	add_child(auto_free(rig))
	var hd := load(HEROES_DIR + "hero_vesper_loom.tres") as HeroDef
	rig.set_weapon(hd.weapon, ModelCatalog.hero_key(hd), ModelPalette.TEAM_CONCORD)
	assert_object(rig.weapon_model).is_not_null()
	assert_bool(rig.gun.visible).is_false()
	var cat := load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	var ember: ArmoryItemDef
	for it in cat.items:
		if (it as ArmoryItemDef).id == &"ember_heart":
			ember = it
	rig.set_mounts([ember, null, null], PackedInt32Array([3, 0, 0]))
	assert_int(rig.mount_mesh_count()).is_equal(1)
	assert_int(rig.weapon_model.socket(&"socket_core").get_child_count()).is_equal(1)


func test_wardling_view_uses_model_and_hides_greybox() -> void:
	var v := WardlingView.new()
	add_child(auto_free(v))
	v.set_state(MapDef.TEAM_SYNDICATE, 1.0, 0)
	assert_object(v.model).is_not_null()
	assert_int(v.model.team).is_equal(MapDef.TEAM_SYNDICATE)
	assert_bool(v.model._pennant.visible).is_true()
	v.set_rewrite(true, false)
	assert_bool(v.is_elite()).is_true()
	assert_float(v.model.scale.x).is_equal_approx(1.0, 0.001)  # the view applies the x1.3
	v.set_tier(3)
	assert_int(v.model.tier).is_equal(3)
