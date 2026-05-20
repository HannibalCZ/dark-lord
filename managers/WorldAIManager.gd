# managers/WorldAIManager.gd
# Řídí AI aktéry (paladíni a budoucí frakce) — utility scoring, plánování, dispatch.
# Voláno z GameState.advance_turn() sekce C po tags_manager.process_end_of_turn().
extends Resource
class_name WorldAIManager

var game_state: GameStateSingleton

# Interní stav aktérů — přistupovat pouze přes metody tohoto manažera.
var _actors: Dictionary = {}  # { faction_id: AIActor }

# Migrovaní aktéři (Epics 1–3 dokončeny):
#   "paladin" — eskalační chování (E1), spawn rozhodnutí (E2), strategický target (E3)

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

# Nastaví current_behavior pro každou řízenou frakci podle aktuálního herního stavu.
# Voláno z GameState.advance_turn() po reputation_manager.update_all() —
# reputation_modifier musí být čerstvě přepočítán před výpočtem efektivního heatu.
func update_faction_behaviors() -> void:
	_update_paladin_behavior()

func _update_paladin_behavior() -> void:
	var faction: Faction = game_state.faction_manager.get_faction("paladin")
	if faction == null:
		return
	var eff: int = game_state.heat + faction.reputation_modifier
	if eff >= Balance.HEAT_MAX:
		faction.current_behavior = Faction.Behavior.COORDINATED
	elif eff >= Balance.HEAT_STAGE_3:
		faction.current_behavior = Faction.Behavior.AGGRESSIVE
	elif eff >= Balance.HEAT_STAGE_2:
		faction.current_behavior = Faction.Behavior.ACTING
	elif eff >= Balance.HEAT_STAGE_1:
		faction.current_behavior = Faction.Behavior.PATROLLING
	else:
		faction.current_behavior = Faction.Behavior.PASSIVE

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

	# Vypočítej skóre pro všechny akce — každé je Dictionary { score, base, breakdown }
	var scores: Dictionary = {}
	for action_key in actions.keys():
		scores[action_key] = _calculate_action_score(action_key, actions[action_key], actor.faction_id)

	# Najdi nejvýše hodnocenou akci
	var best_action: String = ""
	var best_score: float = -1.0
	for action_key in scores.keys():
		var s: float = scores[action_key]["score"]
		if s > best_score:
			best_score = s
			best_action = action_key

	# Plan persistence — přepni pouze pokud rozdíl překročí threshold
	var should_switch: bool = false
	var reason: String
	if actor.current_plan == "":
		should_switch = true
		reason = "nový plán"
	elif best_action != actor.current_plan:
		var current_score: float = scores.get(actor.current_plan, {"score": 0.0}).get("score", 0.0)
		var delta: float = best_score - current_score
		if delta > threshold:
			should_switch = true
			reason = "threshold překročen (rozdíl %.2f > %.2f)" % [delta, threshold]
		else:
			reason = "pokračuje v plánu"
	else:
		reason = "pokračuje v plánu"

	# Extrahuj breakdowns pro pohodlný přístup z debug UI
	var breakdowns: Dictionary = {}
	for action_key in scores.keys():
		breakdowns[action_key] = scores[action_key].get("breakdown", [])

	# Zaloguj rozhodnutí — designer vidí skóre všech akcí a důvod přepnutí
	actor.last_decision_log = {
		"turn": game_state.turn,
		"faction": actor.faction_id,
		"scores": scores,
		"breakdowns": breakdowns,
		"current_plan": actor.current_plan,
		"best_action": best_action,
		"switched": should_switch,
		"reason": reason,
	}

	if should_switch:
		actor.current_plan = best_action
		actor.plan_utility = best_score
		actor.plan_turn = game_state.turn

	# Strategický cíl pro aktuální plán — každý tah čerstvě
	actor.current_target_region_id = _compute_target_region(actor)

	# Vykonej akci pro aktuální plán (ať switch nebo pokračování)
	var action_def: Dictionary = actions.get(actor.current_plan, {})
	_execute_action(actor, action_def)

# ---------------------------------------------------------------------------
# Public read API
# ---------------------------------------------------------------------------

# Vrátí snapshot stavu všech aktérů pro debug UI.
# Nevolej _actors přímo zvenčí — používej tuto metodu.
func get_all_actor_snapshots() -> Array:
	var result: Array = []
	for faction_id in _actors.keys():
		var actor: AIActor = _actors[faction_id]
		result.append({
			"faction_id": faction_id,
			"active_plan": actor.current_plan,
			"plan_turn": actor.plan_turn,
			"log": actor.last_decision_log.duplicate()
		})
	return result

# Vrátí AIActor pro danou frakci, nebo null pokud frakce nemá WorldAI aktéra.
func get_actor(faction_id: String) -> AIActor:
	return _actors.get(faction_id, null)

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

