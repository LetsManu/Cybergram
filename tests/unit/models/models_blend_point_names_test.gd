extends GdUnitTestSuite
## W21-U2: Godot 4.7 logs "add_blend_point: No name provided" for every
## unnamed blend point (about 30 lines at each game start). Every call in the
## game code must pass the point's name (4th argument).

const DIRS: Array[String] = ["res://src/gameplay/views/models", "res://src/gameplay/views"]


func test_every_add_blend_point_call_passes_a_name() -> void:
	var seen := 0
	for dir in DIRS:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			for line in FileAccess.get_file_as_string(dir.path_join(f)).split("\n"):
				if line.contains(".add_blend_point(") and not line.strip_edges().begins_with("#"):
					seen += 1
					# add_blend_point(node, pos, at_index, name): at least 3 top-level commas.
					assert_int(_top_level_commas(line.substr(line.find(".add_blend_point(") + 17))).is_greater_equal(3)
	assert_int(seen).is_greater(0)


func test_named_blend_point_keeps_its_name() -> void:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.add_blend_point(AnimationNodeAnimation.new(), 0.0, -1, &"idle")
	assert_str(String(bs.get_blend_point_name(0))).is_equal("idle")


func _top_level_commas(s: String) -> int:
	var depth := 0
	var n := 0
	for c in s:
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			if depth == 0:
				break
			depth -= 1
		elif c == "," and depth == 0:
			n += 1
	return n
