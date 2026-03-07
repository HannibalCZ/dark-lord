extends Node
class_name SpellManager

signal spells_changed
signal magic_used

var game_state: GameStateSingleton

# [{id, name, branch, cost, desc, key}, ...]
var spells: Array[Dictionary] = []

func init_spells() -> void:
	spells = [
		{"id":0, "name":"Tvorba Homunkula", "branch":"Černá alchymie", "cost":10, "desc":"Vytvoří jednotku typu agent.", "key":"create_homunculus"},
		{"id":1, "name":"Smlouva s démony", "branch":"Démonologie",   "cost":10, "desc":"Získáš +10 many.", "key":"gain_mana"},
		{"id":2, "name":"Strach",           "branch":"Korupce",       "cost":10, "desc":"Sníží HEAT o 5.", "key":"lower_heat"}
	]
	emit_signal("spells_changed")

func get_spells() -> Array[Dictionary]:
	return spells

func can_cast(id:int) -> bool:
	
	if id < 0 or id >= spells.size():
		return false
	return game_state.research >= spells[id]["cost"]

func cast(id:int) -> Dictionary:
	if id < 0 or id >= spells.size():
		return {"text":"❌ Neznámé kouzlo.", "type":"warn"}

	var s = spells[id]
	if game_state.research < s["cost"]:
		return {"text":"❌ Nedostatek výzkumu pro '%s'." % s["name"], "type":"warn"}

	# zaplať
	game_state.research -= s["cost"]

	# efekt
	match s["key"]:
		"create_homunculus":
			# respektuje limit jednotek (kontroluje GameState)
			game_state.unit_manager.recruit_unit(Balance.PLAYER_FACTION, "homunculus", 0)
		"gain_mana":
			game_state.faction_manager.get_faction(Balance.PLAYER_FACTION).change_resource("mana", 10)
		"lower_heat":
			game_state.heat = max(0, game_state.heat - 5)
		_:
			return {"text":"❌ Kouzlo '%s' nemá implementovaný efekt." % s["name"], "type":"warn"}

	emit_signal("magic_used")
	emit_signal("spells_changed")
	return {"text":"🔮 Sesláno kouzlo '%s' (%s)." % [s["name"], s["branch"]], "type":"magic"}
