extends Node
class_name BuildingManager

signal buildings_changed

var game_state: GameStateSingleton
# [{id, name, built, cost, effect, desc}, ...]
var buildings: Array[Dictionary] = []

func init_buildings() -> void:
	buildings = [
		{"id":0, "name":"Knihovna", "built":false, "cost":20, "effect":"+1 výzkum/tahem", "desc":"Zvyšuje produkci výzkumu."},
		{"id":1, "name":"Doupě",   "built":false, "cost":30, "effect":"+1 limit jednotek", "desc":"Umožňuje mít více jednotek."},
		{"id":2, "name":"Past",    "built":false, "cost":25, "effect":"+5 obrana věže", "desc":"Zvyšuje obranu věže proti útoku dobra."}
	]
	emit_signal("buildings_changed")

func get_buildings() -> Array[Dictionary]:
	return buildings

func build(id: int) -> Dictionary:
	if id < 0 or id >= buildings.size():
		return {"text":"❌ Neplatná budova.", "type":"warn"}

	var b = buildings[id]
	if b["built"]:
		return {"text":"ℹ️ Budova %s už stojí." % b["name"], "type":"info"}

	if game_state.faction_manager.get_faction(Balance.PLAYER_FACTION).resources["gold"] < b["cost"]:
		return {"text":"❌ Nedostatek surovin pro stavbu %s." % b["name"], "type":"warn"}

	# Zaplať a postav
	var pay_ctx := EffectContext.make(game_state, null, Balance.PLAYER_FACTION)
	game_state.effects_system.apply({"gold": -b["cost"]}, pay_ctx)
	b["built"] = true

	# Okamžité jednorázové dopady na state (pokud nějaké má být už nyní)
	match b["name"]:
		"Doupě":
			# TODO: unit_limit by měl jít přes EffectsSystem
			# až bude přidán klíč "unit_limit"
			game_state.unit_manager.unit_limit += 1
		_:
			pass

	
	return {"text":"🏗️ Postavena budova: %s." % b["name"], "type":"build"}

func apply_end_of_turn_effects() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	for b in buildings:
		if not b["built"]:
			continue
		match b["name"]:
			"Knihovna":
				var ctx := EffectContext.make(game_state, null, Balance.PLAYER_FACTION)
				game_state.effects_system.apply({"research": 1}, ctx)
			"Past":
				# později: přičítej trvalý bonus k obraně věže / stacky pastí apod.
				pass
			"Doupě":
				# trvalý efekt je již aplikován při stavbě (unit_limit)
				pass
	logs.append({"text":"Budovy poskytly své efekty.", "type":"info"})
	return logs
