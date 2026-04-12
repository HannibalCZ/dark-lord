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


func get_available_doctrines(region_id: int) -> Array[Dictionary]:
	var org: Dictionary = get_org_in_region(region_id)
	if org.is_empty():
		return []
	var current_doctrine: String = org["doctrine"]
	var doctrines_cfg: Dictionary = Balance.ORG[org["org_type"]]["doctrines"]
	var result: Array[Dictionary] = []
	for key in doctrines_cfg.keys():
		var d: Dictionary = doctrines_cfg[key]
		result.append({
			"key":          key,
			"display_name": d["display_name"],
			"effects":      d["effects"],
			"is_current":   key == current_doctrine
		})
	return result


func get_org_display_data(region_id: int) -> Dictionary:
	var org: Dictionary = get_org_in_region(region_id)
	if org.is_empty():
		return { "has_org": false }
	var org_type: String     = org["org_type"]
	var doctrine_key: String = org["doctrine"]
	var org_cfg: Dictionary      = Balance.ORG[org_type]
	var doctrine_cfg: Dictionary = org_cfg["doctrines"][doctrine_key]
	return {
		"has_org":          true,
		"org_type":         org_type,
		"display_name":     org_cfg["display_name"],
		"owner":            org["owner"],
		"doctrine_key":     doctrine_key,
		"doctrine_display": doctrine_cfg["display_name"],
		"is_player_org":    org["owner"] == Balance.ORG_OWNER_PLAYER
	}


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
		"founded_turn": game_state.turn,
		"loyalty":      Balance.ORG_LOYALTY_START,
		"is_rogue":     false
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
# Loajalitni helpery
# ---------------------------------------------------------

func _get_loyalty_phase(loyalty: int) -> String:
	if loyalty <= 0:
		return "rogue"
	elif loyalty < Balance.ORG_LOYALTY_STABLE:
		return "unstable"
	elif loyalty < Balance.ORG_LOYALTY_FAITHFUL:
		return "stable"
	else:
		return "faithful"


func _get_loyalty_multiplier(loyalty: int) -> float:
	match _get_loyalty_phase(loyalty):
		"faithful": return Balance.ORG_LOYALTY_MULT_FAITHFUL
		"stable":   return Balance.ORG_LOYALTY_MULT_STABLE
		"unstable": return Balance.ORG_LOYALTY_MULT_UNSTABLE
		_:          return 0.0  # rogue — zadne efekty


func _scale_effects(effects: Dictionary, mult: float) -> Dictionary:
	var scaled: Dictionary = {}
	for key in effects:
		var val = effects[key]
		if val is int:
			scaled[key] = int(round(float(val) * mult))
		elif val is float:
			scaled[key] = val * mult
		else:
			scaled[key] = val  # string, bool, Array — beze zmeny
	return scaled


# Centralni misto pro skálovane efekty org podle loyalty.
# Volaj misto Balance.get_org_effects() vsude kde se efekty pouzivaji.
func get_org_effects_scaled(org: Dictionary) -> Dictionary:
	if org.get("is_rogue", false):
		return {}  # Rogue org negeneruje zadne efekty
	var base: Dictionary = Balance.get_org_effects(org["org_type"], org["doctrine"])
	var loyalty: int = org.get("loyalty", Balance.ORG_LOYALTY_START)
	var mult: float = _get_loyalty_multiplier(loyalty)
	return _scale_effects(base, mult)


# ---------------------------------------------------------
# End-of-turn pasivni efekty
# ---------------------------------------------------------

func apply_end_of_turn_effects() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []

	for org in orgs:
		var org_type: String = org["org_type"]
		var display_name: String = Balance.ORG[org_type]["display_name"]
		var region: Region = game_state.region_manager.get_region(org["region_id"])

		# Neutral/Rogue org: aplikuj ORG_NEUTRAL_EFFECTS misto doktriny
		if org.get("owner") != Balance.ORG_OWNER_PLAYER:
			var neutral_effects: Dictionary = Balance.ORG_NEUTRAL_EFFECTS.get(org_type, {})
			if neutral_effects.is_empty():
				continue
			# mission_penalty neni EffectsSystem klic — preskocit
			var eff_to_apply: Dictionary = {}
			for key in neutral_effects:
				if key != "mission_penalty":
					eff_to_apply[key] = neutral_effects[key]
			if not eff_to_apply.is_empty():
				var ctx := EffectContext.make(game_state, region, org.get("owner", "neutral"))
				ctx.source_label = "Neutral organizace: %s" % display_name
				var effect_logs: Array[Dictionary] = game_state.effects_system.apply(eff_to_apply, ctx)
				logs += effect_logs
				logs.append({
					"type": "org",
					"text": "Neutral organizace %s (%s) aplikovala pasivni efekty v regionu %d." % [
						org["org_id"], display_name, org["region_id"]
					]
				})
			continue

		# Hracova org: standardni doktrinarni efekty
		var all_effects: Dictionary = get_org_effects_scaled(org)
		if all_effects.is_empty():
			continue

		# gold/mana org efektu jsou zahrnuty v
		# EconomicManager.compute_income_and_upkeep()
		# aby sly pres jeden centralni vypocet prijmu.
		# Zde aplikujeme pouze neekonomicke efekty (heat, awareness, atd.).
		var non_economic: Dictionary = {}
		for key in all_effects:
			if key != "gold" and key != "mana":
				non_economic[key] = all_effects[key]

		if not non_economic.is_empty():
			var ctx := EffectContext.make(game_state, region, Balance.ORG_OWNER_PLAYER)
			ctx.source_label = "Organizace: %s" % display_name
			var effect_logs: Array[Dictionary] = game_state.effects_system.apply(non_economic, ctx)
			logs += effect_logs

		logs.append({
			"type": "org",
			"text": "Organizace %s (%s) aplikovala efekty doktríny '%s' v regionu %d." % [
				org["org_id"], display_name, org["doctrine"], org["region_id"]
			]
		})

	return logs


# ---------------------------------------------------------
# Loajalitni decay
# ---------------------------------------------------------

func apply_loyalty_decay() -> void:
	var player_fac = game_state.faction_manager.get_faction(Balance.PLAYER_FACTION)
	if player_fac == null:
		return
	var infamy: float = player_fac.get_resource("infamy")

	var decay: int
	if infamy <= Balance.ORG_INFAMY_LOW:
		decay = Balance.ORG_LOYALTY_DECAY_LOW
	elif infamy <= Balance.ORG_INFAMY_MID:
		decay = Balance.ORG_LOYALTY_DECAY_MID
	elif infamy <= Balance.ORG_INFAMY_HIGH:
		decay = Balance.ORG_LOYALTY_DECAY_HIGH
	else:
		decay = Balance.ORG_LOYALTY_DECAY_VERY_HIGH

	for org in orgs:
		if org.get("is_rogue", false):
			continue  # Rogue orgy se dal nezhorsuji
		if org.get("owner") != Balance.ORG_OWNER_PLAYER:
			continue  # Neutral/rival orgy nemaji loyalty decay
		var new_loyalty: int = org.get("loyalty", Balance.ORG_LOYALTY_START) - decay
		if new_loyalty <= 0:
			org["loyalty"] = 0
			org["is_rogue"] = true
			EventBus.org_went_rogue.emit(org["org_id"], org["region_id"])
		else:
			org["loyalty"] = new_loyalty
