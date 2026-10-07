class_name ArmoryValidator
extends RefCounted
## Checks Armory data for mistakes that would break purchases, the wire
## contract or build guides (docs/armory.md "Validating data"). Pure: reads
## resources, changes nothing. Run by tests/unit/economy/armory_validator_test.gd
## on the shipped data, so a bad item or guide fails CI.
##
## Example:
##   var r := ArmoryValidator.check(catalog, builds, heroes, BuildAdvisor.rule_ids())
##   for e in r["errors"]: push_error(e)

## Highest catalog index a mount/ammo item may have (ProgressState.mount_item is s8).
const MAX_MOUNT_INDEX := 127
## Squad items must sit below this index (ProgressState.owned_bits is u32).
const MAX_SQUAD_INDEX := 31
## Highest index the ACTION_BUY argument can carry (low byte).
const MAX_ITEM_INDEX := 255

const ITEM_TAGS := ["starter", "core", "defensive", "offensive", "utility", "counter", "luxury"]
const THREAT_TAGS := ["cc", "burst", "sustain", "weapon_dps", "skill_dps", "mobility", "zone", "squad", "frontline"]
const CATEGORIES := ["", "offense", "defense", "utility", "squad", "supply"]
const PHASES := ["", "early", "mid", "late"]
const MODES := ["5v5", "3v3", "custom", "bots"]
const ROLES := ["commander", "infiltrator", "trapper", "soldier", "tank", "healer", "hacker"]


## Validates `cat` and (optionally) `builds` against `heroes` and the known
## advice rule ids. Returns {"errors": PackedStringArray, "warnings": PackedStringArray}.
static func check(cat: ArmoryCatalogDef, builds: RecommendedBuildsDef = null,
		heroes: Array = [], rule_ids: PackedStringArray = PackedStringArray()) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	_check_catalog(cat, errors, warnings)
	for h in heroes:
		if h is HeroDef:
			_check_hero(h, errors)
	if builds != null:
		var hero_by_id := {}
		for h in heroes:
			if h is HeroDef:
				hero_by_id[h.id] = h
		var seen := {}
		for b in builds.builds:
			if b == null:
				errors.append("builds: null entry")
				continue
			var key := "%s/%s" % [b.hero_id, b.display_name]
			if seen.has(key):
				errors.append("build %s: duplicate hero + name" % key)
			seen[key] = true
			_check_build(b, cat, hero_by_id, rule_ids, errors, warnings)
	return {"errors": errors, "warnings": warnings}


