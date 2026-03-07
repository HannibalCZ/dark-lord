# scripts/core/MissionManager.gd
extends Node
class_name MissionManager

signal missions_changed
signal mission_resolved(result: Dictionary)

var game_state: GameStateSingleton
var planned_missions: Array[Mission] = []
var planned_ai_missions : Array[Mission] = []

func init() -> void:
	planned_missions.clear()

func plan_mission(unit: Unit, region: Region, mission_key:String) -> void:
	var cfg: Dictionary = Balance.MISSION.get(mission_key, {})
	if cfg.is_empty():
		game_state._log({"text":"⚠ Neznámá mise: %s" % mission_key, "type":"warn"})
		emit_signal("missions_changed")
		return
		
	if not unit.is_available():
		game_state._log({"text": "⚠ Jednotka je zaneprázdněná.", "type": "warn"})
		emit_signal("missions_changed")
		return

	if not unit.can_do_mission(mission_key):
		game_state._log({"text":"⚠ Tento typ jednotky nemůže provádět tuto misi.","type":"warn"})
		emit_signal("missions_changed")
		return

	if not can_do_mission(unit, region, mission_key):
		game_state._log({"text":"⚠ Tuto misi nelze provést v tomto regionu.","type":"warn"})
		emit_signal("missions_changed")
		return

	var mission := Mission.new(unit, region, mission_key)
	planned_missions.append(mission)
	unit.state = "busy"
	emit_signal("missions_changed")
	
	EventBus.emit_signal("mission_planned", mission)

func cancel_mission(index: int) -> void:
	if index < 0 or index >= planned_missions.size():
		return
		
	var m: Mission = planned_missions[index]
	planned_missions.remove_at(index)
	
	# Uvolni jednotku, pokud existuje
	if m != null and m.unit != null:
		var still_busy := false
		for other: Mission in planned_missions:
			if other != null and other.unit == m.unit:
				still_busy = true
				break
		if not still_busy:
			m.unit.state = "healthy"	
	
	emit_signal("missions_changed")
		

func assign_ai_actions(units: Array[Unit], region_manager: RegionManager) -> void:
	# AI naplánuje mise do planned_ai_missions
	planned_ai_missions.clear()

	for u: Unit in units:
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

		var target_id: int = _ai_pick_target_region(u, prof, region_manager)
		if target_id == -1:
			continue

		# 1) move towards target up to moves_left steps
		_ai_move_towards(u, target_id, region_manager)

		# 2) if in target -> do mission (or wait)
		if u.region_id == target_id:
			_ai_execute_plan(u, target_id, prof, region_manager)

func _ai_pick_target_region(u: Unit, prof: Dictionary, region_manager: RegionManager) -> int:
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

func _ai_move_towards(u: Unit, target_id: int, region_manager: RegionManager) -> void:
	while u.moves_left > 0 and u.region_id != target_id:
		var next_step: int = game_state.query.regions.find_next_step_towards(u.region_id, target_id)
		if next_step == -1 or next_step == u.region_id:
			return

		game_state.move_unit(u.id, next_step)

func _ai_execute_plan(u: Unit, target_id: int, prof: Dictionary, region_manager: RegionManager) -> void:
	var plan: Array = prof.get("plan", [])
	if plan.is_empty():
		return

	var step: Dictionary = plan[0]
	var mission_key: String = String(step.get("mission_key", "_none"))

	# wait / none
	if mission_key == "_none" or mission_key == "wait":
		# volitelně naplánovat "wait" misi jen pro log/telemetrii,
		# ale MVP: nedělá nic
		return

	var region: Region = game_state.query.regions.get_by_id(target_id)
	if region == null:
		return

	if not can_do_mission(u, region, mission_key):
		return

	plan_ai_mission(u, region, mission_key)

func _compute_mission_success(mission_key: String, unit: Unit, region: Region) -> Dictionary:
	# 1) base chance z dat
	var cfg: Dictionary = Balance.MISSION.get(mission_key, {})
	if cfg.is_empty():
		return {
			"chance": 0.5,
			"base": 0.5,
			"region_delta": 0.0,
			"unit_delta": 0.0
		}

	var base: float = float(cfg.get("base_chance", 0.5))

	var region_delta: float = 0.0
	var unit_delta: float = 0.0

	# 2) projít všechny jednotky v regionu a aplikovat jejich aury
	for u in game_state.query.units.in_region(region.id, false):
		if u.state == "lost":
			continue
		if u.region_id != region.id:
			continue

		var u_cfg: Dictionary = Balance.UNIT.get(u.unit_key, {})
		if u_cfg.is_empty():
			continue
		if not u_cfg.has("aura"):
			continue

		var aura: Dictionary = u_cfg["aura"]

		# a) restrikce na typ mise
		if aura.has("mission_key"):
			var keys: Array = aura["mission_key"]
			if mission_key not in keys:
				continue

		# b) restrikce na allies/enemies/all
		var affects: String = String(aura.get("affects", "all"))
		var is_enemy: bool = (u.faction_id != unit.faction_id)
		var is_ally: bool = (u.faction_id == unit.faction_id)

		if affects == "enemies" and not is_enemy:
			continue
		if affects == "allies" and not is_ally:
			continue
		# "all" → bez filtru

		# c) samotná změna šance
		var delta: float = float(aura.get("mission_success", 0.0))

		# kdybychom chtěli self-buffy, můžeme rozlišit u == unit
		if u == unit:
			unit_delta += delta
		else:
			region_delta += delta

	# 3) spočítat výslednou šanci
	var total_chance: float = base + region_delta + unit_delta
	total_chance = clamp(total_chance, 0.05, 0.95)

	return {
		"chance": total_chance,
		"base": base,
		"region_delta": region_delta,
		"unit_delta": unit_delta
	}

