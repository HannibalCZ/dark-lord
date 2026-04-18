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

	# 3) mission_bonus ze Shadow Network doktríny "informants"
	var org: Dictionary = game_state.org_manager.get_org_in_region(region.id)
	if not org.is_empty():
		if org["org_type"] == "shadow_network":
			var effects: Dictionary = Balance.get_org_effects(org["org_type"], org["doctrine"])
			if effects.has("mission_bonus"):
				region_delta += float(effects["mission_bonus"]) / 100.0

	# mission_penalty z neutralnich/Rogue organizaci v regionu
	# Penalizuje hrace za mise v regionu kde operuje cizi organizace.
	if not org.is_empty():
		if org.get("owner") != Balance.PLAYER_FACTION:
			var neutral_fx: Dictionary = Balance.ORG_NEUTRAL_EFFECTS.get(org["org_type"], {})
			if neutral_fx.has("mission_penalty"):
				region_delta -= float(neutral_fx["mission_penalty"])

	# Progression modifier — mission_success (TYP A)
	# Aplikuje se pouze pro hráčovy mise — konzistentní s mission_bonus ze Shadow Network
	var player_faction = game_state.faction_manager.get_faction(Balance.PLAYER_FACTION)
	if player_faction != null and unit.faction_id == Balance.PLAYER_FACTION:
		region_delta += player_faction.modifiers.get("mission_success", 0.0)

	# 4) spočítat výslednou šanci
	var total_chance: float = base + region_delta + unit_delta
	total_chance = clamp(total_chance, Balance.MISSION_CHANCE_MIN, Balance.MISSION_CHANCE_MAX)

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

		# org_loyalty neni znamy EffectsSystem — zpracuj primo pres OrgManager
		var loyalty_boost: int = effects.get("org_loyalty", 0)
		if loyalty_boost != 0:
			game_state.org_manager.boost_org_loyalty(region.id, loyalty_boost)

		# destroy_org neni znamy EffectsSystem — zpracuj primo pres OrgManager
		if effects.get("destroy_org", false):
			var target_org: Dictionary = game_state.org_manager.get_org_in_region(region.id)
			if not target_org.is_empty():
				game_state.org_manager.remove_org(region.id)

		# kill_unit — zpracuj mimo EffectsSystem: zabij první nepřátelskou jednotku v regionu
		if effects.get("kill_unit", false):
			var enemies: Array[Unit] = game_state.query.units.enemies_in_region(region.id, unit.faction_id)
			for target in enemies:
				var killed_key: String = target.unit_key
				var killed_id: int = target.id
				game_state.unit_manager.kill_unit(target.id)
				EventBus.unit_killed.emit(killed_id, killed_key, region.id)
				break  # zabij pouze první nepřátelskou jednotku per mise

		# odstan org_loyalty, destroy_org a kill_unit pred predanim EffectsSystem
		var effects_for_system: Dictionary = effects.duplicate()
		effects_for_system.erase("org_loyalty")
		effects_for_system.erase("destroy_org")
		effects_for_system.erase("kill_unit")

		var ctx := EffectContext.make(game_state, region, unit.faction_id)
		ctx.source_label = "Mise: %s (úspěch)" % key
		var eff_logs : Array[Dictionary] = game_state.effects_system.apply(effects_for_system, ctx)
		#game_state._apply_effects(effects, region, unit.faction_id)

		# purge znicí organizaci v regionu pokud existuje
		if key == "purge":
			_handle_purge_org(region.id)

		# jednotka je zaneprázdněná pouze během plánování
		unit.state = "healthy"

		if unit.faction_id == Balance.PLAYER_FACTION:
			var global_fx: Dictionary = Balance.MISSION_GLOBAL_SUCCESS_EFFECTS
			if not global_fx.is_empty():
				var gctx := EffectContext.make(game_state, null, Balance.PLAYER_FACTION)
				gctx.source_label = "Mise: %s (úspěch)" % key
				game_state.effects_system.apply(global_fx, gctx)

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
		ctx.source_label = "Mise: %s (selhání)" % key
		var eff_logs : Array[Dictionary] = game_state.effects_system.apply(effects, ctx)
		#game_state._apply_effects(effects, region, unit.faction_id)

		# jednotka je ztracená
		game_state.unit_manager.kill_unit(unit.id)

		if unit.faction_id == Balance.PLAYER_FACTION:
			var global_fx: Dictionary = Balance.MISSION_GLOBAL_FAIL_EFFECTS
			if not global_fx.is_empty():
				var gctx := EffectContext.make(game_state, null, Balance.PLAYER_FACTION)
				gctx.source_label = "Mise: %s (selhání)" % key
				game_state.effects_system.apply(global_fx, gctx)

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

	if req.get("requires_org", false):
		var org: Dictionary = game_state.org_manager.get_org_in_region(region.id)
		if org.is_empty():
			return false
		if org.get("owner", "") != Balance.PLAYER_FACTION:
			return false
		if org.get("is_rogue", false):
			return false

	if req.get("requires_enemy_unit", false):
		var enemies: Array[Unit] = game_state.query.units.enemies_in_region(region.id, unit.faction_id)
		if enemies.is_empty():
			return false

	return true

# -------------------------------------------------
# Purge — znici organizaci v regionu pokud existuje
func _handle_purge_org(region_id: int) -> void:
	var org: Dictionary = game_state.org_manager.get_org_in_region(region_id)
	if org.is_empty():
		return
	var org_type: String  = String(org.get("org_type", "?"))
	var org_owner: String = String(org.get("owner", "?"))
	game_state._log({
		"type": "mission_success",
		"text": "Purge: organizace typu '%s' (owner: %s) v regionu %d byla odhalena a znicena." % [
			org_type, org_owner, region_id
		]
	})
	game_state.org_manager.remove_org(region_id)


func get_available_missions_for(unit:Unit, region:Region) -> Array[String]:
	var result: Array[String] = []
	for key in Balance.MISSION.keys():
		if not unit.can_do_mission(key):
			continue
		if can_do_mission(unit, region, key):
			result.append(key)
	return result