static func _check_catalog(cat: ArmoryCatalogDef, errors: PackedStringArray, warnings: PackedStringArray) -> void:
	if cat == null:
		errors.append("catalog: missing")
		return
	var ids := {}
	var groups := {}
	for i in cat.items.size():
		var it: ArmoryItemDef = cat.items[i]
		if it == null:
			errors.append("item #%d: null" % i)
			continue
		var w := "item %s (#%d)" % [it.id, i]
		if it.id == &"":
			errors.append("item #%d: empty id" % i)
		elif ids.has(it.id):
			errors.append("%s: duplicate id" % w)
		ids[it.id] = i
		if i > MAX_ITEM_INDEX:
			errors.append("%s: index above the ACTION_BUY limit %d" % [w, MAX_ITEM_INDEX])
		if it.prices.is_empty():
			errors.append("%s: no prices" % w)
		for p in it.prices:
			if p <= 0:
				errors.append("%s: price %d must be positive" % [w, p])
		match it.kind:
			ArmoryItemDef.Kind.MOUNT, ArmoryItemDef.Kind.AMMO:
				if i > MAX_MOUNT_INDEX:
					errors.append("%s: mount index above %d (ProgressState.mount_item)" % [w, MAX_MOUNT_INDEX])
				if it.socket == ArmoryItemDef.Socket.NONE:
					errors.append("%s: mount without a socket" % w)
				for t in range(1, it.prices.size()):
					if it.prices[t] <= it.prices[t - 1]:
						errors.append("%s: tier %d price not above tier %d (impossible upgrade)" % [w, t + 1, t])
				if it.kind == ArmoryItemDef.Kind.MOUNT and it.stat != &"" and it.values.size() != it.prices.size():
					errors.append("%s: %d values for %d tiers" % [w, it.values.size(), it.prices.size()])
				if it.stat2 != &"" and it.values2.size() != it.prices.size():
					errors.append("%s: %d values2 for %d tiers" % [w, it.values2.size(), it.prices.size()])
			ArmoryItemDef.Kind.SQUAD:
				if i > MAX_SQUAD_INDEX:
					errors.append("%s: squad index above %d (ProgressState.owned_bits)" % [w, MAX_SQUAD_INDEX])
				if it.prices.size() != 1:
					errors.append("%s: squad upgrades have one price" % w)
				if it.socket != ArmoryItemDef.Socket.NONE:
					errors.append("%s: squad upgrade with a socket" % w)
			ArmoryItemDef.Kind.CONSUMABLE:
				if it.carry_limit <= 0:
					errors.append("%s: consumable needs carry_limit > 0" % w)
				if it.socket != ArmoryItemDef.Socket.NONE:
					errors.append("%s: consumable with a socket" % w)
		if it.kind != ArmoryItemDef.Kind.MOUNT and it.family != ArmoryItemDef.Family.ANY:
			errors.append("%s: only mount lines have a family" % w)
		if it.stat != &"" and StatCatalog.hero_index(it.stat) < 0:
			errors.append("%s: unknown stat %s" % [w, it.stat])
		if it.stat2 != &"" and StatCatalog.hero_index(it.stat2) < 0:
			errors.append("%s: unknown stat2 %s" % [w, it.stat2])
		for t in it.tags:
			if not ITEM_TAGS.has(t):
				errors.append("%s: unknown tag %s" % [w, t])
		for t in it.counter_tags:
			if not THREAT_TAGS.has(t):
				errors.append("%s: unknown counter tag %s" % [w, t])
		if not CATEGORIES.has(String(it.category)):
			errors.append("%s: unknown category %s" % [w, it.category])
		if not PHASES.has(String(it.phase)):
			errors.append("%s: unknown phase %s" % [w, it.phase])
		if it.unique_group != &"":
			var g: Array = groups.get(it.unique_group, [])
			g.append(it)
			groups[it.unique_group] = g
	# Requirements: known, same kind chain, no cycles.
	for it in cat.items:
		if it == null or it.requires == &"":
			continue
		if not ids.has(it.requires):
			errors.append("item %s: requires unknown item %s" % [it.id, it.requires])
		elif it.requires == it.id:
			errors.append("item %s: requires itself" % it.id)
	for it in cat.items:
		if it != null and _requires_cycle(cat, it):
			errors.append("item %s: requirement cycle" % it.id)
	# Unique groups: one effect may be held at a time, so every member must
	# share a socket (the socket rule enforces it) or be a squad upgrade.
	for g in groups:
		var members: Array = groups[g]
		if members.size() < 2:
			warnings.append("unique group %s has one member" % g)
			continue
		var socket: int = members[0].socket
		for m in members:
			if m.socket != socket or m.kind == ArmoryItemDef.Kind.CONSUMABLE:
				errors.append("unique group %s: %s cannot share it (different socket or consumable)" % [g, m.id])


static func _requires_cycle(cat: ArmoryCatalogDef, start: ArmoryItemDef) -> bool:
	var seen := {}
	var cur := start
	while cur != null and cur.requires != &"":
		if seen.has(cur.id):
			return true
		seen[cur.id] = true
		cur = cat.find(cur.requires)
		if cur == start:
			return true
	return false


static func _check_hero(h: HeroDef, errors: PackedStringArray) -> void:
	if h.roles.is_empty():
		errors.append("hero %s: no role" % h.id)
	for r in h.roles:
		if not ROLES.has(r):
			errors.append("hero %s: unknown role %s" % [h.id, r])
	for t in h.tags:
		if not THREAT_TAGS.has(t):
			errors.append("hero %s: unknown tag %s" % [h.id, t])


## Checks one item reference `item_id` at `target` for build `w`. Returns the item or null.
static func _check_ref(w: String, item_id: StringName, target: int, cat: ArmoryCatalogDef,
		hero: HeroDef, errors: PackedStringArray, warnings: PackedStringArray, strict_family: bool) -> ArmoryItemDef:
	var it := cat.find(item_id) if cat != null else null
	if it == null:
		errors.append("%s: unknown item %s" % [w, item_id])
		return null
	if it.disabled:
		errors.append("%s: item %s is disabled" % [w, item_id])
	match it.kind:
		ArmoryItemDef.Kind.MOUNT, ArmoryItemDef.Kind.AMMO:
			if target < 1 or target > it.tiers():
				errors.append("%s: %s tier %d outside 1..%d" % [w, item_id, target, it.tiers()])
		ArmoryItemDef.Kind.SQUAD:
			if target != 1:
				errors.append("%s: squad upgrade %s target must be 1" % [w, item_id])
		ArmoryItemDef.Kind.CONSUMABLE:
			if target < 1 or target > it.carry_limit:
				errors.append("%s: %s count %d outside 1..%d" % [w, item_id, target, it.carry_limit])
	if hero != null and hero.weapon != null and not it.fits(hero.weapon):
		var msg := "%s: %s does not fit %s's gun" % [w, item_id, hero.id]
		if strict_family:
			errors.append(msg)
		else:
			warnings.append(msg)
	return it


