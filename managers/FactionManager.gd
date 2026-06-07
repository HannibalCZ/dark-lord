extends Resource
class_name FactionManager

var _factions : Dictionary = {}  # key = faction_id, value = Faction ref
var game_state: GameStateSingleton

var _network_name_pool: Dictionary = {}   # network_type -> Array[String] (dostupné)
var _used_network_names: Dictionary = {}  # network_type -> Array[String] (použité)
var _network_name_pool_loaded: bool = false

func _load_network_name_pool() -> void:
	_network_name_pool_loaded = true
	var f := FileAccess.open("res://data/names/unit_names.json", FileAccess.READ)
	if not f:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var network_names: Variant = parsed.get("network_names", {})
	if typeof(network_names) != TYPE_DICTIONARY:
		return
	for key in network_names.keys():
		var arr: Array = []
		for item in network_names[key]:
			arr.append(item)
		_network_name_pool[key] = arr

func _pick_network_name(network_type: String) -> String:
	if not _network_name_pool_loaded:
		_load_network_name_pool()
	var pool: Array = _network_name_pool.get(network_type, [])
	if not _used_network_names.has(network_type):
		_used_network_names[network_type] = []
	var used: Array = _used_network_names[network_type]
	var available := pool.filter(func(n): return not used.has(n))
	if available.is_empty():
		var base: String = Balance.ORG.get(network_type, {}).get("display_name", network_type)
		return "%s %d" % [base, used.size() + 1]
	var rng := game_state.rng if game_state != null else RandomNumberGenerator.new()
	var chosen: String = available[rng.randi() % available.size()]
	used.append(chosen)
	return chosen
	
func add_faction(faction:Faction) -> void:
	_factions[faction.id] = faction

func get_faction(id:String) -> Faction:
	return _factions.get(id, null)

func init_empty() -> void:
	_factions.clear()

func all() -> Array:
	return _factions.values()

func players() -> Array:
	return _factions.values().filter(func(f): return f.is_player)

func ai_factions() -> Array:
	return _factions.values().filter(func(f): return not f.is_player)

func get_network_faction_in_region(region_id: int) -> Faction:
	for faction in _factions.values():
		if faction.faction_type == "network" and faction.influence.has(region_id):
			return faction
	return null

func create_network_faction(network_type: String, owner_faction_id: String,
		region_id: int, founding_turn: int, founder_unit: Unit = null) -> Faction:
	if get_network_faction_in_region(region_id) != null:
		push_warning("FactionManager: region %d already has a network faction" % region_id)
		return null
	var faction := Faction.new()
	faction.id = "network_%s_%d_%d" % [network_type, region_id, founding_turn]
	faction.name = network_type
	faction.faction_type = "network"
	faction.network_type = network_type
	faction.influence = { region_id: Balance.NETWORK_INFLUENCE_INITIAL }
	faction.visibility = 0
	faction.source_faction_id = owner_faction_id
	faction.founded_turn = founding_turn
	faction.loyalty = 100
	faction.visible = false
	faction.doctrine = Balance.ORG.get(network_type, {}).get("default_doctrine", "")
	faction.faction_display_name = _pick_network_name(network_type)
	faction.founder_name = founder_unit.name if founder_unit != null else ""
	add_faction(faction)
	return faction

func set_doctrine(faction_id: String, doctrine_key: String) -> void:
	var faction: Faction = get_faction(faction_id)
	if faction == null:
		push_warning("FactionManager.set_doctrine: faction '%s' neexistuje" % faction_id)
		return
	if faction.faction_type != "network":
		push_warning("FactionManager.set_doctrine: faction '%s' není network type" % faction_id)
		return
	var doctrines: Dictionary = Balance.ORG.get(faction.network_type, {}).get("doctrines", {})
	if not doctrines.has(doctrine_key):
		push_warning("FactionManager.set_doctrine: doktrína '%s' neexistuje pro '%s'" % [doctrine_key, faction.network_type])
		return
	faction.doctrine = doctrine_key

func get_available_doctrines(faction_id: String) -> Dictionary:
	var faction: Faction = get_faction(faction_id)
	if faction == null or faction.faction_type != "network":
		return {}
	return Balance.ORG.get(faction.network_type, {}).get("doctrines", {})

func load_from_scenario(fd: Dictionary, fac: Faction) -> void:
	if fd.has("loyalty"):
		fac.loyalty = int(fd.get("loyalty", 100))
	if fd.has("is_rogue"):
		fac.is_rogue = bool(fd.get("is_rogue", false))
	if fd.has("doctrine"):
		fac.doctrine = String(fd.get("doctrine", ""))
	if fd.has("visible"):
		fac.visible = bool(fd.get("visible", true))
	if fd.has("founded_turn"):
		fac.founded_turn = int(fd.get("founded_turn", 0))
	if fd.has("source_faction_id"):
		fac.source_faction_id = String(fd.get("source_faction_id", ""))


