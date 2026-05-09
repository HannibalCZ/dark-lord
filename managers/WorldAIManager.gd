# managers/WorldAIManager.gd
# Řídí AI aktéry (paladíni a budoucí frakce) — utility scoring, plánování, dispatch.
# Voláno z GameState.advance_turn() sekce C po tags_manager.process_end_of_turn().
extends Resource
class_name WorldAIManager

var game_state: GameStateSingleton

# Interní stav aktérů — přistupovat pouze přes metody tohoto manažera.
var _actors: Dictionary = {}  # { faction_id: AIActor }

# ---------------------------------------------------------------------------
# Inicializace
# ---------------------------------------------------------------------------

# Vytvoří AIActor pro každý faction_id definovaný v AIProfiles.ACTORS.
# Volat z GameState.load_scenario() po načtení frakcí — ne z _ready().
func init_actors() -> void:
	_actors.clear()
	for faction_id in AIProfiles.ACTORS.keys():
		var actor := AIActor.new()
		actor.faction_id = faction_id
		_actors[faction_id] = actor

# ---------------------------------------------------------------------------
# Herní smyčka
# ---------------------------------------------------------------------------

# Hlavní entry point — volat z GameState.advance_turn().
func process_turn() -> void:
	for faction_id in _actors.keys():
		var actor: AIActor = _actors[faction_id]
		var profile: Dictionary = AIProfiles.ACTORS.get(faction_id, {})
		if profile.is_empty():
			continue
		_process_actor(actor, profile)

# ---------------------------------------------------------------------------
# Interní — jeden aktér
# ---------------------------------------------------------------------------

func _process_actor(actor: AIActor, profile: Dictionary) -> void:
	var actions: Dictionary = profile.get("actions", {})
	var threshold: float = profile.get("plan_switch_threshold", 0.25)

	# Vypočítej skóre pro všechny akce
	var scores: Dictionary = {}
	for action_key in actions.keys():
		scores[action_key] = _calculate_action_score(action_key, actions[action_key], actor.faction_id)

	# Najdi nejvýše hodnocenou akci
	var best_action: String = ""
	var best_score: float = -1.0
	for action_key in scores.keys():
		if scores[action_key] > best_score:
			best_score = scores[action_key]
			best_action = action_key

	# Plan persistence — přepni pouze pokud rozdíl překročí threshold
	var should_switch: bool = false
	if actor.current_plan == "":
		should_switch = true
	elif best_action != actor.current_plan:
		var current_score: float = scores.get(actor.current_plan, 0.0)
		should_switch = (best_score - current_score) > threshold

	# Zaloguj rozhodnutí — designer vidí skóre všech akcí a důvod přepnutí
	var reason: String
	if should_switch and actor.current_plan != "":
		reason = "threshold překročen"
	elif actor.current_plan == "":
		reason = "nový plán"
	else:
		reason = "pokračuje v plánu"

	actor.last_decision_log = {
		"turn": game_state.turn,
		"faction": actor.faction_id,
		"scores": scores,
		"current_plan": actor.current_plan,
		"best_action": best_action,
		"switched": should_switch,
		"reason": reason
	}

	if should_switch:
		actor.current_plan = best_action
		actor.plan_utility = best_score
		actor.plan_turn = game_state.turn

# ---------------------------------------------------------------------------
# Utility scoring
# ---------------------------------------------------------------------------

# Vypočítá výsledné utility skóre akce aplikací všech score_modifiers.
# Modifikátory se násobí v pořadí — podmínky jsou nezávislé, ne exkluzivní.
func _calculate_action_score(action_key: String, action_def: Dictionary, faction_id: String) -> float:
	var score: float = action_def.get("base_score", 0.0)
	var modifiers: Array = action_def.get("score_modifiers", [])
	for modifier in modifiers:
		var condition: String = modifier.get("condition", "")
		var multiplier: float = modifier.get("multiplier", 1.0)
		if _evaluate_condition(condition, faction_id):
			score *= multiplier
	return score

# Vyhodnotí condition string formátu "stat op value" (např. "heat > 25").
# Při neplatném formátu vrátí false a zaloguje warning — nikdy nezpůsobí crash.
func _evaluate_condition(condition: String, faction_id: String) -> bool:
	var parts: Array = condition.split(" ")
	if parts.size() != 3:
		push_warning("WorldAI: neplatný formát condition '%s'" % condition)
		return false

	var stat: String = parts[0]
	var op: String = parts[1]
	var target: float = float(parts[2])
	var value: float = _get_stat_value(stat, faction_id)

	match op:
		">":  return value > target
		"<":  return value < target
		">=": return value >= target
		"<=": return value <= target
		"==": return value == target
		_:
			push_warning("WorldAI: neznámý operátor '%s' v condition '%s'" % [op, condition])
			return false

# Načte aktuální hodnotu herního statu podle klíče.
# infamy je vlastnost player frakce — AI aktéři reagují na hráčovu reputaci.
func _get_stat_value(stat: String, faction_id: String) -> float:
	match stat:
		"heat":
			return float(game_state.heat)
		"awareness":
			return float(game_state.awareness)
		"infamy":
			var player_faction = game_state.faction_manager.get_faction(Balance.PLAYER_FACTION)
			if player_faction == null:
				push_warning("WorldAI: player frakce nenalezena při čtení infamy")
				return 0.0
			return float(player_faction.infamy)
		"turn":
			return float(game_state.turn)
		_:
			push_warning("WorldAI: neznámý stat '%s'" % stat)
			return 0.0
