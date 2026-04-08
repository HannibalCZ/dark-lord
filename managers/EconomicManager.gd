# scripts/systems/EconomicManager.gd
extends Resource
class_name EconomicManager

var game_state: GameStateSingleton
# ========================================================
# ===============  PUBLIC ENTRY POINT  ===================
# ========================================================

func compute_income_and_upkeep(faction_id: String) -> Dictionary:
	var fac := game_state.faction_manager.get_faction(faction_id)
	if fac == null:
		return {"ok": false, "error": "Unknown faction"}

	var gold_income := 0.0
	var mana_income := 0.0
	var research_income := 0.0

	# REGION INCOME
	for region in game_state.region_manager.regions:
		var inc := _compute_region_income_for_faction(region, faction_id)
		gold_income += float(inc.get("gold_income", 0.0))
		mana_income += float(inc.get("mana_income", 0.0))
		research_income += float(inc.get("research_income", 0.0))

	# Progression modifier — gold_per_region (TYP A)
	# fac je již v scope (viz začátek funkce), null check pro jistotu
	if fac != null:
		var owned_count: int = 0
		for region in game_state.region_manager.regions:
			if region.owner_faction_id == faction_id:
				owned_count += 1
		gold_income += fac.modifiers.get("gold_per_region", 0.0) * owned_count

	# Progression modifier — mana_income (TYP A)
	if fac != null:
		mana_income += fac.modifiers.get("mana_income", 0.0)

	# UNIT UPKEEP
	var gold_upkeep := 0.0
	var mana_upkeep := 0.0

	for u in game_state.query.units.by_faction.get(faction_id, []):
		if u.state != "lost":
			var cfg : Dictionary = Balance.UNIT.get(u.unit_key, {})
			var upkeep : Dictionary = cfg.get("upkeep_cost", {})
			gold_upkeep += float(upkeep.get("gold", 0))
			mana_upkeep += float(upkeep.get("mana", 0))

	# ORG PASSIVE INCOME
	for org in game_state.org_manager.orgs:
		if org["owner"] != faction_id:
			continue
		var org_effects: Dictionary = Balance.get_org_effects(org["org_type"], org["doctrine"])
		gold_income += float(org_effects.get("gold", 0))
		mana_income += float(org_effects.get("mana", 0))

	# NET VALUES
	var net_gold := gold_income - gold_upkeep
	var net_mana := mana_income - mana_upkeep

	return {
		"ok": true,
		"gold_income": gold_income,
		"mana_income": mana_income,
		"research_income": research_income,
		"gold_upkeep": gold_upkeep,
		"mana_upkeep": mana_upkeep,
		"net_gold": net_gold,
		"net_mana": net_mana
	}

func _compute_region_income_for_faction(region: Region, faction_id: String) -> Dictionary:
	var gold: float = 0.0
	var mana: float = 0.0
	var research: float = 0.0

	# 1) Základní income regionu (už zohledněný tagy atd.)
	# Uprav si podle toho, jak to máš pojmenované – point je mít "efektivní" hodnoty.
	var region_incomes: Dictionary = region.get_income()
	var base_gold: float = region_incomes["gold"]
	var base_mana: float = region_incomes["mana"]
	var base_research: float = region_incomes["research"]

	# 2) Hráčovy korupční fáze v regionu
	var faction_phase_def: Dictionary = region.get_corruption_phase_def_for(faction_id)
	var owner_income_mult: float = float(faction_phase_def.get("owner_income_mult", 1.0))
	var controller_income_mult: float = float(faction_phase_def.get("controller_income_mult", 0))

	# 3) PŘÍJEM PRO TUTO FRAKCI

	# a) Pokud je tahle frakce ownerem regionu
	if region.owner_faction_id == faction_id:
		gold += base_gold * owner_income_mult
		mana += base_mana * owner_income_mult
		research += base_research * owner_income_mult

	# b) Pokud je tahle frakce hráč (koruptor) a region není jeho
	if  region.controller_faction_id == faction_id and region.controller_faction_id != region.owner_faction_id:
		# hráč dostává podíl podle controller_income_mult
		gold += base_gold * controller_income_mult
		mana += base_mana * controller_income_mult
		research += base_research * controller_income_mult

	# c) Ostatní frakce, které nejsou owner ani hráč → zatím nic
	# (až později přidáme jejich vlastní korupci / mechaniky)

	return {
		"gold_income": gold,
		"mana_income": mana,
		"research_income": research
	}

func apply_economy_cycle() -> Array[Dictionary]:
	var logs: Array[Dictionary] = []

	for faction in game_state.faction_manager.all():
		var r := compute_income_and_upkeep(faction.id)
		if not r.ok:
			continue

		# aplikace změn přes EffectsSystem
		var effects: Dictionary = {}
		if r.net_gold != 0:
			effects["gold"] = r.net_gold
		if r.net_mana != 0:
			effects["mana"] = r.net_mana
		if r.research_income != 0:
			effects["research"] = r.research_income
		if not effects.is_empty():
			var ctx := EffectContext.make(game_state, null, faction.id)
			game_state.effects_system.apply(effects, ctx)

		# log
		logs.append({
			"type": "economy",
			"text": "%s: +%d gold, +%d mana, +%d research (upkeep: -%d gold, -%d mana)" % [
				faction.name,
				int(r.gold_income),
				int(r.mana_income),
				int(r.research_income),
				int(r.gold_upkeep),
				int(r.mana_upkeep)
			]
		})

	_apply_corruption_awareness()

	return logs

func _apply_corruption_awareness() -> void:
	for region in game_state.region_manager.regions:
		if region == null:
			continue
		var phase: int = region.get_corruption_phase_for(Balance.PLAYER_FACTION)
		if phase < Balance.AWARENESS_CORRUPTION_PHASE_MIN:
			continue
		var delta: int = Balance.AWARENESS_CORRUPTION_PH3
		if phase >= 4:
			delta = Balance.AWARENESS_CORRUPTION_PH4
		var ctx := EffectContext.make(game_state, null, Balance.PLAYER_FACTION)
		game_state.effects_system.apply({"awareness": delta}, ctx)

func _tick_all_region_tags(regions: Array) -> void:
	for region in regions:
		region.tick_tags()
		
