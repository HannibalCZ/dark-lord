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

	# Vykonej akci pro aktuální plán (ať switch nebo pokračování)
	var action_def: Dictionary = actions.get(actor.current_plan, {})
	_execute_action(actor, action_def)

# ---------------------------------------------------------------------------
# Action dispatch
# ---------------------------------------------------------------------------

# Přečte handler klíč z action_def a deleguje na příslušný handler.
func _execute_action(actor: AIActor, action_def: Dictionary) -> void:
	var handler: String = action_def.get("handler", "")
	var params: Dictionary = action_def.get("handler_params", {})
	match handler:
		"spawn_unit":
			_handler_spawn_unit(actor, params)
		"move_army_toward_player":
			_handler_move_army_toward_player(actor, params)
		"attack_player_base":
			_handler_attack_player_base(actor, params)
		"":
			pass  # žádná akce
		_:
			push_warning("WorldAI: neznámý handler '%s'" % handler)

# Spawn paladínské armády.
# POZOR: process_ai_spawning() v GameState.advance_turn() (sekce E) již spawní
# paladin_army při heat >= 85 se spawn_rate 4 a limitem 3 jednotek.
# Tento handler zatím pouze loguje záměr — nevykonává duplicitní spawn.
# Budoucí migrace: přesunout spawn logiku sem a odstranit z process_ai_spawning().
func _handler_spawn_unit(actor: AIActor, params: Dictionary) -> void:
	var unit_key: String = params.get("unit_key", "")
	actor.last_decision_log["handler_result"] = {
		"handler": "spawn_unit",
		"unit_key": unit_key,
		"status": "delegated_to_existing",
		"note": "process_ai_spawning() v GameState sekce E"
	}

# Přesun paladínských armád směrem k hráči (heat 85 — fáze výhrůžky).
# POZOR: AIManager.execute_ai_turn() již pohybuje všemi paladin_army jednotkami
# přes profil paladin_threat (AGGRESSIVE behavior) nastaveným v _check_heat_thresholds().
# Tento handler zatím pouze loguje záměr — nevykonává duplicitní pohyb.
# Budoucí migrace: přesunout pohybovou logiku sem a řídit přes WorldAI plán.
func _handler_move_army_toward_player(actor: AIActor, params: Dictionary) -> void:
	actor.last_decision_log["handler_result"] = {
		"handler": "move_army_toward_player",
		"status": "delegated_to_existing",
		"note": "AIManager paladin_threat profil (AGGRESSIVE behavior)"
	}

# Útok na hráčovu základnu (heat 100 — závěrečná výprava).
# POZOR: AIManager.execute_ai_turn() již pohybuje paladin_army jednotkami
# přes profil final_assault (COORDINATED behavior) nastaveným v _check_heat_thresholds().
# Tento handler zatím pouze loguje záměr — nevykonává duplicitní útok.
# Budoucí migrace: přesunout útočnou logiku sem a řídit přes WorldAI plán.
func _handler_attack_player_base(actor: AIActor, params: Dictionary) -> void:
	actor.last_decision_log["handler_result"] = {
		"handler": "attack_player_base",
		"target_region": game_state.player_start_region_id,
		"status": "delegated_to_existing",
		"note": "AIManager final_assault profil (COORDINATED behavior)"
	}

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