# Spawn jednotky pro frakci řízenou WorldAI.
# Čte konfiguraci z Balance.AI_SPAWN[faction_id] (threshold, spawn_rate, unit_limit).
# Spravuje faction.spawn_counter a faction.ai_regular_spawns_enabled.
# Deleguje mechanické provedení na game_state._spawn_faction_unit().
func _handler_spawn_unit(actor: AIActor, params: Dictionary) -> void:
	var unit_key: String = params.get("unit_key", "")
	var cfg: Dictionary = Balance.AI_SPAWN.get(actor.faction_id, {})
	if cfg.is_empty() or unit_key == "":
		actor.last_decision_log["handler_result"] = {
			"handler": "spawn_unit", "status": "no_config"
		}
		return

	var faction: Faction = game_state.faction_manager.get_faction(actor.faction_id)
	if faction == null:
		return

	# Ovládnutá frakce nespawnuje — reset counteru
	if faction.reputation_phase == "controlled":
		faction.spawn_counter = 0
		faction.ai_regular_spawns_enabled = false
		actor.last_decision_log["handler_result"] = {
			"handler": "spawn_unit", "status": "controlled"
		}
		return

	# Trigger threshold + reputation modifier
	var trigger_value: int = game_state.heat if cfg.get("trigger") == "heat" \
							 else game_state.awareness
	var effective_threshold: int = int(cfg["threshold"]) + faction.reputation_modifier
	faction.ai_regular_spawns_enabled = trigger_value >= effective_threshold

	if not faction.ai_regular_spawns_enabled:
		faction.spawn_counter = 0
		actor.last_decision_log["handler_result"] = {
			"handler": "spawn_unit", "status": "below_threshold",
			"trigger": trigger_value, "threshold": effective_threshold
		}
		return

	# Unit limit
	var current_count: int = game_state.query.units.count_units_by_faction_and_key(
		actor.faction_id, unit_key)
	if current_count >= int(cfg["unit_limit"]):
		actor.last_decision_log["handler_result"] = {
			"handler": "spawn_unit", "status": "at_limit", "count": current_count
		}
		return

	# Spawn counter
	faction.spawn_counter += 1
	if faction.spawn_counter < int(cfg["spawn_rate"]):
		actor.last_decision_log["handler_result"] = {
			"handler": "spawn_unit", "status": "counter_wait",
			"counter": faction.spawn_counter, "rate": cfg["spawn_rate"]
		}
		return

	faction.spawn_counter = 0
	game_state._spawn_faction_unit(actor.faction_id, unit_key)
	actor.last_decision_log["handler_result"] = {
		"handler": "spawn_unit", "status": "spawned", "unit_key": unit_key
	}

# Přesun paladínských armád směrem k hráči (heat 85 — fáze výhrůžky).
# POZOR: AIManager.execute_ai_turn() již pohybuje všemi paladin_army jednotkami
# přes profil paladin_threat (AGGRESSIVE behavior) nastaveným v update_faction_behaviors().
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
# přes profil final_assault (COORDINATED behavior) nastaveným v update_faction_behaviors().
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

# Vypočítá utility skóre akce. Vrací Dictionary: { score, base, breakdown }.
# breakdown je Array kroků — každý krok zaznamenává stav před/po aplikaci multiplikátoru.
func _calculate_action_score(action_key: String, action_def: Dictionary, faction_id: String) -> Dictionary:
	var base: float = action_def.get("base_score", 0.0)
	var score: float = base
	var breakdown: Array = []
	for modifier in action_def.get("score_modifiers", []):
		var condition: String = modifier.get("condition", "")
		var multiplier: float = modifier.get("multiplier", 1.0)
		var met: bool = _evaluate_condition(condition, faction_id)
		var score_after: float = score * multiplier if met else score
		breakdown.append({
			"condition": condition,
			"met": met,
			"multiplier": multiplier,
			"score_before": score,
			"score_after": score_after,
		})
		if met:
			score = score_after
	return {"score": score, "base": base, "breakdown": breakdown}

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

# Vypočítá strategický cílový region pro aktuální plán aktéra.
# Referenční bod: player_start_region_id (paladíni útočí na hráčův lair).
# Vrátí -1 pokud plán nemá target blok nebo region nelze najít.
func _compute_target_region(actor: AIActor) -> int:
	var action_def: Dictionary = AIProfiles.ACTORS.get(actor.faction_id, {}) \
									.get("actions", {}).get(actor.current_plan, {})
	var target_def: Dictionary = action_def.get("target", {})
	if target_def.is_empty():
		return -1

	var ref_id: int = game_state.player_start_region_id
	if ref_id < 0:
		return -1

	var select: String = target_def.get("select", "nearest")
	var filters: Dictionary = target_def.get("filters", {})
	match select:
		"nearest":
			return game_state.query.regions.find_nearest_with_filters(
				ref_id, actor.faction_id, filters)
		_:
			return -1

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
