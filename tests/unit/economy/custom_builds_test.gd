extends GdUnitTestSuite
## Private custom builds (CustomBuildStore, owner decision 2026-10-06: local
## `user://builds.json`): editing, versioned JSON round trip, damaged files,
## warnings that never edit the build, export / import strings, reset to the
## default guide, and that a selected build drives the same BuildAdvisor.

const VESPER := &"hero_vesper_loom"

var _cat: ArmoryCatalogDef
var _builds: RecommendedBuildsDef
var _ar: AdviceRulesDef


func before_test() -> void:
	_cat = load(ArmoryCatalogDef.DEFAULT_PATH) as ArmoryCatalogDef
	_builds = load(RecommendedBuildsDef.DEFAULT_PATH) as RecommendedBuildsDef
	_ar = load("res://assets/data/economy/advice_rules.tres") as AdviceRulesDef


func _sample(store: CustomBuildStore) -> String:
	var id := store.create(VESPER, "  Range poke  ")
	store.add_step(id, &"med_pack", 1, BuildNodeDef.Section.OPENING)
	store.add_step(id, &"ember_facet", 1, BuildNodeDef.Section.EARLY)
	store.add_step(id, &"ember_heart", 1, BuildNodeDef.Section.CORE, PackedStringArray(["tempest_heart"]), "spike")
	return id


func test_create_edit_and_select_a_build() -> void:
	var store := CustomBuildStore.new()
	var id := _sample(store)
	var b := store.find(id)
	assert_str(String(b["name"])).is_equal("Range poke")
	assert_int((b["steps"] as Array).size()).is_equal(3)
	assert_bool(store.move_step(id, 2, -1)).is_true()
	assert_str(String(b["steps"][1]["item"])).is_equal("ember_heart")
	assert_bool(store.move_step(id, 0, -1)).is_false()
	assert_bool(store.remove_step(id, 1)).is_true()
	assert_int((b["steps"] as Array).size()).is_equal(2)
	assert_bool(store.rename(id, "Lens first")).is_true()
	var copy := store.duplicate_build(id)
	assert_str(String(store.find(copy)["name"])).is_equal("Lens first (copy)")
	assert_bool(store.select(&"hero_brannoc", id)).is_false()  # another hero's build
	assert_bool(store.select(VESPER, copy)).is_true()
	assert_object(store.selected_guide(VESPER)).is_not_null()
	assert_bool(store.remove(copy)).is_true()
	assert_object(store.selected_guide(VESPER)).is_null()  # falls back to the default guide
	assert_int(store.for_hero(VESPER).size()).is_equal(1)


func test_json_round_trip_keeps_builds_selection_and_ids() -> void:
	var store := CustomBuildStore.new()
	var id := _sample(store)
	store.select(VESPER, id)
	var again := CustomBuildStore.new()
	assert_bool(again.from_json(store.to_json())).is_true()
	assert_str(again.to_json()).is_equal(store.to_json())
	# New ids never collide with loaded ones.
	assert_str(again.create(VESPER, "next")).is_not_equal(id)


func test_damaged_or_foreign_files_are_refused_and_change_nothing() -> void:
	var store := CustomBuildStore.new()
	var id := _sample(store)
	var before := store.to_json()
	for bad in ["", "{", "[]", '{"version": 3, "builds": []}', '{"version": 1, "builds": 7}']:
		assert_bool(store.from_json(bad)).is_false()
	assert_str(store.to_json()).is_equal(before)
	# Malformed entries are dropped, steps without an item are skipped.
	assert_bool(store.from_json('{"version": 1, "builds": [{"id": "b1", "hero": "hero_sable", "steps": [{"item": ""}, {"item": "med_pack", "target": 500}]}, 3, {"hero": ""}]}')).is_true()
	assert_int(store.builds.size()).is_equal(1)
	assert_int((store.builds[0]["steps"] as Array).size()).is_equal(1)
	assert_int(int(store.builds[0]["steps"][0]["target"])).is_equal(99)


