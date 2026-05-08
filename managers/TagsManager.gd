extends Resource
class_name TagsManager

var game_state: GameStateSingleton

func process_end_of_turn() -> void:
	tick_all_tags()
	check_state_tags()
	check_chain_reactions()

func tick_all_tags() -> void:
	for region in game_state.region_manager.regions:
		region.tick_tags()

func check_state_tags() -> void:
	for region in game_state.region_manager.regions:
		_evaluate_state_tags(region)

func _evaluate_state_tags(region: Region) -> void:
	var corruption_phase: int = region.get_corruption_phase_for(Balance.PLAYER_FACTION)
	var fear: int = region.fear

	# unrest: corruption fáze >= min AND fear >= min
	var unrest_cond: bool = corruption_phase >= Balance.UNREST_CORRUPTION_MIN \
		and fear >= Balance.UNREST_FEAR_MIN
	if unrest_cond and not _has_tag(region, "unrest"):
		region.add_tag(Balance.TAGS["unrest"].duplicate())
	elif not unrest_cond and _has_tag(region, "unrest"):
		region.remove_tag("unrest")


func check_chain_reactions() -> void:
	for region in game_state.region_manager.regions:
		if not _has_tag(region, "unrest"):
			continue
		if game_state.rng.randf() < Balance.UNREST_REVOLT_CHANCE:
			var spawn_res := game_state.unit_manager.spawn_unit_free("militia", "militia", region.id)
			for le in spawn_res.get("logs", []):
				game_state._log(le)
			game_state._process_domain_events(spawn_res.get("events", []))
			EventBus.militia_spawned.emit(region.id)

func _has_tag(region: Region, tag_id: String) -> bool:
	for t in region.tags:
		if t.get("id") == tag_id:
			return true
	return false