func get_mission_success_chance(mission_key: String, unit: Unit, region: Region) -> float:
	var info := _compute_mission_success(mission_key, unit, region)
	return float(info.get("chance", 0.5))
	
func get_mission_success_info(mission_key: String, unit: Unit, region: Region) -> Dictionary:
	# UI / debug používá tohle
	return _compute_mission_success(mission_key, unit, region)

func plan_ai_mission(unit: Unit, region: Region, mission_key: String) -> void:
	if not unit.is_available():
		return

	var mission := Mission.new(unit, region, mission_key)
	planned_ai_missions.append(mission)
	unit.state = "busy"

	# eventy pro UI animace můžeš nechat, ale typicky AI nechceš animovat stejně
	EventBus.emit_signal("mission_planned", mission)

func _resolve_single_mission(mission: Mission) -> Dictionary:
	var unit := mission.unit
	var region := mission.region
	var key := mission.mission_key

	if unit == null or region == null:
		return {
			"ok": false,
			"type": "mission_error",
			"text": "Mise není validní (unit/region null)."
		}

	# 1) Získej šanci
	var success_chance: float = get_mission_success_chance(key, unit, region)

	# 2) Roll
	var roll := game_state.rng.randf()
	var success := (roll < success_chance)

	# 3) Najdi config
	var cfg: Dictionary = Balance.MISSION.get(key, {})

	# 4) Aplikuj efekty
	if success:
		var effects: Dictionary = cfg.get("success", {})
		var ctx := EffectContext.make(game_state, region, unit.faction_id)
		var eff_logs : Array[Dictionary] = game_state.effects_system.apply(effects, ctx)
		#game_state._apply_effects(effects, region, unit.faction_id)

		# jednotka je zaneprázdněná pouze během plánování
		unit.state = "healthy"

		return {
			"ok": true,
			"type": "mission_success",
			"text": "ÚSPĚCH mise %s v %s (%d%%)" % [
				key, region.name, int(success_chance * 100)
			],
			"mission_key": key,
			"unit_id": unit.id,
			"region_id": region.id,
			"success": true,
			"effect_logs": eff_logs
		}
	else:
		var effects: Dictionary = cfg.get("fail", {})
		var ctx := EffectContext.make(game_state, region, unit.faction_id)
		var eff_logs : Array[Dictionary] = game_state.effects_system.apply(effects, ctx)
		#game_state._apply_effects(effects, region, unit.faction_id)

		# jednotka je ztracená
		unit.state = "lost"

		return {
			"ok": false,
			"type": "mission_fail",
			"text": "NEÚSPĚCH mise %s v %s (%d%%)" % [
				key, region.name, int(success_chance * 100)
			],
			"mission_key": key,
			"unit_id": unit.id,
			"region_id": region.id,
			"success": false,
			"effect_logs": eff_logs
		}

func resolve_all() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	# PLAYER
	for m in planned_missions:
		var result: Dictionary = _resolve_single_mission(m)
		entries.append(result)
		EventBus.mission_resolved.emit(result)

	# AI (skutečné resolve, ne placeholder)
	for m in planned_ai_missions:
		var result: Dictionary = _resolve_single_mission(m)
		entries.append(result)
		EventBus.mission_resolved.emit(result)

	planned_missions.clear()
	planned_ai_missions.clear()
	emit_signal("missions_changed")

	return entries
	
func can_do_mission(unit, region:Region, mission_key:String) -> bool:
	var cfg: Dictionary = Balance.MISSION.get(mission_key, {})
	var req: Dictionary = cfg.get("requirements", {})
	return _check_requirements(req, unit, region)

func _check_requirements(req:Dictionary, unit:Unit, region:Region) -> bool:
	if req.is_empty():
		return true

	if req.has("region_kind_in"):
		var allowed:Array = req["region_kind_in"]
		if not (region.region_kind in allowed):
			return false

	if req.get("requires_secret", false):
		if not region.has_secret():
			return false

	if req.get("secret_known", false):
		if not region.secret_known:
			return false

	if req.has("secret_state_not_in"):
		var bad:Array = req["secret_state_not_in"]
		if region.secret_state in bad:
			return false

	if req.get("requires_lair", false):
		if not region.has_lair():
			return false

	return true

func get_available_missions_for(unit:Unit, region:Region) -> Array[String]:
	var result: Array[String] = []
	for key in Balance.MISSION.keys():
		if not unit.can_do_mission(key):
			continue
		if can_do_mission(unit, region, key):
			result.append(key)
	return result
