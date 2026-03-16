extends Node
class_name OrgManager

var game_state: GameStateSingleton

var orgs: Array[Dictionary] = []
var _next_id: int = 1


# ---------------------------------------------------------
# Query
# ---------------------------------------------------------

func get_org_in_region(region_id: int) -> Dictionary:
	for org in orgs:
		if org["region_id"] == region_id:
			return org
	return {}


func get_player_orgs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for org in orgs:
		if org["owner"] == Balance.ORG_OWNER_PLAYER:
			result.append(org)
	return result


func has_org_in_region(region_id: int) -> bool:
	for org in orgs:
		if org["region_id"] == region_id:
			return true
	return false


# ---------------------------------------------------------
# Mutace
# ---------------------------------------------------------

func add_org(org_type: String, owner: String, region_id: int) -> Dictionary:
	if not Balance.ORG.has(org_type):
		push_error("OrgManager.add_org: neznamy org_type '%s'" % org_type)
		return {}

	var org: Dictionary = {
		"org_id":       "org_" + str(_next_id),
		"org_type":     org_type,
		"owner":        owner,
		"region_id":    region_id,
		"doctrine":     Balance.ORG[org_type]["default_doctrine"],
		"founded_turn": game_state.turn
	}
	_next_id += 1
	orgs.append(org)

	EventBus.org_founded.emit(org)
	return org


func remove_org(region_id: int) -> void:
	for i in range(orgs.size()):
		if orgs[i]["region_id"] == region_id:
			orgs.remove_at(i)
			EventBus.org_destroyed.emit(region_id)
			return


func set_doctrine(region_id: int, new_doctrine: String) -> void:
	var org: Dictionary = get_org_in_region(region_id)
	if org.is_empty():
		push_error("OrgManager.set_doctrine: zadna organizace v regionu %d" % region_id)
		return

	var valid_doctrines: Dictionary = Balance.ORG[org["org_type"]]["doctrines"]
	if not valid_doctrines.has(new_doctrine):
		push_error("OrgManager.set_doctrine: doktrína '%s' neexistuje pro typ '%s'" % [new_doctrine, org["org_type"]])
		return

	org["doctrine"] = new_doctrine
	EventBus.org_doctrine_changed.emit(region_id, new_doctrine)


# ---------------------------------------------------------
# End-of-turn pasivni efekty
# ---------------------------------------------------------

func apply_end_of_turn_effects() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []

	for org in orgs:
		var effects: Dictionary = Balance.get_org_effects(org["org_type"], org["doctrine"])
		if effects.is_empty():
			continue

		var region: Region = game_state.region_manager.get_region(org["region_id"])
		var ctx := EffectContext.make(game_state, region, Balance.ORG_OWNER_PLAYER)

		var effect_logs: Array[Dictionary] = game_state.effects_system.apply(effects, ctx)
		logs += effect_logs

		logs.append({
			"type": "org",
			"text": "Organizace %s (%s) aplikovala efekty doktríny '%s' v regionu %d." % [
				org["org_id"],
				Balance.ORG[org["org_type"]]["display_name"],
				org["doctrine"],
				org["region_id"]
			]
		})

	return logs
