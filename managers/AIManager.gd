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

		# Scout profil má vlastní pohybovou a akční logiku — přeskočí standardní pipeline
		if profile_key == "scout":
			_ai_move_scout(u)
			_check_decoy_on_arrival(u)
			_ai_apply_scout_effects(u)
			continue

		# Inkvizitor má vlastní prioritní systém cílů a akci — přeskočí standardní pipeline
		if u.unit_key == "inquisitor":
			var target_id: int = _find_inquisitor_target(u)
			if target_id == -1:
				_ai_inquisitor_retreat(u)
			else:
				_ai_move_towards(u, target_id)
				_check_decoy_on_arrival(u)
				if u.region_id == target_id:
					_ai_inquisitor_execute_action(u)
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

	# 2) Speciální typy s pevným nebo dynamickým profilem
	if u.unit_key == "inquisitor":
		if game_state.awareness >= Balance.AWARENESS_INQUISITOR_THRESHOLD:
			return "investigator"        # globální pátrání
		else:
			return "investigator_local"  # pouze vlastní provincie

	if u.unit_key == "orc_band":
		var lair_region: Region = _find_lair_region_for_unit(u)
		if lair_region != null and lair_region.lair_control == "player":
			return "lair_raider"   # lair pod hráčovým vlivem → útočí na civilizované regiony
		else:
			return "defender"      # lair je neutral/ai → stojí na místě a brání

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

# --- Scout (průzkumník) pohybová a akční logika ---

# Pohybuje průzkumníkem dokud má moves_left, vždy do nejprioritnějšího souseda.
func _ai_move_scout(u: Unit) -> void:
	while u.moves_left > 0:
		var next_id: int = _scout_pick_next_region(u)
		if next_id == -1 or next_id == u.region_id:
			break
		var from_id: int = u.region_id
		game_state.move_unit(u.id, next_id)
		turn_movement_log.append({
			"unit_id":       u.id,
			"unit_name":     u.name,
			"faction_id":    u.faction_id,
			"from_region_id": from_id,
			"to_region_id":  next_id
		})

# Vybírá sousední region pro průzkumníka podle priorit:
# 0) Soused s decoy tagem (nejvyšší — přebije vše ostatní)
# 1) Soused se skrytým tajemstvím (has_secret() a secret_known == false)
# 2) Nenavštívený "wildlands" soused
# 3) Libovolný nenavštívený soused
# 4) Náhodný soused (všechny navštíveny)
func _scout_pick_next_region(u: Unit) -> int:
	var neighbors: Array[int] = game_state.query.regions.neighbors(u.region_id)
	if neighbors.is_empty():
		return -1

	# Priorita 0: soused s decoy tagem
	var decoy_neighbors: Array[int] = []
	for nb_id: int in neighbors:
		if _region_has_decoy(nb_id):
			decoy_neighbors.append(nb_id)
	if not decoy_neighbors.is_empty():
		return decoy_neighbors[game_state.rng.randi_range(0, decoy_neighbors.size() - 1)]

	# Priorita 1: soused s neodkrytým tajemstvím
	for nb_id: int in neighbors:
		var r: Region = game_state.region_manager.get_region(nb_id)
		if r == null:
			continue
		if r.has_secret() and not r.secret_known:
			return nb_id

	# Priorita 2: nenavštívený wildlands soused
	var unvisited_wild: Array[int] = []
	for nb_id: int in neighbors:
		if nb_id in u.visited_regions:
			continue
		var r: Region = game_state.region_manager.get_region(nb_id)
		if r == null:
			continue
		if r.region_kind == "wildlands":
			unvisited_wild.append(nb_id)
	if not unvisited_wild.is_empty():
		return unvisited_wild[game_state.rng.randi_range(0, unvisited_wild.size() - 1)]

	# Priorita 3: libovolný nenavštívený soused
	var unvisited: Array[int] = []
	for nb_id: int in neighbors:
		if nb_id not in u.visited_regions:
			unvisited.append(nb_id)
	if not unvisited.is_empty():
		return unvisited[game_state.rng.randi_range(0, unvisited.size() - 1)]

	# Priorita 4: náhodný soused (všechny navštíveny)
	return neighbors[game_state.rng.randi_range(0, neighbors.size() - 1)]

# Aplikuje efekty průzkumníka na jeho aktuální region po dokončení pohybu:
# - šance EXPLORER_SECRET_STEAL % na odhalení skrytého tajemství
# - mírný awareness boost (+2) za průzkum civilizovaného regionu
func _ai_apply_scout_effects(u: Unit) -> void:
	var region: Region = game_state.region_manager.get_region(u.region_id)
	if region == null:
		return

	# Tajemství: region má aktivní tajemství, hráč ho dosud nezná
	if region.has_secret() and not region.secret_known:
		var roll: int = game_state.rng.randi_range(1, 100)
		if roll <= Balance.EXPLORER_SECRET_STEAL:
			region.secret_known = true
			EventBus.secret_stolen.emit(region.id, u.id)

	# Awareness: průzkum civilizovaného regionu prozradí Dark Lordovu přítomnost
	if region.region_kind == "civilized":
		var ctx := EffectContext.make(game_state, region, u.faction_id)
		game_state.effects_system.apply({"awareness": 2}, ctx)

# --- Decoy (Stínová návnada) helper funkce ---

# Vrátí true pokud region obsahuje aktivní decoy tag.
# Region.has_tag() neexistuje — iterujeme tags pole přímo.
func _region_has_decoy(region_id: int) -> bool:
	var region: Region = game_state.region_manager.get_region(region_id)
	if region == null:
		return false
	for tag in region.tags:
		if tag.get("id", "") == "decoy":
			return true
	return false

