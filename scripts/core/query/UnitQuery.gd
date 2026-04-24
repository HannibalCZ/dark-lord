extends RefCounted
class_name UnitQuery

var game: GameStateSingleton

# cache / indexy
var by_id: Dictionary = {}             # int -> Unit
var by_region: Dictionary = {}         # int -> Array[Unit]
var by_faction: Dictionary = {}        # String -> Array[Unit]

func _init(gs: GameStateSingleton) -> void:
	game = gs
	rebuild()

func rebuild() -> void:
	by_id.clear()
	by_region.clear()
	by_faction.clear()

	for u in game.unit_manager.units:
		by_id[u.id] = u

		if not by_region.has(u.region_id):
			by_region[u.region_id] = [] as Array[Unit]
		by_region[u.region_id].append(u)

		if not by_faction.has(u.faction_id):
			by_faction[u.faction_id] = [] as Array[Unit]
		by_faction[u.faction_id].append(u)

func get_by_id(id: int) -> Unit:
	return by_id.get(id, null)

func in_region(region_id: int, include_lost: bool = false) -> Array[Unit]:
	var raw: Array = by_region.get(region_id, [])
	if include_lost:
		var all: Array[Unit] = []
		all.assign(raw)
		return all
	var out: Array[Unit] = []
	for u in raw:
		if not u.is_lost:
			out.append(u)
	return out

func active_count_for_faction(faction_id: String) -> int:
	var arr: Array = by_faction.get(faction_id, [])
	var c := 0
	for u in arr:
		if not u.is_lost:
			c += 1
	return c

func count_units_by_faction_and_key(faction_id: String, unit_key: String) -> int:
	var faction_units: Array = by_faction.get(faction_id, [])
	var count: int = 0
	for u in faction_units:
		if u.unit_key == unit_key \
				and not u.is_lost:
			count += 1
	return count

func enemies_in_region(region_id: int, friendly_faction_id: String, only_armies: bool = false) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in in_region(region_id, false):
		if u.faction_id == friendly_faction_id:
			continue
		if only_armies and u.type != "army":
			continue
		out.append(u)
	return out

func has_enemy_army(region_id: int, friendly_faction_id: String) -> bool:
	for u in enemies_in_region(region_id, friendly_faction_id, true):
		return true
	return false

# query-style validace (bez side-effectů)
func can_move(unit_id: int, target_region_id: int) -> Dictionary:
	var u := get_by_id(unit_id)
	if u == null:
		return {"ok": false, "reason": "Jednotka neexistuje."}
	if u.is_lost:
		return {"ok": false, "reason": "Jednotka je ztracena."}
	if u.moves_left <= 0:
		return {"ok": false, "reason": "Jednotce došly tahy."}
	if not game.region_manager.are_adjacent(u.region_id, target_region_id):
		return {"ok": false, "reason": "Cílový region není sousední."}
	return {"ok": true}
