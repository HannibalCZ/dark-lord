extends RefCounted
class_name RegionQuery

var game: GameStateSingleton

# cache/indexy
var by_id: Array[Region] = []                 # indexované přímo region_id (rychlé)
var by_owner: Dictionary = {}                 # faction_id -> Array[Region]
var by_controller: Dictionary = {}            # faction_id -> Array[Region]
var by_kind: Dictionary = {}                  # "civilized"/"wildlands" -> Array[Region]

func _init(gs: GameStateSingleton) -> void:
	game = gs
	rebuild()

func rebuild() -> void:
	by_owner.clear()
	by_controller.clear()
	by_kind.clear()

	# copy pointerů na regiony (id -> region)
	by_id = game.region_manager.regions.duplicate()

	for r: Region in game.region_manager.regions:
		if r == null:
			continue

		# owner
		if not by_owner.has(r.owner_faction_id):
			by_owner[r.owner_faction_id] = []
		by_owner[r.owner_faction_id].append(r)

		# controller
		if not by_controller.has(r.controller_faction_id):
			by_controller[r.controller_faction_id] = []
		by_controller[r.controller_faction_id].append(r)

		# kind
		if not by_kind.has(r.region_kind):
			by_kind[r.region_kind] = []
		by_kind[r.region_kind].append(r)

func get_by_id(id: int) -> Region:
	if id >= 0 and id < by_id.size():
		return by_id[id]
	return null

func neighbors(id: int) -> Array[int]:
	# deterministické pořadí je dáno adjacency listem
	return game.region_manager.adjacency.get(id, [])

func are_adjacent(a: int, b: int) -> bool:
	var neigh: Array = game.region_manager.adjacency.get(a, [])
	return b in neigh

func regions_owned_by(faction_id: String) -> Array[Region]:
	return by_owner.get(faction_id, [])

func count_owned_by(faction_id: String) -> int:
	return regions_owned_by(faction_id).size()

func count_player_controlled_civilized() -> int:
	var pid := Balance.PLAYER_FACTION
	var total: int = 0
	for r: Region in by_id:
		if r == null:
			continue
		if r.region_kind != Balance.WIN_REGION_KIND:
			continue
		# vojenská kontrola
		if r.owner_faction_id == pid:
			total += 1
			continue
		# korupční kontrola — přímý výpočet fáze, ne přes by_controller cache
		var phase: int = r.get_corruption_phase_for(pid)
		if phase >= Balance.WIN_CORRUPTION_PHASE:
			total += 1
	return total

func count_total_civilized() -> int:
	var total: int = 0
	for r: Region in by_id:
		if r == null:
			continue
		if r.region_kind == Balance.WIN_REGION_KIND:
			total += 1
	return total

func count_player_owned_or_controlled() -> int:
	var pid := Balance.PLAYER_FACTION
	var owned: Array = by_owner.get(pid, [])
	var controlled: Array = by_controller.get(pid, [])

	# union bez duplicit (region může být zároveň owned i controlled)
	var seen := {}
	var c := 0
	for r in owned:
		if r == null: continue
		seen[r.id] = true
		c += 1
	for r in controlled:
		if r == null: continue
		if seen.has(r.id): continue
		seen[r.id] = true
		c += 1
	return c

# --- AI targeting ---

func find_nearest_with_filters(start_id: int, actor_faction_id: String, filters: Dictionary) -> int:
	if _matches_filters(start_id, actor_faction_id, filters):
		return start_id

	var visited := {}
	var q: Array[int] = []
	visited[start_id] = true
	q.append(start_id)

	while not q.is_empty():
		var cur: int = q.pop_front()
		for n in neighbors(cur):
			if visited.has(n):
				continue
			visited[n] = true

			if _matches_filters(n, actor_faction_id, filters):
				return n

			q.append(n)

	return -1

func _matches_filters(region_id: int, actor_faction_id: String, filters: Dictionary) -> bool:
	var r := get_by_id(region_id)
	if r == null:
		return false

	# region_kind
	if filters.has("region_kind"):
		if String(r.region_kind) != String(filters["region_kind"]):
			return false

	# owner_rule: any/self/not_self
	var owner_rule: String = String(filters.get("owner_rule", "any"))
	match owner_rule:
		"any":
			pass
		"self":
			if r.owner_faction_id != actor_faction_id:
				return false
		"not_self":
			if r.owner_faction_id == actor_faction_id:
				return false
		_:
			return false

	# controller_rule (volitelně, když budeš chtít)
	if filters.has("controller_rule"):
		var cr: String = String(filters.get("controller_rule", "any"))
		match cr:
			"any":
				pass
			"self":
				if r.controller_faction_id != actor_faction_id:
					return false
			"not_self":
				if r.controller_faction_id == actor_faction_id:
					return false
			_:
				return false

	# occupied_enemy_army: true = region obsahuje enemy army vůči actorovi
	if filters.get("occupied_enemy_army", false):
		if not game.query.units.has_enemy_army(region_id, actor_faction_id):
			return false

	# unoccupied_enemy_army: true = region NESMÍ obsahovat enemy army vůči actorovi
	if filters.get("unoccupied_enemy_army", false):
		if game.query.units.has_enemy_army(region_id, actor_faction_id):
			return false

	# has_lair: true = region musí mít lair (lair_id != "")
	if filters.get("has_lair", false):
		if not r.has_lair():
			return false

	return true

# Vrací region s nejvyšší korupcí hráčské frakce, který projde filters.
# Vrací -1 pokud žádný kandidát nemá korupci > 0.
func find_highest_corruption_with_filters(actor_faction_id: String, filters: Dictionary) -> int:
	var best_id: int = -1
	var best_corruption: float = 0.0
	for r: Region in by_id:
		if r == null:
			continue
		if not _matches_filters(r.id, actor_faction_id, filters):
			continue
		var corruption: float = r.get_corruption_for(Balance.PLAYER_FACTION)
		if corruption > best_corruption:
			best_corruption = corruption
			best_id = r.id
	return best_id

func find_next_step_towards(start_id: int, target_id: int) -> int:
	if start_id == target_id:
		return start_id

	var visited := {}
	var parent := {}
	var q: Array[int] = []

	visited[start_id] = true
	q.append(start_id)

	var found := false
	while not q.is_empty():
		var cur: int = q.pop_front()
		if cur == target_id:
			found = true
			break

		for n in neighbors(cur):
			if visited.has(n):
				continue
			visited[n] = true
			parent[n] = cur
			q.append(n)

	if not found:
		return -1

	var step := target_id
	while parent.has(step) and parent[step] != start_id:
		step = parent[step]

	if parent.has(step) and parent[step] == start_id:
		return step

	return -1
