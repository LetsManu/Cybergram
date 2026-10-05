extends SceneTree
## Host tool (W21-N1): reset a player's password from the server console.
## In the Docker image:
##   docker exec cybergram /opt/cybergram/Cybergram.x86_64 --headless \
##     --script res://src/networking/auth/account_admin_cli.gd -- --admin-reset-password <username>
## From a source checkout:
##   godot --headless --path . --script res://src/networking/auth/account_admin_cli.gd -- \
##     --admin-reset-password <username> [--data-dir <dir>]
## Accounts folder: --data-dir, else CYBERGRAM_DATA_DIR (Docker: /data/accounts),
## else user://accounts (AuthConfig). The reset itself is applied by the
## running server (AccountAdmin explains why); this tool waits for it up to
## AuthRulesDef.admin_wait_s. It prints the new recovery code exactly once
## and the account's 4-character tag, nothing else about the account.
## Exit codes: 0 done (or queued for the next server start), 1 usage /
## write error, 2 no such account, 3 refused by the server.

const USAGE := "usage: --admin-reset-password <username> [--data-dir <dir>]"


func _initialize() -> void:
	quit(run(OS.get_cmdline_user_args()))


## Runs the tool on `args` (user args); returns the exit code.
func run(args: PackedStringArray) -> int:
	var i := args.find("--admin-reset-password")
	if i < 0 or i + 1 >= args.size() or args[i + 1].begins_with("--"):
		printerr(USAGE)
		return 1
	var username := args[i + 1].strip_edges()
	var auth := AuthConfig.from_os()
	var rules := AuthConfig.rules()
	var a := AccountAdmin.find_username_readonly(auth.data_dir, username)
	if a.is_empty():
		printerr("No account with that username in %s." % auth.data_dir)
		return 2
	var tag := PlayerProfile.tag_of(str(a.get("id", "")))
	var made := AccountAdmin.make_reset(username, rules, int(Time.get_unix_time_from_system()))
	var dir := auth.admin_dir()
	var id := AccountAdmin.submit(dir, made.request)
	if id == "":
		printerr("Cannot write the reset request into %s." % dir)
		return 1
	print("Reset requested for account #%s; waiting for the server ..." % tag)
	var res := AccountAdmin.wait_result(dir, id, rules.admin_wait_s)
	if not res.is_empty() and not bool(res.get("ok", false)):
		printerr("The server refused the reset: %s. No code was issued." % str(res.get("error", "?")))
		return 3
	if res.is_empty():
		print("The server did not answer within %d s (is it running?). The reset stays queued and" % int(rules.admin_wait_s))
		print("is applied when the server next starts; the code below works from then on.")
	else:
		print("Done: the old password of account #%s no longer works and its sessions ended." % tag)
	print("")
	print("Recovery code (give it to the player; it is shown only this once):")
	print("")
	print("    %s" % made.code)
	print("")
	print("The player chooses \"Forgot password?\" at login (game or launcher) and enters the")
	print("username, this code and a new password.")
	return 0
