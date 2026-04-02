extends Node
class_name RegionManager

var game_state: GameStateSingleton
var regions: Array[Region] = []
var adjacency: Dictionary = {}

var grid_w: int = 4
var grid_h: int = 3
var _use_explicit_neighbors: bool = false

func init_regions() -> void:
	regions.clear()
	adjacency.clear()

	load_map_from_json("res://data/maps/mvp_map.json")

	# adjacency se generuje až po načtení regionů (pokud není explicitní ze JSON)
	if not _use_explicit_neighbors:
		generate_grid_adjacency(grid_w, grid_h)

func init_regions_from_map(map_path: String) -> void:
	regions.clear()
	adjacency.clear()
	load_map_from_json(map_path)
	if not _use_explicit_neighbors:
		generate_grid_adjacency(grid_w, grid_h)

func load_map_from_json(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("Map JSON not found: %s" % path)
		return

	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()

	var parsed : Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON in %s" % path)
		return

	var data: Dictionary = parsed

	# meta
	var meta: Dictionary = data.get("meta", {})
	grid_w = int(meta.get("grid_w", 4))
	grid_h = int(meta.get("grid_h", 3))
	_use_explicit_neighbors = bool(meta.get("use_explicit_neighbors", false))

	# regions
	var arr: Array = data.get("regions", [])
	if arr.is_empty():
		push_error("Map has no regions: %s" % path)
		return

	# pro explicitní mapy počítáme regiony ze seznamu, ne z grid rozměrů
	var expected: int = arr.size() if _use_explicit_neighbors else grid_w * grid_h
	regions.resize(expected)

	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var rd: Dictionary = item

		var id: int = int(rd.get("id", -1))
		if id < 0 or id >= expected:
			push_warning("Region id out of range: %s" % str(id))
			continue

		var name: String = String(rd.get("name", "Region %d" % id))
		var owner: String = String(rd.get("owner_faction_id", "neutral"))
		var rtype: String = String(rd.get("region_type", "plains"))
		var kind: String = String(rd.get("region_kind", "civilized"))

		var r := Region.new(id, name, owner, rtype)
		r.region_kind = kind

		# Secret (optional)
		if rd.has("secret"):
			var sd: Dictionary = rd["secret"]
			r.secret_id = String(sd.get("id", ""))
			r.secret_known = bool(sd.get("known", false))
			r.secret_state = String(sd.get("state", "none"))
			r.secret_progress = int(sd.get("progress", 0))

		# Lair (optional)
		if rd.has("lair"):
			var ld: Dictionary = rd["lair"]
			r.lair_id = String(ld.get("id", ""))
			r.lair_control = String(ld.get("control", "neutral"))
			r.lair_influence = int(ld.get("influence", 0))

		# Position (optional, fallback Vector2i.ZERO)
		var pd: Dictionary = rd.get("position", {})
		r.position = Vector2i(int(pd.get("x", 0)), int(pd.get("y", 0)))

		regions[id] = r

	# safety: doplň prázdné sloty, pokud JSON nemá všechny regiony
	for i in regions.size():
		if regions[i] == null:
			regions[i] = Region.new(i, "Region %d" % i, "neutral", "plains")
			regions[i].region_kind = "civilized"

	# explicitní sousedství ze JSON (druhý průchod — všechny regiony již načteny)
	if _use_explicit_neighbors:
		for rd in arr:
			if typeof(rd) != TYPE_DICTIONARY:
				continue
			var id: int = int(rd["id"])
			var neighbors: Array = rd.get("neighbors", [])
			adjacency[id] = neighbors


func generate_grid_adjacency(w: int, h: int) -> void:
	adjacency.clear()
	var total := w * h

	for id in total:
		var x := id % w
		var y := id / w

		var neigh: Array[int] = []

		# left
		if x > 0:
			neigh.append(id - 1)
		# right
		if x < w - 1:
			neigh.append(id + 1)
		# up
		if y > 0:
			neigh.append(id - w)
		# down
		if y < h - 1:
			neigh.append(id + w)

		adjacency[id] = neigh

func count_player_owned_or_controlled() -> int:
	var pid := Balance.PLAYER_FACTION
	var c:int = 0
	for r: Region in regions:
		if r == null:
			continue
		# owner nebo controller
		if r.owner_faction_id == pid or r.controller_faction_id == pid:
			c += 1
	return c

func are_adjacent(a:int, b:int) -> bool:
	return adjacency.has(a) and b in adjacency[a]

func get_region(id: int) -> Region:
	if id >= 0 and id < regions.size():
		return regions[id]
	return null

func get_regions_by_faction(faction_id: String) -> Array[Region]:
	return regions.filter(func(r): return r.owner_faction_id == faction_id)

func count_player_regions() -> int:
	return regions.filter(func(r): return r.owner_faction_id == Balance.PLAYER_FACTION).size()

func find_nearest_region_with_filters(start_id: int, actor_faction_id: String, filters: Dictionary) -> int:
	# pokud start sám prochází, může být target
	if _region_matches_filters(start_id, actor_faction_id, filters):
		return start_id

	var visited: Dictionary = {}
	var q: Array[int] = []
	visited[start_id] = true
	q.append(start_id)

	while not q.is_empty():
		var cur: int = q.pop_front()
		var neigh: Array = adjacency.get(cur, [])

		for n in neigh:
			if visited.has(n):
				continue
			visited[n] = true

			if _region_matches_filters(n, actor_faction_id, filters):
				return n

			q.append(n)

	return -1
	
func _region_matches_filters(region_id: int, actor_faction_id: String, filters: Dictionary) -> bool:
	var r: Region = get_region(region_id)
	if r == null:
		return false

	# region_kind
	if filters.has("region_kind"):
		if String(r.region_kind) != String(filters["region_kind"]):
			return false

	# owner_rule
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

	# occupied: "true" znamená, že v regionu je cizí army (nepřítel) vůči ownerovi
	# (MVP definice, můžeš později změnit)

	return true

func find_next_step_towards(start_id: int, target_id: int) -> int:
	if start_id == target_id:
		return start_id

	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var q: Array[int] = []

	visited[start_id] = true
	q.append(start_id)

	var found := false
	while not q.is_empty():
		var cur: int = q.pop_front()
		if cur == target_id:
			found = true
			break

		var neigh: Array = adjacency.get(cur, [])
		for n in neigh:
			if visited.has(n):
				continue
			visited[n] = true
			parent[n] = cur
			q.append(n)

	if not found:
		return -1

	# jdi od targetu zpět, dokud nedojdeš na souseda startu
	var step := target_id
	while parent.has(step) and parent[step] != start_id:
		step = parent[step]

	if parent.has(step) and parent[step] == start_id:
		return step

	return -1
