extends Node
class_name ReputationManager

# ReputationManager — pouze cachovaci vrstva.
# Kazdy tah precte stav regionu a organizaci
# a zapise vysledek na Faction objekt.
# Jedine zapisy: faction.reputation,
# faction.reputation_phase, faction.reputation_modifier.

var game_state: GameStateSingleton


# ---------------------------------------------------------
# Verejne API
# ---------------------------------------------------------

func update_all() -> void:
	for faction_id in Balance.REPUTATION_BASE.keys():
		var faction = game_state.faction_manager.get_faction(faction_id)
		if faction == null:
			continue
		var rep: int = _compute_reputation(faction_id)
		var phase: String = _compute_phase(rep)
		var modifier: int = _compute_modifier(phase)
		faction.reputation = rep
		faction.reputation_phase = phase
		faction.reputation_modifier = modifier


func get_reputation_breakdown(faction_id: String) -> Dictionary:
	# Vraci breakdown pro UI zobrazeni:
	# { "base": int, "corruption": int,
	#   "shadow_net": int, "total": int,
	#   "phase": String }
	var base: int = Balance.REPUTATION_BASE.get(faction_id, 50)
	var corruption_score: int = 0
	var shadow_score: int = 0

	var regions = game_state.region_manager.get_regions_by_faction(faction_id)
	for region in regions:
		var phase: int = region.get_corruption_phase_for(Balance.PLAYER_FACTION)
		if phase >= 3:
			corruption_score += Balance.REPUTATION_WEIGHT_CORRUPTION

		var org: Dictionary = game_state.org_manager.get_org_in_region(region.id)
		if not org.is_empty() \
				and org.get("org_type") == "shadow_network" \
				and org.get("owner") == Balance.ORG_OWNER_PLAYER \
				and not org.get("is_rogue", false):
			var loyalty: int = org.get("loyalty", Balance.ORG_LOYALTY_START)
			shadow_score += int(float(loyalty) * Balance.REPUTATION_WEIGHT_SHADOW_NET)

	var total: int = clamp(base + corruption_score + shadow_score, 0, 100)
	return {
		"base":        base,
		"corruption":  corruption_score,
		"shadow_net":  shadow_score,
		"total":       total,
		"phase":       _compute_phase(total)
	}


# ---------------------------------------------------------
# Interni vypocty
# ---------------------------------------------------------

func _compute_reputation(faction_id: String) -> int:
	var base: int = Balance.REPUTATION_BASE.get(faction_id, 50)
	var score: int = base

	var regions = game_state.region_manager.get_regions_by_faction(faction_id)

	# 1) Korupce faze 3+ v regionech frakce
	for region in regions:
		var phase: int = region.get_corruption_phase_for(Balance.PLAYER_FACTION)
		if phase >= 3:
			score += Balance.REPUTATION_WEIGHT_CORRUPTION

	# 2) Shadow Network v regionech frakce
	# Rogue Shadow Network neprisiva k reputaci.
	for region in regions:
		var org: Dictionary = game_state.org_manager.get_org_in_region(region.id)
		if org.is_empty():
			continue
		if org.get("org_type") != "shadow_network":
			continue
		if org.get("owner") != Balance.ORG_OWNER_PLAYER:
			continue
		if org.get("is_rogue", false):
			continue
		var loyalty: int = org.get("loyalty", Balance.ORG_LOYALTY_START)
		score += int(float(loyalty) * Balance.REPUTATION_WEIGHT_SHADOW_NET)

	return clamp(score, 0, 100)


func _compute_phase(reputation: int) -> String:
	if reputation <= Balance.REPUTATION_HOSTILE:
		return "hostile"
	elif reputation <= Balance.REPUTATION_NEUTRAL:
		return "neutral"
	elif reputation <= Balance.REPUTATION_INFILTRATED:
		return "infiltrated"
	else:
		return "controlled"


func _compute_modifier(phase: String) -> int:
	match phase:
		"hostile":
			return Balance.REPUTATION_HEAT_MOD_HOSTILE
		"neutral":
			return Balance.REPUTATION_HEAT_MOD_NEUTRAL
		"infiltrated":
			return Balance.REPUTATION_HEAT_MOD_INFILTRATED
		"controlled":
			return Balance.REPUTATION_HEAT_MOD_CONTROLLED
		_:
			return 0
