# managers/WorldAIManager.gd
# Řídí AI aktéry (paladíni a budoucí frakce) — utility scoring, plánování, dispatch.
# Voláno z GameState.advance_turn() sekce C po tags_manager.process_end_of_turn().
extends Resource
class_name WorldAIManager

var game_state: GameStateSingleton

# Interní stav aktérů — přistupovat pouze přes metody tohoto manažera.
var _actors: Dictionary = {}  # { faction_id: AIActor }

# Migrovaní aktéři (Epics 1–3 dokončeny):
#   "paladin"   — eskalační chování (E1), spawn rozhodnutí (E2), strategický target (E3)
#   "merchant"  — trade/defend agenda (log-only; taktická logika zůstává v AIManager)

# ---------------------------------------------------------------------------
# Inicializace
# ---------------------------------------------------------------------------

# Přidá chybějící aktéry ze statických profilů. Idempotentní — opakované volání
# nevytváří duplicity a nezničí dynamicky vytvořené network faction actors.
# Volat z GameState.load_scenario() po načtení frakcí — ne z _ready().
# Pro čistý reset volej reset_actors() před tímto.
func init_actors() -> void:
	for faction_id in AIProfiles.ACTORS.keys():
		if _actors.has(faction_id):
			continue  # guard — nepřepisuj existující actor
		if faction_id.ends_with("_network"):
			continue  # network profile actory se vytváří lazily v process_turn()
		if faction_id.begins_with("lair_"):
			continue  # lair actory se inicializují zvlášť níže
		var actor := AIActor.new()
		actor.faction_id = faction_id
		_actors[faction_id] = actor

	# Lair aktéři — jeden per Lair frakce, profil podle source_faction_id a lair_directive
	for faction in game_state.faction_manager.get_all_lair_factions():
		if _actors.has(faction.id):
			continue
		var region: Region = game_state.query.regions.get_by_id(faction.lair_region_id)
		var actor := AIActor.new()
		actor.faction_id = faction.id
		_actors[faction.id] = actor
		# Nastav výchozí plán podle profilu
		var profile_key: String = _get_lair_profile(faction, region)
		var profile: Dictionary = AIProfiles.ACTORS.get(profile_key, {})
		if not profile.is_empty():
			actor.current_plan = profile.get("actions", {}).keys()[0] if not profile.get("actions", {}).is_empty() else ""

# Vymaže všechny aktéry včetně dynamicky vytvořených network faction actors.
# Volat z GameState.load_scenario() před init_actors() pro čistý start.
func reset_actors() -> void:
	_actors.clear()

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
	# Vyčisti stale actory pro zničené network frakce
	for actor_id in _actors.keys():
		if not AIProfiles.ACTORS.has(actor_id):
			if game_state.faction_manager.get_faction(actor_id) == null:
				_actors.erase(actor_id)

	for faction_id in _actors.keys():
		var actor: AIActor = _actors[faction_id]
		var profile: Dictionary = AIProfiles.ACTORS.get(faction_id, {})
		if profile.is_empty():
			continue
		_process_actor(actor, profile)

	# Lair aktéři — zpracuj přes dynamicky určený profil
	for faction in game_state.faction_manager.get_all_lair_factions():
		var lair_id: String = faction.id
		if not _actors.has(lair_id):
			var actor := AIActor.new()
			actor.faction_id = lair_id
			_actors[lair_id] = actor
		var lair_actor: AIActor = _actors[lair_id]
		var region: Region = game_state.query.regions.get_by_id(faction.lair_region_id)
		var profile_key: String = _get_lair_profile(faction, region)
		var lair_profile: Dictionary = AIProfiles.ACTORS.get(profile_key, {})
		if not lair_profile.is_empty():
			_process_actor(lair_actor, lair_profile)

	# Network frakce — lazy actor creation + zpracování
	for faction in game_state.faction_manager.all():
		if faction.faction_type != "network":
			continue
		var nf_id: String = faction.id
		if not _actors.has(nf_id):
			var actor := AIActor.new()
			actor.faction_id = nf_id
			_actors[nf_id] = actor
		var nf_actor: AIActor = _actors[nf_id]
		var profile_key: String = faction.network_type + "_network"
		var profile: Dictionary = AIProfiles.ACTORS.get(profile_key, {})
		if profile.is_empty():
			continue
		_process_actor(nf_actor, profile)

