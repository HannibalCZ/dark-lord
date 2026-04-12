extends Resource
class_name DarkActionsManager

var game_state: GameStateSingleton

# cooldowny per frakce:
# { "player": {"terrifying_whisper":0, "decoy":0, "infernal_pact":0}, ... }
var _cooldowns:Dictionary = {}


func _init(_game_state:GameStateSingleton = null) -> void:
	game_state = _game_state


# -------------------------------------------------
# interní helper: zajistí, že pro frakci existuje dict cooldownů
func _get_faction_cooldowns(faction_id:String) -> Dictionary:
	if not _cooldowns.has(faction_id):
		var cd:Dictionary = {}
		for key in Balance.DARK_ACTIONS.keys():
			cd[key] = 0
		_cooldowns[faction_id] = cd
	return _cooldowns[faction_id]


# -------------------------------------------------
# 1) can_cast – ověří, zda frakce může akci použít (cooldown, AP, mana, target)
func can_cast(faction_id:String, action_key:String, region_id:int = -1) -> Dictionary:
	var action_def:Dictionary = Balance.DARK_ACTIONS.get(action_key, {})
	if action_def.is_empty():
		return {"ok": false, "reason": "Neznámá dark akce: %s" % action_key}

	var fac = game_state.faction_manager.get_faction(faction_id)
	if fac == null:
		return {"ok": false, "reason": "Neznámá frakce: %s" % faction_id}

	var cds = _get_faction_cooldowns(faction_id)
	if cds.get(action_key, 0) > 0:
		return {"ok": false, "reason": "Akce je na cooldownu."}

	var ap_cost:int = int(action_def.get("ap_cost", 0))
	if fac.dark_actions_left < ap_cost:
		return {"ok": false, "reason": "Nedostatek dark action bodů."}

	var mana_cost:int = int(action_def.get("mana_cost", 0))
	if mana_cost > 0 and fac.get_resource("mana") < mana_cost:
		return {"ok": false, "reason": "Nedostatek many."}

	var gold_cost:int = int(action_def.get("gold_cost", 0))
	if gold_cost > 0 and fac.get_resource("gold") < gold_cost:
		return {"ok": false, "reason": "Nedostatek zlata."}

	var atype:String = String(action_def.get("type", "global"))
	if atype == "region":
		# region_id musí být validní
		if region_id < 0 or region_id >= game_state.region_manager.regions.size():
			return {"ok": false, "reason": "Neplatný cílový region."}

	# validace specifická pro found_org akce
	if action_def.get("effects", {}).has("found_org"):
		if game_state.org_manager.has_org_in_region(region_id):
			return {"ok": false, "reason": "Region jiz ma organizaci."}
		if _find_available_agent(region_id) == null:
			return {"ok": false, "reason": "Zadny dostupny agent v regionu."}

	# validace requires_org requirement
	var req: Dictionary = action_def.get("requirements", {})
	if req.get("requires_org", false):
		var req_region: Region = game_state.region_manager.get_region(region_id)
		if req_region == null:
			return {"ok": false, "reason": "Zadny region neni vybran."}
		var req_org: Dictionary = game_state.org_manager.get_org_in_region(req_region.id)
		if req_org.is_empty():
			return {"ok": false, "reason": "Region nema organizaci."}
		if req_org.get("owner", "") != Balance.PLAYER_FACTION:
			return {"ok": false, "reason": "Organizace v regionu nepatri hraci."}

	return {"ok": true}


