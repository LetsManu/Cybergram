# Connecting to a Cybergram server

Short version: **always connect with the server's name (`cyber.djboeck.at`),
never with a bare IP.** On your own network, make that name point to the NAS
with one line in your hosts file.

The launcher can check all of this for you: **Settings > Connection test**.

## Why a name is required

Online servers only accept encrypted connections (DTLS on UDP 7777, and on the
match ports 7800-7809). Encryption checks the server's certificate, and a
certificate is issued for a **name** (`cyber.djboeck.at`), not for an IP.

| You connect with | What happens |
|---|---|
| `cyber.djboeck.at:7777` | Encrypted. The certificate matches the name. Works. |
| `192.168.1.7:7777` (bare IP) | The game connects **unencrypted** (there is no name to check a certificate against). The server drops that, so you see a timeout: *"This address is an IP. Servers only accept encrypted connections..."*. |
| A different name than the certificate's | Encrypted, but the certificate check fails: *"The server's certificate is not valid for this address..."*. |

## Playing on the server's own network (hosts file)

At home the name usually resolves to your public IP, and many routers cannot
loop back to a machine on the same network ("NAT loopback" / "hairpin"). Fix:
make the name point straight to the NAS on your PC.

1. Open Notepad **as administrator** (Start, type Notepad, right click, *Run as administrator*).
2. File > Open: `C:\Windows\System32\drivers\etc\hosts` (choose *All files*).
3. Add one line at the end and save:
   ```
   192.168.1.7 cyber.djboeck.at
   ```
4. Open a command prompt and run `ipconfig /flushdns`.
5. Launcher > Settings > Connection test: the name lookup line should say
   `cyber.djboeck.at -> 192.168.1.7 (a local network address ...)`.

Linux / macOS: the same line in `/etc/hosts` (with `sudo`).

Remove the line again when you take the PC to another network.

## Connection test: what each line means

The test sends only encryption handshakes, no login and no account data.

| Line | FAIL means | Do this |
|---|---|---|
| Address | You entered an IP. | Use the name; hosts file on your own network. |
| Name lookup (DNS) | The name was not found. | Check internet and spelling; hosts file at home. |
| UDP port 7777: *no answer* | Nothing reached the server (silence). | Server running? Router / NAS forwards **UDP** 7777 (not TCP)? Firewall on the NAS? |
| UDP port 7777: *port closed* | The machine answered that nothing listens on that port. | Start the server; the compose mapping must be `7777:7777/udp`. |
| Encryption and certificate | The server answered, but its certificate is not valid for this name (or not trusted). | Use the name the certificate is for, or issue the certificate for this name (Let's Encrypt) and restart. |

When the hosts-file test fails, check in this order:

1. **NAS firewall / UDP mapping**: Connection test says *no answer* or *port closed*.
   On the NAS: `docker ps` shows `0.0.0.0:7777->7777/udp`; the NAS firewall
   allows UDP 7777 and 7800-7809 from the LAN.
2. **Certificate name**: Connection test says *certificate is not valid*. On the
   NAS: `openssl x509 -in tls/fullchain.pem -noout -subject -ext subjectAltName`
   must list `cyber.djboeck.at`.
3. **Name resolution on the PC**: Connection test name lookup does not show
   `192.168.1.7`. Re-check the hosts line, run `ipconfig /flushdns`, and make
   sure no VPN or browser "secure DNS" replaces it (the game uses the system
   resolver, so browser settings do not matter for the game itself).

## Server side: Portainer / NAS compose notes

The stack is `tools/server/docker-compose.yml` (Portainer: *Stacks > Add stack*,
paste or point at the repo).

- Ports must be **UDP**: `7777:7777/udp` and `7800-7809:7800-7809/udp`.
  Portainer's port editor defaults to TCP; switch each one to UDP.
- The certificate goes in the folder mounted at `/data/tls`
  (`CYBERGRAM_TLS_DIR`, default `./tls`): `fullchain.pem` + `privkey.pem`, issued
  for `cyber.djboeck.at`, readable by the container user. Without it the server
  runs guest-only.
- **`CYBERGRAM_PUBLIC_HOST=cyber.djboeck.at` (set it).** Clients are sent to the
  match processes by this name, so matches are encrypted too and the hosts-file
  line covers them. Without it, game clients up to v0.17.0 tried to join matches
  at an empty address (":7800") and dropped back to the menu; newer clients
  fall back to the name they used for the front.
- Never delete the `cybergram-data` volume (it holds every account).
- Operations endpoint (`/health`, `/metrics`) on TCP 8090: publish it on the LAN
  only (`CYBERGRAM_OPS_PUBLISH=192.168.1.7:8090`), never through the reverse proxy.

## Server side: rejected connections

The front counts refused connections in `/metrics` and writes one JSON log line
per reason at most every 10 s (a client retrying would otherwise flood the log):

```
cybergram_connections_rejected_total{reason="plain_udp"} 12
```

| `reason` | Meaning | Source address in the log |
|---|---|---|
| `plain_udp` | Unencrypted connect to the encrypted port (someone used a bare IP). | no (*) |
| `bad_certificate` | The client refused our certificate (name mismatch or untrusted). | no (*) |
| `handshake_other` | Another DTLS handshake error (`code` field has the engine text). | no (*) |
| `version_mismatch` | The client runs another protocol version (needs an update). | yes, masked |
| `auth` | Wrong credentials, locked account, or an invalid session. | yes, masked |

(*) The engine reports failed DTLS handshakes only as error text, without the
peer's address, so these lines carry `"source":"unknown"`.

Log line example:

```json
{"ts":1791298931.2,"level":"WARN","comp":"front","event":"connection_rejected","msg":"3 connection(s) rejected: auth","reason":"auth","count":3,"source":"203.0.113.0"}
```

Addresses are masked (GDPR: last IPv4 octet, or everything after the first
three IPv6 groups, set to zero). For troubleshooting set
`CYBERGRAM_LOG_FULL_IP=1` on the container to log full addresses; remove it
again afterwards. No account ids, names, passwords or tokens are logged.

## Icinga 2 checks

`/health` and the general checks are in `docs/monitoring.md`. For the reject
counter, use the `check_cybergram_metric` script from there (it reads the
counter's value since the server started):

```
object CheckCommand "cybergram_metric" {
  command = [ PluginDir + "/check_cybergram_metric", "$cg_url$", "$cg_metric$", "$cg_warn$", "$cg_crit$" ]
}

object Service "cybergram-rejects-plain" {
  host_name = "nas"
  check_command = "cybergram_metric"
  vars.cg_url = "http://192.168.1.7:8090/metrics"
  vars.cg_metric = "cybergram_connections_rejected_total\\{reason=\"plain_udp\"\\}"
  vars.cg_warn = 50
  vars.cg_crit = 500
  check_interval = 5m
}

object Service "cybergram-rejects-cert" {
  host_name = "nas"
  check_command = "cybergram_metric"
  vars.cg_url = "http://192.168.1.7:8090/metrics"
  vars.cg_metric = "cybergram_connections_rejected_total\\{reason=\"bad_certificate\"\\}"
  vars.cg_warn = 10
  vars.cg_crit = 100
  check_interval = 5m
}
```

The counters reset when the server restarts. PromQL for "rejects in the last
hour by reason": `sum by (reason) (increase(cybergram_connections_rejected_total[1h]))`.
A sudden rise of `bad_certificate` after a certificate renewal usually means the
new certificate is for the wrong name or the chain is incomplete.
