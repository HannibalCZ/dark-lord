extends Node
class_name AIManager

var game_state: GameStateSingleton
var turn_movement_log: Array[Dictionary] = []

func execute_ai_turn() -> void:
	turn_movement_log.clear()
	game_state.mission_manager.planned_ai_missions.clear()

	for u: Unit in game_state.unit_manager.units:
		if u.faction_id == Balance.PLAYER_FACTION:
			continue
		if u.state != "healthy":
			continue

		var u_cfg: Dictionary = Balance.UNIT.get(u.unit_key, {})
		if u_cfg.is_empty():
			continue

		var profile_key: String = _pick_profile(u)
		var prof: Dictionary = Balance.AI_PROFILE.get(profile_key, {})
		if prof.is_empty():
			continue

		var target_id: int = _ai_pick_target_region(u, prof)
		if target_id == -1:
			continue

		# Pohyb — jen pokud move_towards_target == true A není na cíli
		if prof.get("move_towards_target", false) and u.region_id != target_id:
			_ai_move_towards(u, target_id)

		# Akce — jen pokud je na cíli
		if u.region_id == target_id:
			_ai_execute_action(u, target_id, prof)

# Výběr profilu pro jednotku.
# Priorita: unit-level override ("ai_profile" v Balance.UNIT) >
#           speciální typy (inquisitor) > faction.current_behavior.
func _pick_profile(u: Unit) -> String:
	# 1) Unit-level override: fixní profil nezávislý na heat a faction behavior
	var u_cfg: Dictionary = Balance.UNIT.get(u.unit_key, {})
	var fixed: String = String(u_cfg.get("ai_profile", ""))
	if not fixed.is_empty():
		return fixed

	# 2) Speciální typy s pevným profilem
	if u.unit_key == "inquisitor":
		if game_state.awareness >= Balance.AWARENESS_INQUISITOR_THRESHOLD:
			return "investigator"        # globální pátrání
		else:
			return "investigator_local"  # pouze vlastní provincie

	# 3) Faction behavior: paladin_army a ostatní bez fixed profile
	var faction: Faction = game_state.faction_manager.get_faction(u.faction_id)
	if faction == null:
		return "defender"

	match faction.current_behavior:
		Faction.Behavior.COORDINATED:
			return "raider"
		Faction.Behavior.AGGRESSIVE:
			return "lair_hunter"
		Faction.Behavior.PATROLLING:
			return "defender"
		_:
			return "defender"

func _ai_pick_target_region(u: Unit, prof: Dictionary) -> int:
	var target_def: Dictionary = prof.get("target", {})
	if target_def.is_empty():
		return -1
	var select: String = String(target_def.get("select", "nearest"))
	var filters: Dictionary = target_def.get("filters", {})
	match select:
		"nearest":
			return game_state.query.regions.find_nearest_with_filters(u.region_id, u.faction_id, filters)
		"highest_corruption":
			return game_state.query.regions.find_highest_corruption_with_filters(u.faction_id, filters)
		_:
			return -1

func _ai_move_towards(u: Unit, target_id: int) -> void:
	while u.moves_left > 0 and u.region_id != target_id:
		var next_step: int = game_state.query.regions.find_next_step_towards(u.region_id, target_id)
		if next_step == -1 or next_step == u.region_id:
			return
		var from_id: int = u.region_id
		game_state.move_unit(u.id, next_step)
		turn_movement_log.append({
			"unit_id": u.id,
			"unit_name": u.name,
			"faction_id": u.faction_id,
			"from_region_id": from_id,
			"to_region_id": next_step
		})

# Spustí misi pokud je jednotka na cílovém regionu a akce projde validací can_do.
# Pokud action_at_target == null, jednotka stojí — boj proběhne implicitně.
func _ai_execute_action(u: Unit, target_id: int, prof: Dictionary) -> void:
	var action: Variant = prof.get("action_at_target", null)
	if action == null or String(action).is_empty():
		return

	var action_key: String = String(action)

	# Validace: akce musí být v can_do jednotky
	var u_cfg: Dictionary = Balance.UNIT.get(u.unit_key, {})
	var can_do: Array = u_cfg.get("can_do", [])
	if action_key not in can_do:
		return

	var region: Region = game_state.query.regions.get_by_id(target_id)
	if region == null:
		return
	if not game_state.mission_manager.can_do_mission(u, region, action_key):
		return
	game_state.mission_manager.plan_ai_mission(u, region, action_key)
