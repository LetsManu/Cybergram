class_name AuthConfig
extends RefCounted
## Server account / transport-security settings from the command line and the
## environment (design/ux/lobby-and-social.md §6):
##   --tls-cert <pem>   / env CYBERGRAM_TLS_CERT   certificate chain (PEM), e.g. Let's Encrypt fullchain.pem
##   --tls-key <pem>    / env CYBERGRAM_TLS_KEY    private key (PEM), e.g. privkey.pem
##   --data-dir <dir>   / env CYBERGRAM_DATA_DIR   account files (default user://accounts; Docker: /data/accounts)
##   --crash-dir <dir>  / env CYBERGRAM_CRASH_DIR   opt-in crash reports (W15; default: crash_reports
##                      next to the data dir, Docker: /data/crash_reports); only with DTLS
##   --allow-guests     / env CYBERGRAM_ALLOW_GUESTS=1|true|yes   let players join without an account
##                      (default off; forced on while there is no TLS certificate, so the game stays playable)
## Flags win over env. Without a readable cert + key the server runs
## guest-only (no DTLS; login / register are refused, never sent in plain).
## Client side:
##   --dtls-ca <pem>     pin this certificate / CA (self-hosted servers, tests)
##   --dtls-insecure     DEBUG ONLY: accept any server certificate (client_unsafe);
##                       ignored (with a warning) in release exports (W11-Q1 SEC-005)
##   --no-dtls           connect in plain UDP (guest-only servers)
## Parsed here (not in LaunchConfig, a lead-owned file; see the L1 report).

const DEFAULT_DATA_DIR := "user://accounts"
const RULES_PATH := "res://assets/data/net/auth_rules.tres"

var cert_path: String = ""
var key_path: String = ""
var data_dir: String = DEFAULT_DATA_DIR
var ca_path: String = ""
var insecure: bool = false
var no_dtls: bool = false
var allow_guests: bool = false
## W15: folder for opt-in crash reports ("" = next to data_dir).
var crash_dir: String = ""
## Loaded server TLS (null = guest-only) and why it is missing.
var server_tls: TLSOptions
var tls_error: String = ""


## Parses `args` (user args) and `env` (name -> value; missing = unset).
## `debug_build`: 1 / 0 force debug / release (tests), -1 = OS.is_debug_build().
## --dtls-insecure only takes effect in a debug build.
static func parse(args: PackedStringArray, env: Dictionary, debug_build: int = -1) -> AuthConfig:
	var debug := OS.is_debug_build() if debug_build < 0 else debug_build == 1
	var c := AuthConfig.new()
	c.cert_path = str(env.get("CYBERGRAM_TLS_CERT", ""))
	c.key_path = str(env.get("CYBERGRAM_TLS_KEY", ""))
	var dd := str(env.get("CYBERGRAM_DATA_DIR", ""))
	if dd != "":
		c.data_dir = dd
	c.allow_guests = str(env.get("CYBERGRAM_ALLOW_GUESTS", "")).to_lower() in ["1", "true", "yes", "on"]
	c.crash_dir = str(env.get("CYBERGRAM_CRASH_DIR", ""))
	var i := 0
	while i < args.size():
		var has_value := i + 1 < args.size()
		match args[i]:
			"--tls-cert":
				if has_value:
					i += 1
					c.cert_path = args[i]
			"--tls-key":
				if has_value:
					i += 1
					c.key_path = args[i]
			"--data-dir":
				if has_value:
					i += 1
					c.data_dir = args[i]
			"--crash-dir":
				if has_value:
					i += 1
					c.crash_dir = args[i]
			"--dtls-ca":
				if has_value:
					i += 1
					c.ca_path = args[i]
			"--dtls-insecure":
				if debug:
					c.insecure = true
				else:
					push_warning("[net] --dtls-insecure is ignored in release builds")
			"--no-dtls":
				c.no_dtls = true
			"--allow-guests":
				c.allow_guests = true
		i += 1
	return c


## This process's settings (OS args + env).
static func from_os() -> AuthConfig:
	var env := {}
	for k in ["CYBERGRAM_TLS_CERT", "CYBERGRAM_TLS_KEY", "CYBERGRAM_DATA_DIR", "CYBERGRAM_ALLOW_GUESTS",
			"CYBERGRAM_CRASH_DIR"]:
		if OS.has_environment(k):
			env[k] = OS.get_environment(k)
	return parse(OS.get_cmdline_user_args(), env)


## Where crash reports are kept: crash_dir, or "crash_reports" next to data_dir.
func crash_reports_dir() -> String:
	return crash_dir if crash_dir != "" else data_dir.get_base_dir().path_join("crash_reports")


## W21-N1: folder of host password-reset requests ("admin" next to data_dir;
## Docker: /data/admin). See AccountAdmin.
func admin_dir() -> String:
	return data_dir.get_base_dir().path_join("admin")


## Loads the server certificate + key. Returns the TLSOptions or null
## (tls_error says why); null means guest-only.
func load_server_tls() -> TLSOptions:
	server_tls = null
	if cert_path == "" or key_path == "":
		tls_error = "no TLS certificate configured (--tls-cert / CYBERGRAM_TLS_CERT)"
		return null
	# The Docker image always sets the env: a missing file is normal (guest-only).
	if not FileAccess.file_exists(cert_path):
		tls_error = "no TLS certificate at %s" % cert_path
		return null
	if not FileAccess.file_exists(key_path):
		tls_error = "no TLS private key at %s" % key_path
		return null
	var cert := X509Certificate.new()
	if cert.load(cert_path) != OK:
		tls_error = "unreadable TLS certificate at %s" % cert_path
		return null
	var key := CryptoKey.new()
	if key.load(key_path) != OK:
		tls_error = "unreadable TLS private key at %s" % key_path
		return null
	tls_error = ""
	server_tls = TLSOptions.server(key, cert)
	return server_tls


## Hosts whose DTLS handshake failed this run (a server without a certificate
## yet): later links to them use plain UDP. Plain links never carry a password:
## the login screen offers guest play only (see MainMenu._show_login).
static var plain_hosts: Dictionary = {}


## Client TLS for `host`: null = plain UDP. IP addresses and localhost are
## plain unless a CA is pinned or --dtls-insecure is given; host names use
## DTLS with the system CA bundle (Let's Encrypt) and hostname check.
func client_tls_for(host: String) -> TLSOptions:
	if no_dtls or plain_hosts.has(host):
		return null
	if insecure:
		push_warning("[net] --dtls-insecure: the server certificate is NOT verified (debug only)")
		return TLSOptions.client_unsafe()
	if ca_path != "":
		var ca := X509Certificate.new()
		if ca.load(ca_path) == OK:
			return TLSOptions.client(ca)
		push_warning("[net] cannot read --dtls-ca %s; using the system CAs" % ca_path)
		return TLSOptions.client()
	if host.is_valid_ip_address() or host == "localhost":
		return null
	return TLSOptions.client()


## The account rules (data), or defaults.
static func rules() -> AuthRulesDef:
	var r := load(RULES_PATH) as AuthRulesDef if ResourceLoader.exists(RULES_PATH) else null
	return r if r != null else AuthRulesDef.new()