func get_all_network_factions() -> Array[Faction]:
	var result: Array[Faction] = []
	for faction in _factions.values():
		if faction.faction_type == "network":
			result.append(faction)
	return result


func process_loyalty_decay(player_infamy: float) -> void:
	var decay: int
	if player_infamy <= 20:   decay = Balance.NETWORK_LOYALTY_DECAY_LOW
	elif player_infamy <= 50: decay = Balance.NETWORK_LOYALTY_DECAY_MID
	elif player_infamy <= 80: decay = Balance.NETWORK_LOYALTY_DECAY_HIGH
	else:                     decay = Balance.NETWORK_LOYALTY_DECAY_VERY_HIGH

	for faction in get_all_network_factions():
		if faction.is_rogue:
			continue
		if faction.source_faction_id != Balance.PLAYER_FACTION:
			continue
		faction.loyalty = max(0, faction.loyalty - decay)
		if faction.loyalty <= Balance.NETWORK_LOYALTY_ROGUE_THRESHOLD:
			var max_influence: int = faction.influence.values().max() \
					if not faction.influence.is_empty() else 0
			if max_influence >= Balance.NETWORK_LOYALTY_ROGUE_INFLUENCE_MIN:
				_trigger_rogue(faction)


func _trigger_rogue(faction: Faction) -> void:
	faction.is_rogue = true
	faction.source_faction_id = ""
	var region_ids: Array = faction.influence.keys()
	EventBus.network_faction_went_rogue.emit(faction.id, region_ids)


func remove_network_faction(region_id: int) -> void:
	for faction_id in _factions.keys():
		var f: Faction = _factions[faction_id]
		if f.faction_type != "network":
			continue
		if f.influence.has(region_id):
			f.influence.erase(region_id)
			if f.influence.is_empty():
				_factions.erase(faction_id)
			EventBus.network_faction_destroyed.emit(faction_id, region_id)
			return


func create_lair_faction(region: Region) -> Faction:
	var fac := Faction.new()
	fac.id = "lair_%d" % region.id
	fac.name = Balance.LAIR[region.lair_id].get("display_name", "Lair")
	fac.alignment = "neutral"
	fac.faction_type = "lair"
	fac.source_faction_id = "neutral"
	fac.lair_region_id = region.id
	fac.unit_limit = Balance.LAIR[region.lair_id].get("max_units", 2)
	add_faction(fac)
	return fac


func get_lair_faction_for_region(region_id: int) -> Faction:
	return get_faction("lair_%d" % region_id)


func get_all_lair_factions() -> Array[Faction]:
	var result: Array[Faction] = []
	for fac in _factions.values():
		if fac.faction_type == "lair":
			result.append(fac)
	return result


func get_player_network_factions() -> Array[Faction]:
	return get_all_network_factions().filter(
		func(f: Faction): return f.source_faction_id == Balance.PLAYER_FACTION and not f.is_rogue
	)


func get_network_faction_display_data(region_id: int) -> Dictionary:
	var nf: Faction = get_network_faction_in_region(region_id)
	if nf == null:
		return {}
	return {
		"faction_id":       nf.id,
		"network_type":     nf.network_type,
		"display_name":     nf.faction_display_name if not nf.faction_display_name.is_empty() else Balance.ORG.get(nf.network_type, {}).get("display_name", nf.network_type),
		"founder_name":     nf.founder_name,
		"doctrine":         nf.doctrine,
		"doctrine_display": Balance.ORG.get(nf.network_type, {}).get("doctrines", {}).get(nf.doctrine, {}).get("display_name", ""),
		"loyalty":          nf.loyalty,
		"is_rogue":         nf.is_rogue,
		"visible":          nf.visible,
		"is_player_org":    nf.source_faction_id == Balance.PLAYER_FACTION,
		"influence":        nf.influence.get(region_id, 0)
	}


func get_available_doctrines_by_region(region_id: int) -> Array[Dictionary]:
	var nf: Faction = get_network_faction_in_region(region_id)
	if nf == null:
		return []
	var current_doctrine: String = nf.doctrine
	var doctrines_cfg: Dictionary = Balance.ORG.get(nf.network_type, {}).get("doctrines", {})
	var result: Array[Dictionary] = []
	for key in doctrines_cfg.keys():
		var d: Dictionary = doctrines_cfg[key]
		result.append({
			"key":          key,
			"display_name": d["display_name"],
			"effects":      d.get("effects", {}),
			"is_current":   key == current_doctrine
		})
	return result


func set_doctrine_by_region(region_id: int, doctrine_key: String) -> void:
	var nf: Faction = get_network_faction_in_region(region_id)
	if nf == null:
		return
	set_doctrine(nf.id, doctrine_key)
