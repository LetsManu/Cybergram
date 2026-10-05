extends GdUnitTestSuite
## W15-UPD: optional content packs (src/core/boot/content_packs.gd) mount from a
## folder of .pck files, and a missing folder is a no-op (running from source).

const DIR := "user://w15_packs_test"


func after_test() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_missing_folder_mounts_nothing() -> void:
	assert_int(ContentPacks.mount_dir(ProjectSettings.globalize_path("user://w15_no_such_dir")).size()).is_equal(0)


func test_mounts_every_pck_in_the_folder() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var src := dir.path_join("payload.txt")
	var f := FileAccess.open(src, FileAccess.WRITE)
	f.store_string("w15 pack payload")
	f.close()
	var pk := PCKPacker.new()
	assert_int(pk.pck_start(dir.path_join("zz_test.pck"))).is_equal(OK)
	assert_int(pk.add_file("res://w15_pack_probe/payload.txt", src)).is_equal(OK)
	assert_int(pk.flush()).is_equal(OK)
	var junk := FileAccess.open(dir.path_join("notes.txt"), FileAccess.WRITE)
	junk.store_string("not a pack")
	junk.close()
	var got := ContentPacks.mount_dir(dir)
	assert_array(Array(got)).contains_exactly(["zz_test"])
	assert_str(FileAccess.get_file_as_string("res://w15_pack_probe/payload.txt")).is_equal("w15 pack payload")