# ---------------------------------------------------------------------------
# Interní — jeden aktér
# ---------------------------------------------------------------------------

func _process_actor(actor: AIActor, profile: Dictionary) -> void:
	var actions: Dictionary = profile.get("actions", {})
	var threshold: float = profile.get("plan_switch_threshold", 0.25)

	var faction = game_state.faction_manager.get_faction(actor.faction_id)
	var player_faction = game_state.faction_manager.get_faction(Balance.PLAYER_FACTION)

	var influence_avg: float = 0.0
	if faction and not faction.influence.is_empty():
		var total: float = 0.0
		for v in faction.influence.values():
			total += float(v)
		influence_avg = total / float(faction.influence.size())

	var has_rival := false
	if faction:
		for region_id in faction.influence.keys():
			var rival = game_state.faction_manager.get_network_faction_in_region(region_id)
			if rival != null and rival.id != actor.faction_id:
				has_rival = true
				break

	var context: Dictionary = {
		"heat":          game_state.heat,
		"awareness":     game_state.awareness,
		"turn":          game_state.turn,
		"infamy":        player_faction.get_resource("infamy") if player_faction else 0.0,
		"doctrine":      faction.doctrine if faction else "",
		"visibility":    faction.visibility if faction else 0,
		"influence":     influence_avg,
		"faction_id":    actor.faction_id,
		"rival_present": has_rival,
	}

	# Tick active_modifiers a přidej do context
	for key in actor.active_modifiers.keys():
		var mod = actor.active_modifiers[key]
		context[key] = mod["value"]
		mod["turns_remaining"] -= 1
		if mod["turns_remaining"] <= 0:
			actor.active_modifiers.erase(key)
			EventBus.ai_modifier_expired.emit(actor.faction_id, key)

	# Vypočítej skóre pro všechny akce — každé je Dictionary { score, base, breakdown }
	var scores: Dictionary = {}
	for action_key in actions.keys():
		scores[action_key] = _calculate_action_score(action_key, actions[action_key], context)

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
# Lair profily
# ---------------------------------------------------------------------------

func _get_lair_profile(faction: Faction, region: Region) -> String:
	if faction.source_faction_id != Balance.PLAYER_FACTION:
		return "lair_neutral"
	if region == null:
		return "lair_defensive"
	match region.lair_directive:
		Balance.LAIR_DIRECTIVE_RAIDER: return "lair_raider"
		_: return "lair_defensive"

# Přepne plán Lair aktéra pokud nový profil aktuální plán neobsahuje.
func update_lair_actor_profile(region_id: int) -> void:
	var faction: Faction = game_state.faction_manager.get_lair_faction_for_region(region_id)
	if faction == null or not _actors.has(faction.id):
		return
	var region: Region = game_state.query.regions.get_by_id(region_id)
	var new_profile_key: String = _get_lair_profile(faction, region)
	var actor: AIActor = _actors[faction.id]
	var actions: Dictionary = AIProfiles.ACTORS.get(new_profile_key, {}).get("actions", {})
	if not actions.has(actor.current_plan):
		actor.current_plan = actions.keys()[0] if not actions.is_empty() else ""

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
			"log": actor.last_decision_log.duplicate(),
			"active_modifiers": actor.active_modifiers.duplicate()
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
		"stay_dormant":
			_handler_stay_dormant(actor, params)
		"activate_inquisition":
			_handler_activate_inquisition(actor, params)
		"spawn_colonist":
			_handler_spawn_colonist(actor, params)
		"merchant_trade":
			_handler_merchant_trade(actor, params)
		"merchant_defend":
			_handler_merchant_defend(actor, params)
		"network_grow":
			_handler_network_grow(actor, params)
		"network_action":
			_handler_network_action(actor, action_def)
		"network_expand":
			_handler_network_expand(actor, action_def)
		"network_suppress":
			_handler_network_suppress(actor, action_def)
		"lair_idle":
			_handler_lair_idle(actor)
		"lair_stay":
			_handler_lair_stay(actor)
		"lair_raid":
			_handler_lair_raid(actor)
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

