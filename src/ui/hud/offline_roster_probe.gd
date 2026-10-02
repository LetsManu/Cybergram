class_name OfflineRosterProbe
extends RefCounted
## Roster enrichment for OFFLINE sessions only (the server runs in-process):
## hero display name, level, Lumen and bot flag per net id, read-only from the
## session's ServerWorld. A networked client has no `server` and gets an
## invalid Callable; RosterTracker then shows replicated data only.
## TODO(net): replace with a replicated roster block (name, level, own-team
## Lumen) in SnapshotData; this probe is a slice-only shortcut.


## Callable(net_id) -> Dictionary, or an invalid Callable when not offline.
static func make(session: Node) -> Callable:
	var server := session.get("server") as ServerWorld if session != null else null
	if server == null or session.get("dedicated") == true:
		return Callable()
	var lc = session.get("launch_config")
	var bot_match: bool = lc != null and (lc.get("bots") == true or lc.get("bots_only") == true)
	var client := session.get("client") as ClientWorld
	return func(id: int) -> Dictionary:
		var h := server.hero(id)
		if h == null:
			return {}
		var d := {"name": h.combat.def.display_name if h.combat.def != null else ""}
		var own := client != null and client.session != null and client.session.own_net_id == id
		d["bot"] = bot_match and not own
		if server.progression != null:
			var p: HeroProgress = server.progression.progress.get(id)
			if p != null:
				d["level"] = p.level
				d["lumen"] = p.lumen
		return d
