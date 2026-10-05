class_name LauncherDiagnostics
extends RefCounted
## Diagnostics zip for Settings > Support (W15) and the redacted payload of
## the opt-in crash report. Built only when the player clicks; the zip is
## never uploaded. Contents:
## - the launcher's and the game's Godot logs (user://logs, last LOG_TAIL_BYTES
##   of each file), with account tokens and passwords removed (redact());
## - basic system info (OS, CPU, RAM, GPU, locale, versions). No user name,
##   host name, device id or IP address.
## The crash report uses redact(text, true) ("strict"), which also removes IP
## addresses, player / account ids, e-mail addresses and the home folder.

const LOG_TAIL_BYTES: int = 2 * 1024 * 1024
const MAX_LOG_FILES: int = 12
const TOKEN_MARK: String = "[REDACTED-TOKEN]"
const SECRET_MARK: String = "[REDACTED]"

static var _rx: Dictionary = {}


static func _re(key: String, pattern: String) -> RegEx:
	if not _rx.has(key):
		var r: RegEx = RegEx.new()
		r.compile(pattern)
		_rx[key] = r
	return _rx[key]


## `text` without secrets: 64-hex tokens (session / launch tokens), the values
## of password / token / secret / key fields (key=value, key: value, JSON) and
## the launch hand-over variables. `strict` (crash reports) also removes IPv4 /
## IPv6 addresses, 32-hex player / account ids, e-mail addresses and `home`.
static func redact(text: String, strict: bool = false, home: String = "") -> String:
	var out: String = text
	out = _re("kv", "(?i)((?:password|passwd|pass|pw|token|secret|session|api[_-]?key|private[_-]?key|CYBERGRAM_LAUNCH_[A-Z_]+|CYBERGRAM_SESSION_[A-Z_]+)\"?\\s*[:=]\\s*\"?)([^\"\\s,;}&]+)").sub(out, "$1" + SECRET_MARK, true)
	out = _re("tok", "(?i)\\b[0-9a-f]{64}\\b").sub(out, TOKEN_MARK, true)
	out = _re("pem", "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----").sub(out, SECRET_MARK, true)
	if strict:
		out = _re("mail", "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}").sub(out, "[email]", true)
		out = _re("ip4", "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b").sub(out, "[ip]", true)
		out = _re("ip6", "(?i)\\b(?:[0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4}\\b").sub(out, "[ip]", true)
		out = _re("id", "(?i)\\b[0-9a-f]{32}\\b").sub(out, "[id]", true)
		if home.length() > 1:
			out = out.replace(home, "~")
	return out


## Basic system info (no user, host or device identifiers).
static func system_info(launcher_version: String, game_version: String) -> Dictionary:
	var mem: Dictionary = OS.get_memory_info()
	return {
		"os": OS.get_name(), "os_version": OS.get_version(), "distribution": OS.get_distribution_name(),
		"cpu": OS.get_processor_name(), "cpu_cores": OS.get_processor_count(),
		"ram_mb": int(int(mem.get("physical", 0)) / 1048576), "gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(), "renderer": RenderingServer.get_current_rendering_driver_name(),
		"locale": OS.get_locale(), "engine": Engine.get_version_info().get("string", ""),
		"launcher_version": launcher_version, "game_version": game_version,
		"created_unix": int(Time.get_unix_time_from_system()),
	}


## The game's user folder (a sibling of the launcher's: same OS data folder).
static func game_user_dir() -> String:
	return OS.get_user_data_dir().get_base_dir().path_join("Cybergram")


## Log files in `dirs` (absolute folders), newest first, at most MAX_LOG_FILES.
## Each entry: {zip_name, path}.
static func find_logs(dirs: Dictionary) -> Array:
	var out: Array = []
	for label: String in dirs:
		var d: String = String(dirs[label])
		if not DirAccess.dir_exists_absolute(d):
			continue
		var files: Array = []
		for f: String in DirAccess.get_files_at(d):
			if f.ends_with(".log") or f.ends_with(".txt"):
				files.append(f)
		files.sort()
		files.reverse()
		for f: String in files.slice(0, MAX_LOG_FILES / 2):
			out.append({"zip_name": "%s/%s" % [label, f], "path": d.path_join(f)})
	return out


## The last LOG_TAIL_BYTES of a file as text ("" when unreadable).
static func read_tail(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var n: int = f.get_length()
	if n > LOG_TAIL_BYTES:
		f.seek(n - LOG_TAIL_BYTES)
	return f.get_buffer(mini(n, LOG_TAIL_BYTES)).get_string_from_utf8()


## The default log folders: launcher and game.
static func default_log_dirs() -> Dictionary:
	return {"launcher": OS.get_user_data_dir().path_join("logs"), "game": game_user_dir().path_join("logs")}


## Redacted {name -> text} of everything that goes into a zip or report.
static func collect(log_dirs: Dictionary, info: Dictionary, strict: bool = false) -> Dictionary:
	var home: String = OS.get_environment("HOME") if OS.get_environment("HOME") != "" else OS.get_environment("USERPROFILE")
	var files: Dictionary = {"system.json": JSON.stringify(info, "  ")}
	for e: Dictionary in find_logs(log_dirs):
		files["logs/" + String(e.zip_name)] = redact(read_tail(String(e.path)), strict, home)
	files["README.txt"] = "Cybergram diagnostics. Logs with passwords and tokens removed, plus basic system\n" \
		+ "information. Created on your request; nothing was uploaded. Attach this file to a\n" \
		+ "support request only if you want to.\n"
	return files


## Writes `files` ({name -> text}) into a new zip in `folder`; returns its
## path or "" on failure.
static func write_zip(folder: String, files: Dictionary) -> String:
	if not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder) != OK:
		return ""
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var path: String = folder.path_join("cybergram-diagnostics-%s.zip" % stamp)
	var z: ZIPPacker = ZIPPacker.new()
	if z.open(path) != OK:
		return ""
	for name: String in files:
		z.start_file(name)
		z.write_file(String(files[name]).to_utf8_buffer())
		z.close_file()
	z.close()
	return path


## Default output folder: the user's Downloads, else the documents folder.
static func default_folder() -> String:
	var d: String = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if d == "" or not DirAccess.dir_exists_absolute(d):
		d = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if d == "" or not DirAccess.dir_exists_absolute(d):
		d = OS.get_user_data_dir()
	return d


## The crash report payload: strict redaction, JSON, gzip. Empty when it
## would exceed `max_bytes` even after dropping the oldest logs.
static func crash_payload(log_dirs: Dictionary, info: Dictionary, exit_code: int, max_bytes: int) -> PackedByteArray:
	var files: Dictionary = collect(log_dirs, info, true)
	files.erase("README.txt")
	var report: Dictionary = {"kind": "crash", "exit_code": exit_code, "files": files}
	var bytes: PackedByteArray = JSON.stringify(report).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	while bytes.size() > max_bytes and files.size() > 1:
		var biggest: String = ""
		for k: String in files:
			if k != "system.json" and (biggest == "" or String(files[k]).length() > String(files[biggest]).length()):
				biggest = k
		if biggest == "":
			break
		var txt: String = String(files[biggest])
		files[biggest] = txt.substr(txt.length() / 2) if txt.length() > 4096 else ""
		if String(files[biggest]) == "":
			files.erase(biggest)
		bytes = JSON.stringify(report).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return bytes if bytes.size() <= max_bytes else PackedByteArray()
