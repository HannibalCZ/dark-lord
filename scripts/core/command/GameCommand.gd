extends RefCounted
class_name GameCommands

var game: GameStateSingleton

func _init(gs: GameStateSingleton) -> void:
	game = gs

# -----------------------------
# INTERNAL Helpers

func _normalize_dict_array(v: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if typeof(v) != TYPE_ARRAY:
		return out

	for item in v:
		if typeof(item) == TYPE_DICTIONARY:
			out.append(item)

	return out

func _res_ok(payload: Dictionary = {}, logs: Array[Dictionary] = [], events: Array[Dictionary] = []) -> Dictionary:
	payload["ok"] = true
	payload["logs"] = logs
	payload["events"] = events
	return payload

func _res_err(reason: String, payload: Dictionary = {}, logs: Array[Dictionary] = [], events: Array[Dictionary] = []) -> Dictionary:
	payload["ok"] = false
	payload["reason"] = reason
	payload["logs"] = logs
	payload["events"] = events
	return payload

# =====================================================================
# COMMANDS
# =====================================================================

# 1) MOVE UNIT
func move_unit(unit_id: int, target_region_id: int) -> Dictionary:
	# Validace přes Query (read model)
	if game.query == null:
		return _res_err("Query není inicializovaná.")

	var check: Dictionary = game.query.units.can_move(unit_id, target_region_id)
	if not check.get("ok", false):
		return _res_err(String(check.get("reason", "Nelze pohnout jednotkou.")))

	# Mutace přes UnitManager (write model)
	# očekáváme, že unit_manager.move_unit už vrací Dictionary s textem a events (jak jsi měl)
	var res: Dictionary = game.unit_manager.move_unit(unit_id, target_region_id)

	if not res.get("ok", false):
		# res už typicky obsahuje "text" pro warn
		var reason := String(res.get("reason", res.get("text", "Move failed.")))
		var logs: Array[Dictionary] = []
		if res.has("text"):
			logs.append({"type": String(res.get("type", "warn")), "text": String(res.get("text"))})
		return _res_err(reason, {}, logs, res.get("events", []))

	# logs: preferuj jednotný log entry
	var logs_ok: Array[Dictionary] = []
	if res.has("text"):
		logs_ok.append({
			"type": String(res.get("type", "move")),
			"text": String(res.get("text"))
		})

	# events: forward
	var events_ok: Array[Dictionary] = _normalize_dict_array(res.get("events"))

	return _res_ok({
		"command": "move_unit",
		"unit_id": unit_id,
		"from": int(res.get("from", -1)),
		"to": int(res.get("to", -1))
	}, logs_ok, events_ok)


# 2) CAST DARK ACTION
func cast_dark_action(action_key: String, region_id: int = -1, faction_id: String = Balance.PLAYER_FACTION) -> Dictionary:
	# DarkActionsManager už vrací {ok, reason, logs, events, ...}
	var res: Dictionary = game.dark_actions_manager.cast(faction_id, action_key, region_id)
	var logs: Array[Dictionary] = _normalize_dict_array(res.get("logs"))
	var events: Array[Dictionary] = _normalize_dict_array(res.get("events"))

	if not res.get("ok", false):
		var reason := String(res.get("reason", "Nelze seslat."))
		# Přidej konzistentní warn log, pokud manager žádný nedal
		if logs.is_empty():
			logs.append({"type":"warn", "text":"❌ Nelze seslat akci: %s" % reason})
		return _res_err(reason, {
			"command": "cast_dark_action",
			"action": action_key,
			"region_id": region_id,
			"faction_id": faction_id
		}, logs, events)

	return _res_ok({
		"command": "cast_dark_action",
		"action": action_key,
		"region_id": region_id,
		"faction_id": faction_id
	}, logs, events)


# 3) PLAN MISSION (player)
func plan_mission(unit_id: int, region_id: int, mission_key: String) -> Dictionary:
	if game.query == null:
		return _res_err("Query není inicializovaná.")

	var unit: Unit = game.query.units.get_by_id(unit_id)
	var region: Region = game.query.regions.get_by_id(region_id)
	if unit == null:
		return _res_err("Jednotka neexistuje.")
	if region == null:
		return _res_err("Region neexistuje.")

	# MissionManager.plan_mission dnes loguje do GameState a emituje missions_changed; zatím to necháme.
	# Ale pro Command API chceme konzistentní návrat.
	# Tady uděláme lightweight validace, aby UI mělo feedback.

	var cfg: Dictionary = Balance.MISSION.get(mission_key, {})
	if cfg.is_empty():
		return _res_err("Neznámá mise: %s" % mission_key)

	if not unit.is_available():
		return _res_err("Jednotka je zaneprázdněná.")

	if not unit.can_do_mission(mission_key):
		return _res_err("Tento typ jednotky nemůže provádět tuto misi.")

	if not game.mission_manager.can_do_mission(unit, region, mission_key):
		return _res_err("Tuto misi nelze provést v tomto regionu.")

	game.mission_manager.plan_mission(unit, region, mission_key)

	# event zatím žádný, jen log (pokud chceš)
	var logs: Array[Dictionary] = [{
		"type": "mission",
		"text": "📜 Naplánována mise %s v %s." % [mission_key, region.name]
	}]
	return _res_ok({
		"command": "plan_mission",
		"mission_key": mission_key,
		"unit_id": unit_id,
		"region_id": region_id
	}, logs, [])


# 4) ADVANCE TURN (wrap GameState.advance_turn)
# Pozn.: game.advance_turn() dnes už sám loguje entries + řeší end conditions.
# Do Command API dáme zatím jen jednotný obal, aby UI/AI volaly commands.
func advance_turn() -> Dictionary:
	game.advance_turn()
	# Výsledek je primárně v logu + signálech; pro API vrátíme ok.
	return _res_ok({"command":"advance_turn"}, [], [{"type":"turn_advanced"}])
