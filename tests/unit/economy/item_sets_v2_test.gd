extends GdUnitTestSuite
## Armory v2 Item Sets (design/gdd/items-and-armory.md §3.9): file version 2,
## "CGB2:" strings round trip, "CGB1:" strings refused with "Made for the old
## Armory", version 1 files still read (as old-Armory builds), and the view
## model lists only the sets of the Armory in use.

const VESPER := &"hero_vesper_loom"

var _v22: ArmoryCatalogDef
var _v1: ArmoryCatalogDef
var _guides: RecommendedBuildsDef


func before_test() -> void:
	_v22 = load(ArmoryCatalogDef.V22_PATH) as ArmoryCatalogDef
	_v1 = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_guides = load(RecommendedBuildsDef.V22_PATH) as RecommendedBuildsDef


func _vm(store: CustomBuildStore) -> BuildsViewModel:
	var vm := BuildsViewModel.new(store, "")
	vm.setup(VESPER, _v22, CombatFixtures.vesper().weapon, _guides)
	return vm


func test_v2_set_round_trips_as_cgb2_with_finished_items() -> void:
	var store := CustomBuildStore.new()
	var vm := _vm(store)
	var e := vm.new_from_default()
	assert_int(e).is_equal(1)
	var b := vm.build_at(e)
	assert_int(int(b["armory"])).is_equal(CustomBuildStore.ARMORY_V2)
	var ids: Array = (b["steps"] as Array).map(func(s: Dictionary) -> String: return String(s["item"]))
	assert_array(ids).contains(["ember_heart"])  # finished items from the guide
	var text := vm.export_entry(e)
	assert_str(text).starts_with("CGB2:")
	var other := _vm(CustomBuildStore.new())
	var e2 := other.import_text(text)
	assert_int(e2).is_equal(1)
	assert_str(other.last_error).is_equal("")
	assert_array(other.build_at(e2)["steps"]).is_equal(b["steps"])
	# File: version 2, read back equal.
	var again := CustomBuildStore.new()
	assert_bool(again.from_json(store.to_json())).is_true()
	assert_str(again.to_json()).is_equal(store.to_json())
	assert_str(store.to_json()).contains('"version": 2')


func test_cgb1_strings_are_refused_as_old_armory() -> void:
	var old := CustomBuildStore.new()
	var id := old.create(VESPER, "old", CustomBuildStore.ARMORY_V1)
	old.add_step(id, &"ember_heart", 2)
	var text := old.export_string(id)
	assert_str(text).starts_with("CGB1:")
	var vm := _vm(CustomBuildStore.new())
	assert_int(vm.import_text(text)).is_equal(-1)
	assert_str(vm.last_error).is_equal(CustomBuildStore.ERR_OLD_ARMORY)
	assert_int(vm.entries().size()).is_equal(1)  # nothing added
	assert_int(vm.import_text("hello")).is_equal(-1)
	assert_str(vm.last_error).is_equal(CustomBuildStore.ERR_BAD)


func test_version_1_files_are_read_as_old_armory_builds() -> void:
	var v1 := '{"version": 1, "selected": {"hero_vesper_loom": "b1"}, "builds": [{"id": "b1", "hero": "hero_vesper_loom", "name": "old", "steps": [{"item": "ember_heart", "target": 2}]}]}'
	var store := CustomBuildStore.new()
	assert_bool(store.from_json(v1)).is_true()
	assert_int(int(store.builds[0]["armory"])).is_equal(CustomBuildStore.ARMORY_V1)
	# The v2 shop does not list or follow it; the v1 panel still does.
	var vm := _vm(store)
	assert_int(vm.entries().size()).is_equal(1)
	assert_object(vm.active_guide()).is_null()
	var vm1 := BuildsViewModel.new(store, "")
	vm1.setup(VESPER, _v1, CombatFixtures.vesper().weapon, load(RecommendedBuildsDef.DEFAULT_PATH))
	assert_int(vm1.entries().size()).is_equal(2)
	assert_str(vm1.active_id()).is_equal("b1")
	assert_object(vm1.active_guide()).is_not_null()