func _handler_spawn_colonist(actor: AIActor, _params: Dictionary) -> void:
	# Spawnuje elfího kolonizátora v elfím hraničním regionu sousedícím s uninhabited územím.
	# Podmínky: alespoň 1 uninhabited neutral region sousedí s elfím územím AND živé kolonizátory < 2.
	var elf_regions := game_state.query.regions.regions_owned_by("elf")
	var spawn_candidates: Array[int] = []
	for er in elf_regions:
		for n_id in game_state.query.regions.neighbors(er.id):
			var nr := game_state.query.regions.get_by_id(n_id)
			if nr != null and not nr.inhabited and nr.owner_faction_id == "neutral":
				if not spawn_candidates.has(er.id):
					spawn_candidates.append(er.id)
	if spawn_candidates.is_empty():
		actor.last_decision_log["handler_result"] = {
			"handler": "spawn_colonist", "status": "no_adjacent_uninhabited"
		}
		return
	# Limit: maximálně 2 živí kolonizátoři najednou
	var colonist_count: int = game_state.query.units.count_units_by_faction_and_key("elf", "elf_colonist")
	if colonist_count >= 2:
		actor.last_decision_log["handler_result"] = {
			"handler": "spawn_colonist", "status": "limit_reached", "count": colonist_count
		}
		return
	# Spawn v prvním elfím regionu — kolonizátor se pak pohybuje k cíli přes colonist AI profil.
	game_state._spawn_faction_unit("elf", "elf_colonist")
	actor.last_decision_log["handler_result"] = {
		"handler": "spawn_colonist", "status": "spawned"
	}

func _handler_stay_dormant(actor: AIActor, params: Dictionary) -> void:
	actor.last_decision_log["handler_result"] = "dormant — inkvizice čeká"

func _handler_activate_inquisition(actor: AIActor, params: Dictionary) -> void:
	# Taktická logika zůstává v AIManager — zde pouze logujeme strategické rozhodnutí
	actor.last_decision_log["handler_result"] = "active — inkvizice pronásleduje"

func _handler_merchant_trade(actor: AIActor, _params: Dictionary) -> void:
	# Obchodníci udržují obchodní aktivity — taktická logika v AIManager
	# Budoucí migrace: propojit s ekonomickým systémem frakce
	actor.last_decision_log["handler_result"] = "trade — obchodní aktivita probíhá"

func _handler_merchant_defend(actor: AIActor, _params: Dictionary) -> void:
	# Obchodníci posilují obranu — taktická logika v AIManager
	# Budoucí migrace: spawn obranných jednotek při ohrožení
	actor.last_decision_log["handler_result"] = "defend — posílení obrany"

func _handler_lair_idle(actor: AIActor) -> void:
	actor.last_decision_log["handler_result"] = "idle — doupě čeká"

func _handler_lair_stay(actor: AIActor) -> void:
	# Jednotky zůstanou v Lairu — taktická logika (defender profil) v AIManager
	actor.last_decision_log["handler_result"] = "stay — jednotky brání doupě"

func _handler_lair_raid(actor: AIActor) -> void:
	# Jednotky útočí na nejbližší civilizovaný region — taktická logika v AIManager (lair_raider_active)
	actor.last_decision_log["handler_result"] = "raid — jednotky nájezdí"

func _handler_network_grow(actor: AIActor, _params: Dictionary) -> void:
	var faction: Faction = game_state.faction_manager.get_faction(actor.faction_id)
	if faction == null:
		return
	for region_id in faction.influence.keys():
		faction.influence[region_id] = min(
			faction.influence[region_id] + Balance.NETWORK_GROW_AMOUNT,
			100
		)
	faction.visibility = min(faction.visibility + Balance.NETWORK_VISIBILITY_GROW, 100)
	actor.last_decision_log["handler_result"] = "grew influence in %d regions" % faction.influence.size()

