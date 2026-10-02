class_name HudStrings
extends RefCounted
## HUD localisation: every HUD string is a key in assets/localization/hud.csv
## (columns keys,en; Godot imports it as hud.en.translation). ensure_loaded()
## registers the translation with the TranslationServer once; when the import
## has not produced the .translation yet (fresh clone, no --import), the CSV is
## parsed directly so tr() still resolves.

const CSV_PATH := "res://assets/localization/hud.csv"
const TRANSLATION_PATH := "res://assets/localization/hud.en.translation"

static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if ResourceLoader.exists(TRANSLATION_PATH):
		var t := load(TRANSLATION_PATH) as Translation
		if t != null:
			TranslationServer.add_translation(t)
			return
	var table := parse_csv(CSV_PATH)
	if table.is_empty():
		push_warning("HudStrings: no HUD translation (%s)" % CSV_PATH)
		return
	var tr_en := Translation.new()
	tr_en.locale = "en"
	for k in table:
		tr_en.add_message(k, table[k])
	TranslationServer.add_translation(tr_en)


## key -> English text from a "keys,en" CSV (RFC 4180 quoting). Empty on error.
static func parse_csv(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var header := f.get_csv_line()
	var col := header.find("en")
	if col < 0:
		return out
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > col and row[0] != "":
			out[row[0]] = row[col]
	return out