func test_warnings_report_bad_references_without_editing() -> void:
	var store := CustomBuildStore.new()
	var cat := _cat.duplicate(true) as ArmoryCatalogDef
	cat.find(&"prism_eye").disabled = true
	var id := store.create(VESPER, "odd")
	store.add_step(id, &"removed_item", 1)
	store.add_step(id, &"prism_eye", 1)  # switched off
	store.add_step(id, &"ember_heart", 4)  # a Signature is bought once
	store.add_step(id, &"med_pack", 1, BuildNodeDef.Section.CORE, PackedStringArray(["ghost"]))
	var w := CustomBuildStore.warnings(store.find(id), cat, CombatFixtures.vesper().weapon)
	assert_int(w.size()).is_equal(4)
	assert_str(w[0]).contains("unknown item removed_item")
	assert_str(w[1]).contains("is not sold")
	assert_str(w[2]).contains("no tier")
	assert_str(w[3]).contains("unknown alternative ghost")
	assert_int((store.find(id)["steps"] as Array).size()).is_equal(4)  # nothing deleted
	assert_array(Array(CustomBuildStore.warnings(store.find(_sample(store)), _cat, CombatFixtures.vesper().weapon))).is_empty()


func test_export_and_import_strings() -> void:
	var store := CustomBuildStore.new()
	var id := _sample(store)
	var s := store.export_string(id)
	assert_str(s).starts_with(CustomBuildStore.EXPORT_PREFIX)
	assert_bool(s.contains("\n")).is_false()
	var other := CustomBuildStore.new()
	var nid := other.import_string("  " + s + "\n")
	assert_str(nid).is_not_empty()
	assert_array(other.find(nid)["steps"]).is_equal(store.find(id)["steps"])
	assert_str(other.import_string("hello")).is_equal("")
	assert_str(other.import_string(CustomBuildStore.EXPORT_PREFIX + "!!!")).is_equal("")


func test_reset_to_default_copies_the_guide_core_path() -> void:
	var store := CustomBuildStore.new()
	var id := store.create(VESPER, "mine")
	assert_bool(store.reset_to_default(id, _builds.for_hero(VESPER))).is_true()
	var steps: Array = store.find(id)["steps"]
	assert_str(String(steps[0]["item"])).is_equal("med_pack")
	assert_str(String(steps[1]["item"])).is_equal("ember_heart")
	for st in steps:
		assert_bool(String(st["item"]) in ["bastion_weave", "null_weave", "ammo_piercing"]).is_false()  # situational only


func test_selected_build_drives_the_advisor_in_order() -> void:
	var store := CustomBuildStore.new()
	var id := _sample(store)
	var g := CustomBuildStore.to_build_def(store.find(id))
	var st := BuildState.new()
	st.catalog = _cat
	st.weapon = CombatFixtures.vesper().weapon
	st.lumen = 5000
	var best := func() -> StringName: return _cat.at(BuildAdvisor.evaluate(g, st, _ar).best().item_index).id
	assert_str(String(best.call())).is_equal("med_pack")
	st.holdings[_cat.index_of(&"med_pack")] = 1
	assert_str(String(best.call())).is_equal("ember_facet")
	st.holdings[_cat.index_of(&"ember_facet")] = 1
	assert_str(String(best.call())).is_equal("ember_heart")
	st.holdings[_cat.index_of(&"tempest_heart")] = 1  # the alternative satisfies the last step
	assert_bool(BuildAdvisor.evaluate(g, st, _ar).advice.is_empty()).is_true()
	# ItemShopModel uses it in place of the default guide.
	var m := ItemShopModel.new(_cat, null, _builds, VESPER, st.weapon)
	m.set_custom_guide(g)
	assert_object(m.build()).is_same(g)
	m.set_custom_guide(null)
	assert_object(m.build()).is_same(_builds.for_hero(VESPER))


func test_file_save_and_load() -> void:
	var path := "user://custom_builds_test.json"
	var store := CustomBuildStore.new()
	_sample(store)
	assert_bool(store.save_file(path)).is_true()
	var again := CustomBuildStore.new()
	assert_bool(again.load_file(path)).is_true()
	assert_int(again.builds.size()).is_equal(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_bool(CustomBuildStore.new().load_file("user://does_not_exist.json")).is_true()