func _handler_network_action(actor: AIActor, action_def: Dictionary) -> void:
	var faction: Faction = game_state.faction_manager.get_faction(actor.faction_id)
	if faction == null:
		return
	var effects: Dictionary = action_def.get("effects", {})

	if effects.has("gold"):
		faction.change_resource("gold", float(effects["gold"]))
	if effects.has("visibility"):
		faction.visibility = clamp(
			faction.visibility + int(effects["visibility"]),
			0, Balance.NETWORK_VISIBILITY_MAX
		)
	if effects.has("influence"):
		for region_id in faction.influence.keys():
			faction.influence[region_id] = clamp(
				faction.influence[region_id] + int(effects["influence"]),
				0, Balance.NETWORK_INFLUENCE_MAX
			)

	actor.last_decision_log["handler_result"] = "applied effects: %s" % str(effects)
	Log_Manager.add({
		"type": "network",
		"text": "🕸 %s: %s" % [_network_display_name(faction), actor.current_plan]
	})

func _handler_network_expand(actor: AIActor, action_def: Dictionary) -> void:
	var faction: Faction = game_state.faction_manager.get_faction(actor.faction_id)
	if faction == null:
		return
	var effects: Dictionary = action_def.get("effects", {})
	var gold_cost: float = float(effects.get("gold_cost", 0))
	var influence_cost: int = int(effects.get("influence_cost", 0))
	var initial_influence: int = int(effects.get("initial_influence", Balance.NETWORK_INFLUENCE_INITIAL))

	# Najdi zdrojový region s dostatečnou influence
	var source_id: int = -1
	for region_id in faction.influence.keys():
		if faction.influence[region_id] >= Balance.NETWORK_EXPANSION_THRESHOLD:
			source_id = region_id
			break

	if source_id < 0:
		actor.last_decision_log["handler_result"] = "expand: no region above threshold %d" % Balance.NETWORK_EXPANSION_THRESHOLD
		return

	# Najdi sousední region bez network faction
	var candidates: Array[int] = game_state.query.regions.get_neighbors_without_network_faction(source_id)
	if candidates.is_empty():
		actor.last_decision_log["handler_result"] = "expand: no free neighbor for region %d" % source_id
		return

	# Ověř zlato
	var current_gold: float = faction.get_resource("gold")
	if current_gold < gold_cost:
		actor.last_decision_log["handler_result"] = "expand: insufficient gold (%.1f < %.1f)" % [current_gold, gold_cost]
		return

	var target_id: int = candidates[0]
	faction.influence[source_id] = max(0, faction.influence[source_id] - influence_cost)
	faction.change_resource("gold", -gold_cost)
	faction.influence[target_id] = initial_influence
	faction.visibility = clamp(
		faction.visibility + int(effects.get("visibility", 0)),
		0, Balance.NETWORK_VISIBILITY_MAX
	)

	EventBus.network_faction_expanded.emit(actor.faction_id, source_id, target_id)
	var from_name: String = _region_name(source_id)
	var to_name: String = _region_name(target_id)
	actor.last_decision_log["handler_result"] = "expand: %d → %d (cost gold %.1f, influence %d)" % [
		source_id, target_id, gold_cost, influence_cost
	]
	Log_Manager.add({
		"type": "network",
		"text": "🕸 %s expandoval z %s do %s" % [_network_display_name(faction), from_name, to_name]
	})

