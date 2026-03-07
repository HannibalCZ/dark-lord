# res://scripts/CombatManager.gd
extends Resource
class_name CombatManager

var game_state: GameStateSingleton

func resolve_all_combats() -> Dictionary:
	var logs: Array[Dictionary] = []
	var events: Array[Dictionary] = []

	var contested := _collect_contested_regions()  # Array[int]

	for region_idx in contested:
		var res := _resolve_region_battle(region_idx) # {logs, events}
		logs += res.get("logs")
		events += res.get("events")

	return {
		"ok": true,
		"logs": logs,
		"events": events
	}

# ---- Helpers ----

func _collect_contested_regions() -> Array[int]:
	var contested: Array[int] = []
	var regions := game_state.region_manager.regions

	for i in regions.size():
		var factions := {}
		for u in game_state.query.units.in_region(i, false):
			if u.type != "army":
				continue
			factions[u.faction_id] = true
			if factions.size() >= 2:
				contested.append(i)
				break

	return contested

func _resolve_region_battle(region_idx: int) -> Dictionary:
	var logs: Array[Dictionary] = []
	var events: Array[Dictionary] = []

	var region: Region = game_state.query.regions.get_by_id(region_idx)
	if region == null:
		return {"ok": false, "logs": logs, "events": events}

	# map(faction_id -> Array[Unit] v regionu)
	var by_faction: Dictionary = {}
	for u in game_state.query.units.in_region(region_idx, false):
		if u.type != "army":
			continue
		if not by_faction.has(u.faction_id):
			by_faction[u.faction_id] = []
		(by_faction[u.faction_id] as Array).append(u)

	# 1) spočti sílu
	var power_by_faction: Dictionary = {}
	var factions_sorted: Array = by_faction.keys()
	factions_sorted.sort() # determinismus

	for f in factions_sorted:
		var total := 0
		for u: Unit in by_faction[f]:
			if u.state != "lost":
				total += u.power
		power_by_faction[f] = total

	# 2) vítěz / remíza
	var max_power := -1
	var winners: Array[String] = []
	for f in factions_sorted:
		var p: int = int(power_by_faction[f])
		if p > max_power:
			max_power = p
			winners.clear()
			winners.append(f)
		elif p == max_power:
			winners.append(f)

	# 3) vyhodnocení
	if winners.size() == 1:
		var winner_faction: String = winners[0]
		var winner_power: int = max_power

		# poražení – všechny armády ztraceny
		for f in factions_sorted:
			if f == winner_faction:
				continue
			for u: Unit in by_faction[f]:
				if u.state != "lost":
					var prev := u.state
					u.state = "lost"
					events.append({
						"type": "unit_state_changed",
						"unit_id": u.id,
						"from": prev,
						"to": "lost"
					})

		logs.append({
			"type": "battle",
			"text": "Bitva v %s: frakce %s zvítězila (síla %d) nad ostatními." % [
				region.name, winner_faction, winner_power
			]
		})

		# změna vlastníka regionu
		var prev_owner := region.owner_faction_id
		if prev_owner != winner_faction:
			region.owner_faction_id = winner_faction

			events.append({
				"type": "region_owner_changed",
				"region_id": region.id,
				"from": prev_owner,
				"to": winner_faction
			})

			logs.append({
				"type": "success",
				"text": "Region %s ovládnut frakcí %s (dříve %s)." % [
					region.name, winner_faction, prev_owner
				]
			})
	else:
		# remíza – všichni zničeni
		for f in factions_sorted:
			for u: Unit in by_faction[f]:
				if u.state != "lost":
					var prev := u.state
					u.state = "lost"
					events.append({
						"type": "unit_state_changed",
						"unit_id": u.id,
						"from": prev,
						"to": "lost"
					})

		logs.append({
			"type": "neutral",
			"text": "Bitva v %s skončila patem (síly frakcí vyrovnané, všechny armády zničeny)." % region.name
		})

	return {
		"ok": true,
		"logs": logs,
		"events": events
	}

func _pick_strongest(units_arr: Array) -> Unit:
	var best: Unit = null
	var best_power := -999
	for u: Unit in units_arr:
		if u.state != "lost":
			if u.power > best_power:
				best_power = u.power
				best = u
	return best

func _alive_factions(_by_faction: Dictionary) -> Array[String]:
	var arr: Array[String] = []
	for f in _by_faction.keys():
		var has_alive := false
		for uu: Unit in _by_faction[f]:
			if uu.state != "lost":
				has_alive = true
				break
		if has_alive:
			arr.append(f)
	return arr