static func _check_build(b: RecommendedBuildDef, cat: ArmoryCatalogDef, hero_by_id: Dictionary,
		rule_ids: PackedStringArray, errors: PackedStringArray, warnings: PackedStringArray) -> void:
	var w := "build %s/%s" % [b.hero_id, b.display_name]
	var hero: HeroDef = hero_by_id.get(b.hero_id)
	if not hero_by_id.is_empty() and hero == null:
		errors.append("%s: unknown hero" % w)
	for m in b.modes:
		if not MODES.has(m):
			errors.append("%s: unknown mode %s" % [w, m])
	for r in b.roles:
		if not ROLES.has(r):
			errors.append("%s: unknown role %s" % [w, r])
	if b.item_ids.size() != b.targets.size():
		errors.append("%s: %d item_ids but %d targets" % [w, b.item_ids.size(), b.targets.size()])
	for s in b.steps():
		_check_ref("%s step %d" % [w, s], b.item_at(s), b.targets[s], cat, hero, errors, warnings, false)
	if not b.is_guide():
		if b.steps() == 0:
			errors.append("%s: empty build" % w)
		return
	var node_ids := {}
	for n in b.nodes:
		if n == null:
			errors.append("%s: null node" % w)
			continue
		if n.id == &"":
			errors.append("%s: node without id" % w)
		elif node_ids.has(n.id):
			errors.append("%s: duplicate node %s" % [w, n.id])
		node_ids[n.id] = n
	for n in b.nodes:
		if n == null:
			continue
		var nw := "%s node %s" % [w, n.id]
		var it := _check_ref(nw, n.item_id, n.target, cat, hero, errors, warnings, not n.fallback)
		for a in n.alternatives:
			_check_ref("%s alternative" % nw, StringName(a), n.target, cat, null, errors, warnings, false)
		for r in n.requires:
			if not node_ids.has(StringName(r)):
				errors.append("%s: requires unknown node %s" % [nw, r])
			elif StringName(r) == n.id:
				errors.append("%s: requires itself" % nw)
		for c in n.conditions:
			if not rule_ids.is_empty() and not rule_ids.has(c):
				errors.append("%s: unknown condition %s" % [nw, c])
		if n.max_s > 0 and n.max_s < n.min_s:
			errors.append("%s: window ends before it starts" % nw)
		# The catalog prerequisite must be reachable inside the guide (or be an
		# alternative path); otherwise the node can never be bought by following it.
		if it != null and it.requires != &"" and not _guide_has_item_before(b, n, it.requires):
			warnings.append("%s: needs %s, which no earlier node buys" % [nw, it.requires])
	for n in b.nodes:
		if n != null and _node_cycle(b, n):
			errors.append("%s node %s: prerequisite cycle (unreachable)" % [w, n.id])


static func _guide_has_item_before(b: RecommendedBuildDef, n: BuildNodeDef, item_id: StringName) -> bool:
	var stack: Array = Array(n.requires)
	var seen := {}
	while not stack.is_empty():
		var id := StringName(stack.pop_back())
		if seen.has(id):
			continue
		seen[id] = true
		var p := b.node(id)
		if p == null:
			continue
		if p.item_id == item_id or p.alternatives.has(String(item_id)):
			return true
		stack.append_array(Array(p.requires))
	return false


static func _node_cycle(b: RecommendedBuildDef, start: BuildNodeDef) -> bool:
	var stack: Array = Array(start.requires)
	var seen := {}
	while not stack.is_empty():
		var id := StringName(stack.pop_back())
		if id == start.id:
			return true
		if seen.has(id):
			continue
		seen[id] = true
		var p := b.node(id)
		if p != null:
			stack.append_array(Array(p.requires))
	return false
