extends GdUnitTestSuite
## Armory "My builds" tab logic (BuildsViewModel): the default guide is
## always entry 0, new builds start from it, delete needs a second press,
## the focused item can be added / removed, paste only accepts this hero's
## builds, and the active guide follows the selection. Never writes a file
## (path "").

const VESPER := &"hero_vesper_loom"

var _vm: BuildsViewModel
var _cat: ArmoryCatalogDef


func before_test() -> void:
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_vm = BuildsViewModel.new(CustomBuildStore.new(), "")
	_vm.setup(VESPER, _cat, CombatFixtures.vesper().weapon, load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef)


func test_default_guide_is_first_and_active_until_a_build_is_used() -> void:
	var e := _vm.entries()
	assert_int(e.size()).is_equal(1)
	assert_str(String(e[0]["id"])).is_equal("")
	assert_bool(e[0]["active"]).is_true()
	assert_object(_vm.active_guide()).is_null()
	var i := _vm.new_from_default()
	assert_int(i).is_equal(1)
	assert_bool(_vm.entries()[1]["steps"] > 0).is_true()
	assert_bool(_vm.use(i)).is_true()
	assert_bool(_vm.entries()[1]["active"]).is_true()
	assert_object(_vm.active_guide()).is_not_null()
	assert_bool(_vm.use(0)).is_true()
	assert_object(_vm.active_guide()).is_null()


func test_delete_needs_a_second_press_on_the_same_build() -> void:
	var a := _vm.new_from_default()
	var b := _vm.duplicate_entry(a)
	assert_int(b).is_equal(2)
	assert_bool(_vm.delete_entry(0)).is_false()  # the default guide cannot be deleted
	assert_bool(_vm.delete_entry(a)).is_false()  # armed
	assert_bool(_vm.delete_entry(b)).is_false()  # another build re-arms
	assert_bool(_vm.delete_entry(b)).is_true()
	assert_int(_vm.entries().size()).is_equal(2)


func test_add_item_starts_a_build_when_none_is_active_and_remove_takes_it_back() -> void:
	var item := _cat.index_of(&"ammo_sunder")  # not in the default guide's core path
	var n := _vm.add_item(item, 2)
	assert_bool(n > 0).is_true()
	assert_str(_vm.active_id()).is_not_empty()
	var steps: Array = _vm.store.find(_vm.active_id())["steps"]
	assert_str(String(steps[-1]["item"])).is_equal("ammo_sunder")
	assert_int(int(steps[-1]["target"])).is_equal(2)
	assert_int(int(steps[-1]["section"])).is_equal(BuildNodeDef.Section.CORE)
	assert_bool(_vm.remove_item(item)).is_true()
	assert_int((_vm.store.find(_vm.active_id())["steps"] as Array).size()).is_equal(n - 1)
	assert_bool(_vm.remove_item(item)).is_false()
	assert_int(_vm.add_item(-5, 1)).is_equal(-1)


func test_paste_accepts_only_this_heros_builds() -> void:
	var i := _vm.new_from_default()
	var text := _vm.export_entry(i)
	assert_int(_vm.import_text(text)).is_equal(2)
	var other := BuildsViewModel.new(CustomBuildStore.new(), "")
	other.setup(&"hero_brannoc", _cat, CombatFixtures.brannoc().weapon, _vm.defaults)
	assert_int(other.import_text(text)).is_equal(-1)
	assert_int(other.store.builds.size()).is_equal(0)
	assert_str(_vm.export_entry(0)).is_equal("")  # the default guide is not exported


func test_warnings_show_on_entries() -> void:
	var cat := _cat.duplicate(true) as ArmoryCatalogDef
	cat.find(&"prism_eye").disabled = true  # switched off by the server
	_vm.setup(VESPER, cat, CombatFixtures.vesper().weapon, load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef)
	var i := _vm.new_from_default()
	_vm.use(i)
	_vm.add_item(cat.index_of(&"prism_eye"), 1)
	var w: PackedStringArray = _vm.entries()[i]["warnings"]
	assert_int(w.size()).is_equal(1)
	assert_str(w[0]).contains("is not sold")
