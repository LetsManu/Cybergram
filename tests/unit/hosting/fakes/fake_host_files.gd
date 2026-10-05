extends MatchHostFiles
## In-memory MatchHostFiles for the W17-SUP tests (no disk I/O).

var store: Dictionary = {}  # path -> Dictionary or String
var flags: Dictionary = {}  # path -> true (drain file etc.)


func _init() -> void:
	super("mem://host")


func prepare() -> bool:
	return true


func write_secure(file_name: String, data: Dictionary) -> String:
	var p := run_dir.path_join(file_name)
	store[p] = data.duplicate(true)
	return p


func read_and_delete(path: String) -> Dictionary:
	var d: Variant = store.get(path, {})
	store.erase(path)
	return d if d is Dictionary else {}


func remove(path: String) -> void:
	store.erase(path)


func exists(path: String) -> bool:
	return flags.has(path) or store.has(path)


func write_atomic(path: String, text: String) -> bool:
	store[path] = text
	return true
