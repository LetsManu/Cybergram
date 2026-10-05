class_name DeltaInstaller
extends RefCounted
## Swaps staged files into the installed game with a journal, so a failure
## part-way restores every file it already touched (W15-UPD).
##
##   <root>/game.stage/<path>   verified new files, ready to go in
##   <root>/game.undo/<path>    the old files moved aside during the swap
## Every step is a rename inside the install root (same drive), so each file
## switch is atomic and the whole set rolls back on the first error.

## Tests: make the swap fail after this many renames (-1 = never).
static var fail_after: int = -1


## Moves each `paths` entry from `stage_dir` into `game_dir` and moves each
## `remove` entry out of it. Returns "" on success (the undo folder is then
## deleted) or an error text after rolling everything back.
static func swap(game_dir: String, stage_dir: String, undo_dir: String,
		paths: PackedStringArray, remove: PackedStringArray) -> String:
	LauncherCore.remove_tree(undo_dir)
	var journal: Array = []  # [target, had_old, backup, removed_only]
	for rel in remove:
		var target: String = game_dir.path_join(rel)
		if not FileAccess.file_exists(target):
			continue
		var err: String = _aside(target, undo_dir.path_join(rel))
		if err != "":
			_roll_back(journal)
			return "cannot remove %s (%s)" % [rel, err]
		journal.append([target, true, undo_dir.path_join(rel), true])
		if _should_fail(journal):
			_roll_back(journal)
			return "cannot remove %s (simulated failure)" % rel
	for rel in paths:
		var target: String = game_dir.path_join(rel)
		var backup: String = undo_dir.path_join(rel)
		var had_old: bool = FileAccess.file_exists(target)
		if had_old:
			var aerr: String = _aside(target, backup)
			if aerr != "":
				_roll_back(journal)
				return "cannot replace %s (%s). Is the game still running?" % [rel, aerr]
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var rerr: Error = DirAccess.rename_absolute(stage_dir.path_join(rel), target)
		if rerr != OK:
			if had_old:
				DirAccess.rename_absolute(backup, target)
			_roll_back(journal)
			return "cannot install %s (%s)" % [rel, error_string(rerr)]
		journal.append([target, had_old, backup, false])
		if rel.ends_with(".x86_64") and OS.get_name() != "Windows":
			FileAccess.set_unix_permissions(target, 493)  # 0755
		if _should_fail(journal):
			_roll_back(journal)
			return "cannot install %s (simulated failure)" % rel
	LauncherCore.remove_tree(undo_dir)
	LauncherCore.remove_tree(stage_dir)
	return ""


static func _should_fail(journal: Array) -> bool:
	return fail_after >= 0 and journal.size() > fail_after


static func _aside(target: String, backup: String) -> String:
	DirAccess.make_dir_recursive_absolute(backup.get_base_dir())
	DirAccess.remove_absolute(backup)
	var err: Error = DirAccess.rename_absolute(target, backup)
	return "" if err == OK else error_string(err)


## Undo in reverse order: drop the new file, put the old one back.
static func _roll_back(journal: Array) -> void:
	for i in range(journal.size() - 1, -1, -1):
		var j: Array = journal[i]
		var target: String = j[0]
		if not bool(j[3]):
			DirAccess.remove_absolute(target)
		if bool(j[1]):
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			DirAccess.rename_absolute(String(j[2]), target)
