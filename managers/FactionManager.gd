extends Resource
class_name FactionManager

var _factions : Dictionary = {}  # key = faction_id, value = Faction ref
var game_state: GameStateSingleton
	
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
		region_id: int, founding_turn: int) -> Faction:
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
	add_faction(faction)
	return faction

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