# -------------------------------------------------
# 2) cast – provede akci, odečte náklady, nastaví cooldown, aplikuje efekty
func cast(faction_id:String, action_key:String, region_id:int = -1) -> Dictionary:
	var logs: Array[Dictionary] = []
	var events: Array[Dictionary] = []

	var check := can_cast(faction_id, action_key, region_id)
	if not check.get("ok", false):
		return {
			"ok": false,
			"reason": String(check.get("reason", "Nelze seslat.")),
			"logs": logs,
			"events": events,
			"action": action_key,
			"faction_id": faction_id,
			"region_id": region_id
		}

	var action_def:Dictionary = Balance.DARK_ACTIONS.get(action_key, {})
	var fac = game_state.faction_manager.get_faction(faction_id)
	var cds = _get_faction_cooldowns(faction_id)

	# --- costs ---
	var ap_cost:int = int(action_def.get("ap_cost", 0))
	var mana_cost:int = int(action_def.get("mana_cost", 0))
	var gold_cost:int = int(action_def.get("gold_cost", 0))
	# TODO: AP cost by měl jít přes EffectsSystem
	# až bude přidán klíč "ap"
	fac.dark_actions_left -= ap_cost
	var cost_effects: Dictionary = {}
	if mana_cost > 0:
		cost_effects["mana"] = -mana_cost
	if gold_cost > 0:
		cost_effects["gold"] = -gold_cost
	if not cost_effects.is_empty():
		var cost_ctx := EffectContext.make(game_state, null, fac.id)
		game_state.effects_system.apply(cost_effects, cost_ctx)

	# cooldown
	var cd_val:int = int(action_def.get("cooldown", 0))
	cds[action_key] = cd_val

	# efekty přes centrální resolver v GameState
	# --- effects ---
	var atype:String = String(action_def.get("type", "global"))
	var target_region: Region = null
	if atype == "region":
		target_region = game_state.query.regions.get_by_id(region_id)

	var effects:Dictionary = action_def.get("effects", {})

	# org_loyalty neni znamy EffectsSystem — zpracuj primo pres OrgManager
	var loyalty_boost: int = effects.get("org_loyalty", 0)
	if loyalty_boost != 0 and target_region != null:
		var boost_org: Dictionary = game_state.org_manager.get_org_in_region(target_region.id)
		if not boost_org.is_empty():
			boost_org["loyalty"] = min(100, boost_org.get("loyalty", Balance.ORG_LOYALTY_START) + loyalty_boost)

	# odstan org_loyalty pred predanim EffectsSystem
	var effects_for_system: Dictionary = effects.duplicate()
	effects_for_system.erase("org_loyalty")

	if not effects_for_system.is_empty():
		# signatura: _apply_effects(effects, region_or_null, source_faction_id)
		var ctx := EffectContext.make(game_state, target_region, faction_id)
		ctx.source_label = "Temná akce: %s" % String(action_def.get("display_name", action_key))
		var eff_logs: Array[Dictionary] = game_state.effects_system.apply(effects_for_system, ctx)
		logs += eff_logs

	# zpracování speciálního efektu found_org
	if effects.has("found_org"):
		var found_logs: Array[Dictionary] = _handle_found_org(action_key, region_id, faction_id)
		logs += found_logs

	events = [{
		"type": "dark_action_cast",
		"action": action_key,
		"faction_id": faction_id,
		"region_id": region_id
	}]

	# log do UI (pokud chceš mít jednotný feed)
	var display_name:String = String(action_def.get("display_name", action_key))
	logs.append({
		"type": "dark_action",
		"text": "🔮 Seslána temná akce: %s" % display_name
	})

	var global_fx: Dictionary = Balance.DARK_ACTION_GLOBAL_EFFECTS
	if not global_fx.is_empty():
		var gctx := EffectContext.make(game_state, null, Balance.PLAYER_FACTION)
		gctx.source_label = "Temná akce: %s" % String(action_def.get("display_name", action_key))
		game_state.effects_system.apply(global_fx, gctx)

	return {
		"ok": true,
		"action": action_key,
		"faction_id": faction_id,
		"region_id": region_id,
		"logs": logs,
		"events": events
	}

# -------------------------------------------------
# 3) tick_cooldowns – volat na konci kola
func tick_cooldowns() -> void:
	for fid in _cooldowns.keys():
		var cd_for_faction:Dictionary = _cooldowns[fid]
		for key in cd_for_faction.keys():
			var v:int = cd_for_faction[key]
			if v > 0:
				cd_for_faction[key] = v - 1


# -------------------------------------------------
# 4) refresh_dark_actions_for_faction – na začátku kola
func refresh_dark_actions_for_faction(faction_id:String) -> void:
	var fac = game_state.faction_manager.get_faction(faction_id)
	if fac == null:
		return
	fac.dark_actions_left = fac.dark_actions_max


# volitelně: pro všechny frakce najednou
func refresh_all_dark_actions() -> void:
	for f in game_state.faction_manager.factions:
		refresh_dark_actions_for_faction(f.id)


# -------------------------------------------------
# 5) get_available_actions_for_faction – pro UI (cooldown==0)
# POZOR: nekontrolujeme AP/mana, jen cooldown
func get_available_actions_for_faction(faction_id:String) -> Array[String]:
	var result:Array[String] = []
	var cds = _get_faction_cooldowns(faction_id)
	for key in Balance.DARK_ACTIONS.keys():
		if cds.get(key, 0) <= 0:
			result.append(key)
	return result


# -------------------------------------------------
# 6) _find_available_agent – první zdravý agent hráče v regionu
func _find_available_agent(region_id: int) -> Unit:
	for unit in game_state.unit_manager.units:
		if unit.region_id == region_id \
				and unit.faction_id == Balance.PLAYER_FACTION \
				and unit.is_available() \
				and not unit.is_army():
			return unit
	return null


# -------------------------------------------------
# 7) _handle_found_org – vytvoří organizaci a spotřebuje agenta
func _handle_found_org(action_key: String, region_id: int, faction_id: String) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []

	# double-check (can_cast už validoval, ale pro jistotu)
	if game_state.org_manager.has_org_in_region(region_id):
		push_error("DarkActionsManager._handle_found_org: region %d jiz ma organizaci" % region_id)
		logs.append({"type": "warn", "text": "Region jiz ma organizaci — organizace nevznikla."})
		return logs

	var agent: Unit = _find_available_agent(region_id)
	if agent == null:
		push_error("DarkActionsManager._handle_found_org: zadny agent v regionu %d" % region_id)
		logs.append({"type": "warn", "text": "Zadny dostupny agent v regionu — organizace nevznikla."})
		return logs

	# vytvoř organizaci
	var org_type: String = Balance.DARK_ACTIONS[action_key]["effects"]["found_org"]
	var org: Dictionary = game_state.org_manager.add_org(
		org_type,
		Balance.ORG_OWNER_PLAYER,
		region_id
	)

	# spotřebuj agenta
	agent.state = "lost"

	var org_display: String = Balance.ORG[org_type]["display_name"]
	logs.append({
		"type": "dark_action",
		"text": "Organizace zalozena: %s (region %d). Agent obetuji." % [org_display, region_id]
	})
	return logs
