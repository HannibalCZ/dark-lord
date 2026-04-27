extends Resource
class_name LairManager

var game_state: GameStateSingleton

# Hlavní entry point — volat z GameState.advance_turn() sekce C.
# Pořadí: check → decay → spawn.
# Check musí předcházet spawnu — nespawnujeme do lairu který právě ztratil kontrolu.
func process_end_of_turn() -> void:
	check_all_control()
	process_decay()
	process_spawns()

# Projde všechny regiony s lairem a zkontroluje stav kontroly na základě aktuálního vlivu.
# Zachytí gain/loss kontroly z misí a dark actions provedených v tomto tahu.
func check_all_control() -> void:
	for region in game_state.query.regions.get_regions_with_lair():
		_check_control(region)

# Aplikuje přirozený útlum vlivu ve všech hráčem kontrolovaných lairech.
# Po každém decay znovu zkontroluje kontrolu — lair může být okamžitě ztracen.
func process_decay() -> void:
	for region in game_state.query.regions.get_regions_with_lair():
		if region.lair_control != Balance.PLAYER_FACTION:
			continue
		region.add_influence(-Balance.LAIR_INFLUENCE_DECAY)
		_check_control(region)

# Zpracuje spawn jednotek ze všech lairů podle Balance.LAIR konfigurace.
func process_spawns() -> void:
	for region in game_state.query.regions.get_regions_with_lair():
		var lair_conf: Dictionary = Balance.LAIR.get(region.lair_id, {})
		if lair_conf.is_empty():
			continue

		var spawn_unit_id: String = lair_conf.get("spawn_unit", "")
		if spawn_unit_id == "":
			continue

		var max_units: int = int(lair_conf.get("max_units", 0))
		if max_units <= 0:
			continue

		var lair_faction_id: String = String(lair_conf.get("faction_id", "neutral"))
		var count_alive: int = game_state.query.units.active_count_for_faction(lair_faction_id)
		if count_alive >= max_units:
			continue

		var spawn_rate: int = int(lair_conf.get("spawn_rate", 1))
		region.lair_spawn_counter += 1
		if region.lair_spawn_counter < spawn_rate:
			continue
		region.lair_spawn_counter = 0

		var spawn_res := game_state.unit_manager.spawn_unit_free(lair_faction_id, spawn_unit_id, region.id)
		for le in spawn_res.get("logs", []):
			game_state._log(le)
		game_state._process_domain_events(spawn_res.get("events", []))
		EventBus.lair_unit_spawned.emit(region.id, lair_faction_id, spawn_unit_id)

# Vrátí první region s lairem jehož faction_id v Balance.LAIR odpovídá faction_id.
# Používá AIManager pro určení stavu lairu orc_band a podobných jednotek.
func get_lair_region_for_faction(faction_id: String) -> Region:
	for region in game_state.query.regions.get_regions_with_lair():
		var lair_conf: Dictionary = Balance.LAIR.get(region.lair_id, {})
		if lair_conf.is_empty():
			continue
		if String(lair_conf.get("faction_id", "")) == faction_id:
			return region
	return null

# Přidá raid tag do regionu. Volá AIManager po naplánování mise pro lair_raider_active profil.
func apply_raid_tag(region_id: int) -> void:
	var region: Region = game_state.region_manager.get_region(region_id)
	if region == null:
		return
	region.add_tag(Balance.TAGS["raid"].duplicate())

# -----------------------
# Interní helpers
# -----------------------

func _check_control(region: Region) -> void:
	if not region.has_lair():
		return

	if region.lair_influence >= Balance.LAIR_INFLUENCE_CONTROL_THRESHOLD \
			and region.lair_control != Balance.PLAYER_FACTION:
		region.lair_control = Balance.PLAYER_FACTION
		game_state._log({"type": "lair", "text": "🕳️ Doupě v regionu %s přešlo pod vliv Temného pána." % str(region.id)})
		EventBus.lair_control_changed.emit(region.id, Balance.PLAYER_FACTION)

	elif region.lair_influence <= Balance.LAIR_INFLUENCE_LOSS_THRESHOLD \
			and region.lair_control == Balance.PLAYER_FACTION:
		region.lair_control = "neutral"
		game_state._log({"type": "lair", "text": "🕳️ Vliv nad doupětem v regionu %s byl ztracen." % str(region.id)})
		EventBus.lair_control_changed.emit(region.id, "neutral")
