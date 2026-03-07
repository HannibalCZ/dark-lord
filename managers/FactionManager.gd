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
