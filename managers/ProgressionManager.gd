extends Node
class_name ProgressionManager

var game_state: GameStateSingleton

# Stav odemcených uzlu per frakce
# { faction_id: Array[String] }
var unlocked_nodes: Dictionary = {}

# Tracking herních podmínek — inicializováno lazy pri prvním prístupu
# { faction_id: { "military_victories": 0, ... } }
var condition_trackers: Dictionary = {}


# ---------------------------------------------------------
# Query
# ---------------------------------------------------------

# Vrátí Array[String] odemcených uzlu frakce
func get_unlocked(faction_id: String) -> Array:
	return unlocked_nodes.get(faction_id, [])


# Je konkrétní uzel odemcen?
func is_unlocked(faction_id: String, node_key: String) -> bool:
	return node_key in get_unlocked(faction_id)


# Vrátí všechny uzly daného tieru pro frakci s jejich stavem
# Každý prvek: { "key": String, "state": String }
# state: "unlocked" | "available" | "locked"
func get_tier_status(faction_id: String, tier: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in Balance.PROGRESSION:
		var node: Dictionary = Balance.PROGRESSION[key]
		if int(node.get("tier", 0)) != tier:
			continue
		var state: String
		if is_unlocked(faction_id, key):
			state = "unlocked"
		else:
			var check := can_unlock(faction_id, key)
			state = "available" if check["ok"] else "locked"
		result.append({ "key": key, "state": state })
	return result


# ---------------------------------------------------------
# Unlock validace
# ---------------------------------------------------------

# Validuje zda lze uzel odemcít pro danou frakci.
# Vrátí { "ok": bool, "reason": String }.
# Kontroly v porádí: existence, ne-duplikat, RP, requires, excludes, game_condition.
func can_unlock(faction_id: String, node_key: String) -> Dictionary:
	# 1. Uzel existuje v Balance.PROGRESSION
	var node: Dictionary = Balance.get_progression_node(node_key)
	if node.is_empty():
		return { "ok": false, "reason": "Uzel '%s' neexistuje v Balance.PROGRESSION." % node_key }

	# 2. Uzel ješte není odemcen pro tuto frakci
	if is_unlocked(faction_id, node_key):
		return { "ok": false, "reason": "Uzel '%s' je již odemcen." % node_key }

	# 3. Frakce má dostatek RP
	var faction := game_state.faction_manager.get_faction(faction_id)
	if faction == null:
		return { "ok": false, "reason": "Neznámá frakce: '%s'." % faction_id }
	var cost_rp: int = int(node["cost"].get("rp", 0))
	if faction.get_resource("research") < float(cost_rp):
		return {
			"ok": false,
			"reason": "Nedostatek RP (potreba %d, mas %d)." % [
				cost_rp, int(faction.get_resource("research"))
			]
		}

	# 4. Všechny requires_nodes jsou odemceny
	var requires: Array = node["unlock_conditions"].get("requires_nodes", [])
	for req_key in requires:
		if not is_unlocked(faction_id, String(req_key)):
			return { "ok": false, "reason": "Požadovaný uzel '%s' není odemcen." % req_key }

	# 5. Žádný excludes_nodes není odemcen
	var excludes: Array = node["unlock_conditions"].get("excludes_nodes", [])
	for excl_key in excludes:
		if is_unlocked(faction_id, String(excl_key)):
			return { "ok": false, "reason": "Exkluzivní uzel '%s' je již odemcen — vzájemne se vylucují." % excl_key }

	# 6. game_condition je splnena (null = vždy splnena)
	var game_cond = node["unlock_conditions"].get("game_condition", null)
	if game_cond != null:
		if not _check_game_condition(faction_id, game_cond):
			return {
				"ok": false,
				"reason": "Herní podmínka '%s' není splnena." % String(game_cond.get("type", "?"))
			}

	return { "ok": true, "reason": "" }


func _check_game_condition(faction_id: String, condition: Dictionary) -> bool:
	match condition.get("type", ""):
		"regions_corrupted":
			# Pocet regionu kde frakce má korupci fáze >= 1
			var count := 0
			for region in game_state.region_manager.regions:
				if region.get_corruption_phase_for(faction_id) >= 1:
					count += 1
			return count >= int(condition.get("min", 0))

		"orgs_active":
			# Pocet aktivních org hráce >= min
			# MVP: používá get_player_orgs() — platí pouze pro player frakci
			var player_orgs := game_state.org_manager.get_player_orgs()
			return player_orgs.size() >= int(condition.get("min", 0))

		"regions_owned":
			# Pocet regionu kde owner == faction_id
			return game_state.query.regions.count_owned_by(faction_id) >= int(condition.get("min", 0))

		"military_victories":
			# Sleduje se pres condition_trackers — inkrementovat zvenku
			# (viz record_military_victory())
			var trackers := _get_trackers(faction_id)
			return int(trackers.get("military_victories", 0)) >= int(condition.get("min", 0))

		"org_exists":
			# Existuje org daneho typu aktivní alespon min_turns tahu
			var org_type: String = String(condition.get("org_type", ""))
			var min_turns: int = int(condition.get("min_turns", 0))
			for org in game_state.org_manager.orgs:
				if org["owner"] == faction_id and org["org_type"] == org_type:
					if game_state.turn - int(org.get("founded_turn", 0)) >= min_turns:
						return true
			return false

		"mana_cap_reached":
			# Frakce má aktuálne alespon min many
			var fac := game_state.faction_manager.get_faction(faction_id)
			if fac == null:
				return false
			return fac.get_resource("mana") >= float(condition.get("min", 0))

	push_warning("ProgressionManager: neznamy typ game_condition '%s'" % String(condition.get("type", "?")))
	return false


# ---------------------------------------------------------
# Mutace
# ---------------------------------------------------------

func unlock_node(faction_id: String, node_key: String) -> Dictionary:
	var check := can_unlock(faction_id, node_key)
	if not check["ok"]:
		return check

	var node: Dictionary = Balance.get_progression_node(node_key)
	var ctx := EffectContext.make(game_state, null, faction_id)

	# 1. Odecti RP
	game_state.effects_system.apply(
		{"research": -int(node["cost"].get("rp", 0))}, ctx)

	# 2. Aplikuj one_time_effects (TYP B) — pres EffectsSystem jednorázove
	var one_time: Dictionary = Balance.get_progression_one_time(node_key)
	if not one_time.is_empty():
		game_state.effects_system.apply(one_time, ctx)

	# 3. Aplikuj passive_effects (TYP A) — modifier_ klíce → faction.modifiers accumulator
	#    EffectsSystem akumuluje do faction.modifiers — per-turn se NEVOLÁ
	var passive: Dictionary = Balance.get_progression_passive(node_key)
	if not passive.is_empty():
		game_state.effects_system.apply(passive, ctx)

	# 4. Ulož odemcený uzel
	if not unlocked_nodes.has(faction_id):
		unlocked_nodes[faction_id] = []
	unlocked_nodes[faction_id].append(node_key)

	# 5. Emituj signal
	EventBus.progression_node_unlocked.emit(faction_id, node_key)

	return { "ok": true, "reason": "" }


# ---------------------------------------------------------
# Condition tracker helpers
# ---------------------------------------------------------

# Lazy init — condition_trackers se neinicializují v _ready()
func _get_trackers(faction_id: String) -> Dictionary:
	if not condition_trackers.has(faction_id):
		condition_trackers[faction_id] = {
			"military_victories": 0,
		}
	return condition_trackers[faction_id]


# Volat z GameState/_process_domain_events() po výhre v bitve
func record_military_victory(faction_id: String) -> void:
	var trackers := _get_trackers(faction_id)
	trackers["military_victories"] = int(trackers.get("military_victories", 0)) + 1