func _handler_network_suppress(actor: AIActor, action_def: Dictionary) -> void:
	var faction: Faction = game_state.faction_manager.get_faction(actor.faction_id)
	if faction == null:
		return
	var effects: Dictionary = action_def.get("effects", {})
	var rival_delta: int = int(effects.get("rival_influence", 0))

	# Najdi rivala s nejvyšší influence v regionu kde je tato frakce přítomna
	var best_rival: Faction = null
	var best_region_id: int = -1
	var best_influence: int = -1

	var checked_regions: Dictionary = {}

	for region_id in faction.influence.keys():
		var regions_to_check: Array = [region_id]
		regions_to_check.append_array(game_state.query.regions.neighbors(region_id))

		for check_id in regions_to_check:
			if checked_regions.has(check_id):
				continue
			checked_regions[check_id] = true

			var rival: Faction = game_state.faction_manager.get_network_faction_in_region(check_id)
			if rival == null or rival.id == actor.faction_id:
				continue
			var rival_inf: int = rival.influence.get(check_id, 0)
			if rival_inf > best_influence:
				best_influence = rival_inf
				best_rival = rival
				best_region_id = check_id

	if best_rival == null:
		actor.last_decision_log["handler_result"] = "suppress: no rival found"
		return

	best_rival.influence[best_region_id] = best_rival.influence.get(best_region_id, 0) + rival_delta
	if best_rival.influence[best_region_id] <= 0:
		best_rival.influence.erase(best_region_id)
		EventBus.network_faction_suppressed.emit(actor.faction_id, best_rival.id, best_region_id)

	faction.visibility = clamp(
		faction.visibility + int(effects.get("visibility", 0)),
		0, Balance.NETWORK_VISIBILITY_MAX
	)

	var region_name: String = _region_name(best_region_id)
	actor.last_decision_log["handler_result"] = "suppress: hit %s in region %d by %d" % [
		best_rival.id, best_region_id, rival_delta
	]
	Log_Manager.add({
		"type": "network",
		"text": "🕸 %s potlačil vliv rivala v %s (%+d)" % [
			_network_display_name(faction), region_name, rival_delta
		]
	})

# ---------------------------------------------------------------------------
# Utility scoring
# ---------------------------------------------------------------------------

# Context sestavuje _process_actor() — tyto funkce jsou čisté
# Vypočítá utility skóre akce. Vrací Dictionary: { score, base, breakdown }.
# breakdown je Array kroků — každý krok zaznamenává stav před/po aplikaci multiplikátoru.
func _calculate_action_score(action_key: String, action_def: Dictionary, context: Dictionary) -> Dictionary:
	var base: float = action_def.get("base_score", 0.0)
	var score: float = base
	var breakdown: Array = []
	for modifier in action_def.get("score_modifiers", []):
		var condition: String = modifier.get("condition", "")
		var multiplier: float = modifier.get("multiplier", 1.0)
		var met: bool = _evaluate_condition(condition, context)
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

	var doctrine: String = context.get("doctrine", "")
	if doctrine != "":
		var doctrine_mods: Dictionary = action_def.get("doctrine_modifiers", {})
		if doctrine_mods.has(doctrine):
			var dmul: float = doctrine_mods[doctrine]
			if dmul != 1.0:
				breakdown.append({
					"condition": "doctrine: %s" % doctrine,
					"met": true,
					"multiplier": dmul,
					"score_before": score,
					"score_after": score * dmul,
				})
				score *= dmul

	return {"score": score, "base": base, "breakdown": breakdown}

# Vyhodnotí condition string formátu "stat op value" (např. "heat > 25").
# Při neplatném formátu vrátí false a zaloguje warning — nikdy nezpůsobí crash.
func _evaluate_condition(condition: String, context: Dictionary) -> bool:
	if condition == "rival_present":
		return bool(context.get("rival_present", false))

	var parts: Array = condition.split(" ")
	if parts.size() != 3:
		push_warning("WorldAI: neplatný formát condition '%s'" % condition)
		return false

	var stat: String = parts[0]
	var op: String = parts[1]
	var target: float = float(parts[2])
	var value: float = _get_stat_value(stat, context)

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

func _get_stat_value(stat: String, context: Dictionary) -> float:
	return float(context.get(stat, 0.0))

# ---------------------------------------------------------------------------
# Helpers pro log a display
# ---------------------------------------------------------------------------

func _network_display_name(faction: Faction) -> String:
	var profile_key: String = faction.network_type + "_network"
	return AIProfiles.ACTORS.get(profile_key, {}).get("display_name", faction.network_type)

func _region_name(region_id: int) -> String:
	var region: Region = game_state.query.regions.get_by_id(region_id)
	return region.name if region != null and region.name != "" else "region %d" % region_id
