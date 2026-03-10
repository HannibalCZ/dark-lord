extends Node
class_name AIManager

var game_state: GameStateSingleton

func execute_ai_turn() -> void:
	game_state.mission_manager.planned_ai_missions.clear()

	for u: Unit in game_state.unit_manager.units:
		if u.faction_id == Balance.PLAYER_FACTION:
			continue
		if u.state != "healthy":
			continue

		var u_cfg: Dictionary = Balance.UNIT.get(u.unit_key, {})
		if u_cfg.is_empty():
			continue

		var prof: Dictionary = u_cfg.get("ai_profile", {})
		if prof.is_empty():
			continue

		var target_id: int = _ai_pick_target_region(u, prof)
		if target_id == -1:
			continue

		_ai_move_towards(u, target_id)

		if u.region_id == target_id:
			_ai_execute_plan(u, target_id, prof)

func _ai_pick_target_region(u: Unit, prof: Dictionary) -> int:
	var target_def: Dictionary = prof.get("target", {})
	if target_def.is_empty():
		return -1
	if String(target_def.get("type", "")) != "region":
		return -1
	var select: String = String(target_def.get("select", "nearest"))
	if select != "nearest":
		# MVP: jen nearest
		return -1
	var filters: Dictionary = target_def.get("filters", {})
	return game_state.query.regions.find_nearest_with_filters(u.region_id, u.faction_id, filters)

func _ai_move_towards(u: Unit, target_id: int) -> void:
	while u.moves_left > 0 and u.region_id != target_id:
		var next_step: int = game_state.query.regions.find_next_step_towards(u.region_id, target_id)
		if next_step == -1 or next_step == u.region_id:
			return
		game_state.move_unit(u.id, next_step)

func _ai_execute_plan(u: Unit, target_id: int, prof: Dictionary) -> void:
	var plan: Array = prof.get("plan", [])
	if plan.is_empty():
		return
	var step: Dictionary = plan[0]
	var mission_key: String = String(step.get("mission_key", "_none"))
	if mission_key == "_none" or mission_key == "wait":
		return
	var region: Region = game_state.query.regions.get_by_id(target_id)
	if region == null:
		return
	if not game_state.mission_manager.can_do_mission(u, region, mission_key):
		return
	game_state.mission_manager.plan_ai_mission(u, region, mission_key)
