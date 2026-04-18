extends Resource
class_name UnitManager

var game_state: GameStateSingleton

var units: Array[Unit] = []
var unit_limit: int = 3
var _id_counter:int = 0

func init_empty() -> void:
	units.clear()
	_id_counter = -1

func recompute_id_counter() -> void:
	var max_id: int = -1
	for u in units:
		if u.id > max_id:
			max_id = u.id
	_id_counter = max_id

func get_active_unit_count_for(faction_id: String) -> int:
	if game_state != null and game_state.query != null:
		return game_state.query.units.active_count_for_faction(faction_id)
	# fallback
	return units.filter(func(u): return u.state != "lost" and u.faction_id == faction_id).size()

func _result_ok(payload: Dictionary = {}, events: Array = [], logs: Array = []) -> Dictionary:
	payload["ok"] = true
	payload["events"] = events
	payload["logs"] = logs
	return payload

func _result_err(reason: String, type: String = "warn") -> Dictionary:
	return {
		"ok": false,
		"type": type,
		"text": "⚠ " + reason,
		"reason": reason,
		"events": [],
		"logs": []
	}

func recruit_unit(faction_id:String, unit_key:String, spawn_region_id:int) -> Dictionary:
	# 1) cap / limit
	if get_active_unit_count_for(faction_id) >= unit_limit:
		return _result_err("Limit jednotek dosažen.")

	# 2) načti config
	var cfg:Dictionary = Balance.UNIT.get(unit_key, {})
	if cfg.is_empty():
		return _result_err("Neznámý typ jednotky: %s" % unit_key)

	# 3) frakce
	var fac: Faction = game_state.faction_manager.get_faction(faction_id)
	if fac == null:
		return _result_err("Neznámá frakce: %s" % faction_id)

	# 4) náklady
	var cost: Dictionary = cfg.get("recruit_cost", {})
	var gold_cost: float = float(cost.get("gold", 0))
	var mana_cost: float = float(cost.get("mana", 0))

	if fac.get_resource("gold") < gold_cost or fac.get_resource("mana") < mana_cost:
		return _result_err("Nedostatek surovin.")

	# 5) odečet
	if gold_cost > 0.0:
		fac.change_resource("gold", -gold_cost)
	if mana_cost > 0.0:
		fac.change_resource("mana", -mana_cost)

	# 6) vytvoř jednotku s unikátním ID
	var new_id: int = _next_unit_id()
	var u: Unit = Unit.new().init(new_id, unit_key, spawn_region_id, faction_id)
	units.append(u)

	var logs := [
		{"type":"unit", "text":"✅ Rekrutována jednotka: %s" % u.name}
	]
	var events := [
		{"type":"unit_added", "unit_id": new_id}
	]

	return _result_ok({
		"type": "recruit",
		"unit_id": new_id,
		"name": u.name,
		"faction_id": faction_id
	}, events, logs)

func spawn_unit_free(faction_id:String, unit_key:String, spawn_region_id:int) -> Dictionary:
	# 1) najdi definici jednotky
	var cfg:Dictionary = Balance.UNIT.get(unit_key, {})
	if cfg.is_empty():
		return _result_err("Lair: neznámý typ jednotky: %s" % unit_key)

	# 2) zkontroluj frakci
	var fac: Faction = game_state.faction_manager.get_faction(faction_id)
	if fac == null:
		return _result_err("Lair: neznámá frakce: %s" % faction_id)

	# 3) vytvoř jednotku bez nákladů a limitů
	var new_id: int = _next_unit_id()
	var u: Unit = Unit.new().init(new_id, unit_key, spawn_region_id, faction_id)
	units.append(u)

	var logs := [
		{"type":"unit", "text":"☠ Z doupěte povstala jednotka: %s" % u.name}
	]
	var events := [
		{"type":"unit_added", "unit_id": new_id}
	]

	return _result_ok({
		"type": "spawn",
		"unit_id": new_id,
		"unit_key": unit_key,
		"faction_id": faction_id,
		"region_id": spawn_region_id
	}, events, logs)

func _next_unit_id() -> int:
	_id_counter += 1
	return _id_counter

func can_move(unit_id:int, target_region_id:int) -> Dictionary:
	return game_state.query.units.can_move(unit_id, target_region_id)

func apply_post_move_effects(unit_id:int, from_region:int, to_region:int) -> Dictionary:
	var u : Unit = null
	if game_state != null and game_state.query != null:
		u = game_state.query.units.get_by_id(unit_id)

	if u == null:
		return { "ok": false, "reason": "Jednotka neexistuje." }

	var r: Region = game_state.region_manager.get_region(to_region)
	if r == null:
		return { "ok": false, "reason": "Cílový region neexistuje." }

	# zjisti, jestli je v cílovém regionu nepřátelská armáda
	var enemy_army_here := false
	if game_state != null and game_state.query != null:
		enemy_army_here = game_state.query.units.has_enemy_army(to_region, u.faction_id)
	else:
		# fallback (jen kdyby query ještě nebyla vždy ready)
		for other in units:
			if other.region_id == to_region and other.type == "army" and other.state != "lost" and other.faction_id != u.faction_id:
				enemy_army_here = true
				break

	var result: Dictionary = { "ok": true }

	# jednoduché pravidlo: armáda bez odporu → zabere region
	if u.type == "army" and not enemy_army_here and r.owner_faction_id != u.faction_id:
		game_state.region_manager.claim_region(r.id, u.faction_id)
		result["region_captured"] = true
		result["captured_region_id"] = to_region

	# sem časem: intercepty, pasti, spouštěče tagů…

	return result

func move_unit(unit_id:int, target_region_id:int) -> Dictionary:
	# 1) validace pravidel
	var check: Dictionary = can_move(unit_id, target_region_id)
	if not check.get("ok", false):
		return _result_err(String(check.get("reason", "Nelze pohnout jednotkou.")))

	# 2) samotný přesun
	var u := game_state.query.units.get_by_id(unit_id)
	if u == null:
		return _result_err("Jednotka neexistuje.")

	var from_region_id: int = u.region_id
	u.region_id = target_region_id
	u.moves_left -= 1

	# sledování navštívených regionů (pro scout pohybovou logiku)
	if target_region_id not in u.visited_regions:
		u.visited_regions.append(target_region_id)

	# 3) post-move efekty (např. změna vlastnictví regionu)
	var post: Dictionary = apply_post_move_effects(unit_id, from_region_id, target_region_id)

	var from_r : Region = game_state.region_manager.get_region(from_region_id)
	var to_r   : Region = game_state.region_manager.get_region(target_region_id)
	var from_name := from_r.name if from_r != null else str(from_region_id)
	var to_name := to_r.name if to_r != null else str(target_region_id)

	var events := [
		{"type":"unit_moved", "unit_id": unit_id, "from": from_region_id, "to": target_region_id}
	]

	var result := _result_ok({
		"type": "move",
		"text": "🚶‍♂️ %s se přesunul z %s do %s." % [u.name, from_name, to_name],
		"unit_id": unit_id,
		"from": from_region_id,
		"to": target_region_id
	}, events)
	

	# 4) pokud post-move efekty něco přinesly, přeneseme to do result
	if post.get("ok", false):
		for k in post.keys():
			if k == "ok":
				continue
			result[k] = post[k]

	return result
