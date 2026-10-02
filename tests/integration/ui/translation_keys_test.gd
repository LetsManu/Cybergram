extends GdUnitTestSuite
## E12 localisation coverage: every HUD string key used in src/ui exists in
## assets/localization/hud.csv with English text, and every tr("...") literal in
## src/ui is a key (no raw English routed through tr()). Reads source files, so
## it lives under integration.

const CSV := "res://assets/localization/hud.csv"
const ROOT := "res://src/ui"


func _sources(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_sources(dir.path_join(d), out)


func _scan(pattern: String) -> Dictionary:
	var re := RegEx.create_from_string(pattern)
	var files: Array[String] = []
	_sources(ROOT, files)
	var found := {}
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			found[m.get_string(1)] = path
	return found


func test_csv_has_english_for_every_key() -> void:
	var table := HudStrings.parse_csv(CSV)
	assert_int(table.size()).is_greater(50)
	for k in table:
		assert_str(str(k)).starts_with("HUD_")
		assert_str(str(table[k]).strip_edges()).is_not_empty()


func test_every_hud_key_used_exists() -> void:
	var table := HudStrings.parse_csv(CSV)
	var used := _scan("\"(HUD_[A-Z0-9_]+)\"")
	assert_int(used.size()).is_greater(50)
	var missing: Array = []
	for k in used:
		if not table.has(k):
			missing.append("%s (%s)" % [k, used[k]])
	assert_array(missing).is_empty()


func test_tr_literals_are_keys() -> void:
	var literals := _scan("\\btr\\(\"([^\"]*)\"\\)")
	var bad: Array = []
	for k in literals:
		if not str(k).begins_with("HUD_"):
			bad.append("%s (%s)" % [k, literals[k]])
	assert_array(bad).is_empty()


func test_translation_server_resolves_keys() -> void:
	HudStrings.ensure_loaded()
	assert_str(TranslationServer.translate("HUD_RESPAWN_IN")).is_equal("RESPAWN IN %ds")
	assert_str(TranslationServer.translate("HUD_TEAM_1")).is_equal("SYNDICATE")
