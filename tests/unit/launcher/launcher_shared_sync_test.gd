extends GdUnitTestSuite
## The launcher reuses the game's login protocol scripts as copies in
## launcher/src/shared/. This suite fails when a copy drifted from its original:
## run launcher/tools/sync_shared.sh to fix it.

const LIST := "res://launcher/tools/shared_files.txt"
const DEST := "res://launcher/src/shared/"


func _entries() -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(LIST).split("\n"):
		var l := line.strip_edges()
		if l != "" and not l.begins_with("#"):
			out.append(l)
	return out


func test_list_is_not_empty() -> void:
	assert_int(_entries().size()).is_greater(0)


func test_every_copy_matches_its_original() -> void:
	var drifted: Array[String] = []
	for rel in _entries():
		var original := FileAccess.get_file_as_bytes("res://" + rel)
		var copy_path := DEST + rel.get_file()
		var copy := FileAccess.get_file_as_bytes(copy_path)
		if original.is_empty() or original != copy:
			drifted.append(rel)
	assert_array(drifted).is_empty()


const TREE_LIST := "res://launcher/tools/shared_tree_files.txt"


func test_every_ui_kit_copy_matches_its_original() -> void:
	var drifted: Array[String] = []
	var count := 0
	for line in FileAccess.get_file_as_string(TREE_LIST).split("\n"):
		var rel := line.strip_edges()
		if rel == "" or rel.begins_with("#"):
			continue
		count += 1
		for suffix in ["", ".import", ".uid"]:
			var original := FileAccess.get_file_as_bytes("res://" + rel + suffix)
			if suffix != "" and original.is_empty():
				continue
			if original != FileAccess.get_file_as_bytes("res://launcher/" + rel + suffix) or original.is_empty():
				drifted.append(rel + suffix)
	assert_int(count).is_greater(0)
	assert_array(drifted).is_empty()