# Zkontroluje zda jednotka dorazila do regionu s decoy tagem.
# Pokud ano — odstraní tag, aplikuje Awareness +2 a emituje decoy_triggered.
# Volat po každém pohybu scouta a inkvizitora.
func _check_decoy_on_arrival(u: Unit) -> void:
	var region: Region = game_state.region_manager.get_region(u.region_id)
	if region == null:
		return
	var has_decoy: bool = false
	for tag in region.tags:
		if tag.get("id", "") == "decoy":
			has_decoy = true
			break
	if not has_decoy:
		return

	# Jednotka dorazila do návnady — odeber tag a aplikuj efekty
	region.remove_tag("decoy")

	var ctx := EffectContext.make(game_state, region, Balance.PLAYER_FACTION)
	ctx.source_label = "Stínová návnada"
	game_state.effects_system.apply({"awareness": 2}, ctx)

	EventBus.decoy_triggered.emit(region.id, u.unit_key)

# --- Inkvizitor — prioritní logika cílů, ústup a akce ---

# Vrátí ID cílového regionu pro inkvizitora podle priorit:
# 0) Region s decoy tagem (nejvyšší — přebije visible org i korupci)
# 1) Region s visible hráčovou organizací (kdekoliv na mapě)
# 2) Elfí region s nejvyšší hráčovou korupcí (fáze > 0)
# 3) Globální region s nejvyšší hráčovou korupcí
# 4) -1 → žádný cíl, inkvizitor se vrátí domů
func _find_inquisitor_target(u: Unit) -> int:
	# Priorita 0: region s decoy tagem kdekoliv na mapě
	for region in game_state.region_manager.regions:
		if _region_has_decoy(region.id):
			return region.id

	# Priorita 1: visible hráčova org kdekoliv na mapě
	for org in game_state.org_manager.orgs:
		if org.get("owner") != Balance.ORG_OWNER_PLAYER:
			continue
		if not org.get("visible", false):
			continue
		if org.get("is_rogue", false):
			continue
		return int(org["region_id"])

	# Priorita 2: elfí region s nejvyšší hráčovou korupcí
	var elf_regions: Array[Region] = game_state.region_manager.get_regions_by_faction("elf")
	var best_elf_id: int = -1
	var best_elf_corruption: int = -1
	for region in elf_regions:
		var corruption: int = region.get_corruption_phase_for(Balance.PLAYER_FACTION)
		if corruption > best_elf_corruption:
			best_elf_corruption = corruption
			best_elf_id = region.id
	if best_elf_id != -1 and best_elf_corruption > 0:
		return best_elf_id

	# Priorita 3: globální region s nejvyšší hráčovou korupcí
	var global_target: int = game_state.query.regions.find_highest_corruption_with_filters(
		u.faction_id, {})
	if global_target != -1:
		return global_target

	# Žádný cíl
	return -1

# Vrátí inkvizitora do nejbližšího elfího regionu pokud nemá žádný cíl.
# Signal inquisitor_returned se emituje pouze když inkvizitor skutečně dorazí.
func _ai_inquisitor_retreat(u: Unit) -> void:
	var elf_regions: Array[Region] = game_state.region_manager.get_regions_by_faction("elf")
	if elf_regions.is_empty():
		return

	# Najdi nejbližší elfí region podle BFS vzdálenosti
	var nearest_id: int = -1
	var min_dist: int = 999
	for region in elf_regions:
		var dist: int = game_state._bfs_distance(u.region_id, region.id)
		if dist < min_dist:
			min_dist = dist
			nearest_id = region.id

	if nearest_id == -1:
		return

	# Pohyb směrem domů (přes existující _ai_move_towards)
	_ai_move_towards(u, nearest_id)

	# Event pouze pokud inkvizitor skutečně dorazil do elfího regionu
	if u.region_id == nearest_id:
		EventBus.inquisitor_returned.emit(u.id)

# Provede akci inkvizitora na jeho aktuálním regionu:
# - dismantle má přednost pokud je v regionu visible hráčova org
# - fallback na purge (čištění korupce)
func _ai_inquisitor_execute_action(u: Unit) -> void:
	var region: Region = game_state.region_manager.get_region(u.region_id)
	if region == null:
		return

	# Preferuj dismantle pokud je v regionu visible hráčova org (ne rogue)
	var org: Dictionary = game_state.org_manager.get_org_in_region(u.region_id)
	if not org.is_empty() \
			and org.get("visible", false) \
			and org.get("owner") == Balance.ORG_OWNER_PLAYER \
			and not org.get("is_rogue", false):
		if game_state.mission_manager.can_do_mission(u, region, "dismantle"):
			game_state.mission_manager.plan_ai_mission(u, region, "dismantle")
			return

	# Fallback: purge korupce
	if game_state.mission_manager.can_do_mission(u, region, "purge"):
		game_state.mission_manager.plan_ai_mission(u, region, "purge")

# Najde region s lairem jehož faction_id odpovídá frakci jednotky.
# Vrátí první takový region nebo null — používá se pro určení stavu lairu orc_band.
func _find_lair_region_for_unit(u: Unit) -> Region:
	for region in game_state.region_manager.regions:
		if not region.has_lair():
			continue
		var lair_conf: Dictionary = Balance.LAIR.get(region.lair_id, {})
		if lair_conf.is_empty():
			continue
		if String(lair_conf.get("faction_id", "")) == u.faction_id:
			return region
	return null
