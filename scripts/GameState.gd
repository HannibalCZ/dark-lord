extends Node
class_name GameStateSingleton

signal game_updated # cokoliv se změnilo (mise, pohyb, zdroje…) → UI refresh
signal turn_resolved # konec tahu (vyhodnocené mise, ekonomika, AI) → velké změny
signal unit_moved(unit_id, from_region, to_region) # jemný event pro animace
signal game_ended(result: Dictionary) # { ok:bool, outcome:"win"/"lose", reason:String }

@onready var unit_manager: UnitManager = UnitManager.new()
@onready var region_manager: RegionManager = RegionManager.new()
@onready var mission_manager: MissionManager = MissionManager.new()
@onready var building_manager : BuildingManager = BuildingManager.new()
@onready var spell_manager    : SpellManager    = SpellManager.new()
@onready var combat_manager    : CombatManager    = CombatManager.new()
@onready var economic_manager    : EconomicManager    = EconomicManager.new()
@onready var faction_manager    : FactionManager    = FactionManager.new()
@onready var dark_actions_manager    : DarkActionsManager    = DarkActionsManager.new()
@onready var effects_system: EffectsSystem = EffectsSystem.new()
@onready var ai_manager: AIManager = AIManager.new()

var rng := RandomNumberGenerator.new()
var turn:int = 1
var heat: int = 0
var old_heat: int = 0
var heat_stage:int = 0  # 0..4 podle toho, jaký threshold už byl dosažen
var doom:int = 0
var doom_income:int = 0
var game_over: bool = false
var game_over_result: Dictionary = {}
var query: GameQuery
var commands: GameCommands

const DEFAULT_SCENARIO_PATH := "res://data/scenarios/mvp_scenario.json"

# ---------------------------
func _ready() -> void:
	unit_manager.game_state     = self
	region_manager.game_state   = self
	spell_manager.game_state    = self
	combat_manager.game_state    = self
	faction_manager.game_state    = self
	dark_actions_manager.game_state    = self
	mission_manager.game_state    = self
	economic_manager.game_state    = self
	building_manager.game_state    = self
	ai_manager.game_state          = self


	query = GameQuery.new(self)
	query.rebuild_indexes()
	commands = GameCommands.new(self)
	
	unit_manager.setup(region_manager, faction_manager)
	# případné navázání signálů (UI naslouchá přes GameState)
	spell_manager.magic_used.connect(func(): emit_signal("game_updated"))
	building_manager.buildings_changed.connect(func(): emit_signal("game_updated"))
	
	rng.randomize()
	init_data()

# ---------------------------
func init_data() -> void:
	load_scenario(DEFAULT_SCENARIO_PATH)	
	emit_signal("game_updated")

func load_scenario(path: String) -> void:
	# 0) parse JSON
	if not FileAccess.file_exists(path):
		push_error("Scenario JSON not found: %s" % path)
		return

	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid scenario JSON: %s" % path)
		return

	var data: Dictionary = parsed

	# 1) RESET managers that are scenario-driven
	game_over = false
	game_over_result = {}
	old_heat = heat
	
	unit_manager.init_empty()
	faction_manager.init_empty()
	mission_manager.init()

	# (budovy/spells jsou zatím "game rules", ne scénář – nechávám init)
	building_manager.init_buildings()
	spell_manager.init_spells()

	# 2) Load map (přes RegionManager API, které už máš)
	var meta: Dictionary = data.get("meta", {})
	var map_path: String = String(meta.get("map_path", ""))
	if map_path == "":
		push_warning("Scenario missing meta.map_path; falling back to RegionManager.init_regions().")
		region_manager.init_regions()
	else:
		region_manager.init_regions_from_map(map_path)

	# 3) Globals
	var g: Dictionary = data.get("globals", {})
	turn = int(g.get("turn", 1))
	heat = int(g.get("heat", 0))
	old_heat = heat
	heat_stage = int(g.get("heat_stage", 0))
	doom = int(g.get("doom", 0))
	doom_income = int(g.get("doom_income", 0))

	# 4) Factions
	var player_unit_limit_from_scenario: int = -1

	var factions_arr: Array = data.get("factions", [])
	for item in factions_arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var fd: Dictionary = item

		var fid: String = String(fd.get("id", ""))
		if fid == "":
			push_warning("Skipping faction without id: %s" % str(fd))
			continue

		var fac := Faction.new()
		fac.id = fid
		fac.name = String(fd.get("name", fid))
		fac.is_player = bool(fd.get("is_player", false))

		if fd.has("ai_spawn_unit"):
			fac.ai_spawn_unit = String(fd.get("ai_spawn_unit", ""))

		if fd.has("unit_limit"):
			fac.unit_limit = int(fd.get("unit_limit", 0))
			if fac.is_player:
				player_unit_limit_from_scenario = fac.unit_limit

		if fd.has("dark_actions_max"):
			fac.dark_actions_max = int(fd.get("dark_actions_max", 0))
		if fd.has("dark_actions_left"):
			fac.dark_actions_left = int(fd.get("dark_actions_left", 0))

		# pokud budeš chtít v budoucnu loadovat AI flags, nechávám hook:
		if fd.has("ai_flags"):
			var flags: Dictionary = fd.get("ai_flags", {})
			for k in flags.keys():
				# nastaví dynamické properties pokud existují
				fac.set(String(k), flags[k])

		faction_manager.add_faction(fac)

		# resources
		var res: Dictionary = fd.get("resources", {})
		for rk in res.keys():
			fac.change_resource(String(rk), float(res[rk]))

	# 4b) Sjednocení unit limitu: UnitManager používá unit_limit globálně
	# Pro MVP to necháme jako "player unit cap". Pokud ve scénáři není, fallback na UnitManager default.
	if player_unit_limit_from_scenario >= 0:
		unit_manager.unit_limit = player_unit_limit_from_scenario

	# 5) Units
	var units_arr: Array = data.get("units", [])
	for item in units_arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var ud: Dictionary = item

		var uid: int = int(ud.get("id", -1))
		var unit_key: String = String(ud.get("unit_key", ""))
		var region_id: int = int(ud.get("region_id", -1))
		var fid2: String = String(ud.get("faction_id", ""))
		var state: String = String(ud.get("state", "healthy"))

		if uid < 0 or unit_key == "" or region_id < 0 or fid2 == "":
			push_warning("Skipping invalid unit entry: %s" % str(ud))
			continue

		# bezpečnost: region existuje?
		if region_manager.get_region(region_id) == null:
			push_warning("Unit %d has invalid region_id=%d" % [uid, region_id])
			continue

		# bezpečnost: frakce existuje?
		if faction_manager.get_faction(fid2) == null:
			push_warning("Unit %d references unknown faction_id=%s" % [uid, fid2])
			continue

		var u := Unit.new().init(uid, unit_key, region_id, fid2)
		u.state = state
		unit_manager.units.append(u)

	# 6) UnitManager ID counter sync
	unit_manager.recompute_id_counter()

	# 7) Dark actions refresh pro playera na startu
	dark_actions_manager.refresh_dark_actions_for_faction(Balance.PLAYER_FACTION)

	if query != null:
		query.rebuild_indexes()

	emit_signal("game_updated")

# ---------------------------
# wrapper pro logovani
func _log(entry:Dictionary) -> void:
	if entry == null:
		return
	if not entry.has("turn"):
		entry["turn"] = turn
	Log_Manager.add(entry)

# wrappery – můžeš volat i přímo manažery z UI
func build_building(id:int) -> void:
	var log_entry = building_manager.build(id)
	_log(log_entry)
	emit_signal("game_updated")

func cast_spell(spell_id:int) -> void:
	var log_entry = spell_manager.cast(spell_id)
	_log(log_entry)
	emit_signal("game_updated")

func plan_mission(unit_id:int, region_id:int, mission_key:String) -> void:
	mission_manager.plan_mission(
		query.units.get_by_id(unit_id),
		region_manager.get_region(region_id),
		mission_key
	)
	emit_signal("game_updated")

func cancel_mission(idx:int) -> void:
	mission_manager.cancel_mission(idx)
	emit_signal("game_updated")
	
func resolve_all() -> void:
	mission_manager.resolve_all()
	emit_signal("game_updated")

# ---------------------------
func advance_turn() -> void:
	var entries: Array[Dictionary] = []
	if game_over:
		return
	
	# =========================
	# A) AI plánování (férově před resolve)
	# =========================
	ai_manager.execute_ai_turn()
	# (později sem dáš i ai movement planning, pokud bude)
	
	# =========================
	# B) Resolve misí (player + AI)
	# =========================
	entries += mission_manager.resolve_all()

	# =========================
	# C) World tick (lairs/budovy/ekonomika/cooldowny/dooms)
	# =========================
	process_lairs_end_of_turn()
	# 1) efekty budov
	entries += building_manager.apply_end_of_turn_effects()

	# 2) ekonomika
	entries += economic_manager.apply_economy_cycle()

	# 3) cooldowny dark actions
	dark_actions_manager.tick_cooldowns()

	# 4) doom income
	doom += doom_income

	# =========================
	# D) Souboje (po world ticku)
	# =========================
	var combat_res: Dictionary = combat_manager.resolve_all_combats()
	for e in combat_res.get("logs", []):
		entries.append(e)
	_process_domain_events(combat_res.get("events", []))

	# =========================
	# E) End-of-turn cleanup
	# =========================

	# reset moves na nový tah (až po všech efektech a combat)
	for u in unit_manager.units:
		u.moves_left = u.moves_per_turn
	
	# HEAT reakce
	_check_heat_thresholds(old_heat, heat)
	old_heat = heat

	# zaloguj vše najednou (konsistentně)
	for e in entries:
		_log(e)
	
	# --- End conditions (WIN/LOSE) ---
	var end_res := check_end_conditions()
	if game_over:
		# zaloguj konec hry do logu, ať je to vidět i bez UI okna
		var t := "🏆 VÍTĚZSTVÍ: %s" % String(end_res.get("reason", ""))
		if end_res.get("outcome", "") == "lose":
			t = "💀 PROHRA: %s" % String(end_res.get("reason", ""))
		_log({"type":"end", "text": t})
		emit_signal("game_updated")
		emit_signal("turn_resolved")
		return
	
	# posun kola
	turn += 1

	# refresh dark actions pro hráče (nový tah)
	dark_actions_manager.refresh_dark_actions_for_faction(Balance.PLAYER_FACTION)
	
	emit_signal("game_updated")
	emit_signal("turn_resolved")

func _check_heat_thresholds(old_heat: int, new_heat: int) -> void:
	var paladin_faction := faction_manager.get_faction("paladin")
	if paladin_faction == null:
		return

	# žádná změna → nic neřešíme
	if new_heat == old_heat:
		return

	# --- STAGE 1 ---
	if old_heat < Balance.HEAT_STAGE_1 and new_heat >= Balance.HEAT_STAGE_1:
		heat_stage = max(heat_stage, 1)
		_log({
			"type": "heat",
			"text": "🔥 [HEAT 25] Řády paladinů začínají sledovat temné aktivity."
		})

	# --- STAGE 2 ---
	if old_heat < Balance.HEAT_STAGE_2 and new_heat >= Balance.HEAT_STAGE_2:
		heat_stage = max(heat_stage, 2)
		_log({
			"type": "heat",
			"text": "🔥🔥 [HEAT 50] Frakce dobra mobilizují armády a vysílají inkvizitory."
		})

	# --- STAGE 3 ---
	if old_heat < Balance.HEAT_STAGE_3 and new_heat >= Balance.HEAT_STAGE_3:
		heat_stage = max(heat_stage, 3)
		paladin_faction.ai_regular_spawns_enabled = true
		_log({
			"type": "heat",
			"text": "🔥🔥🔥 [HEAT 76] Svaté výpravy proudí ze všech koutů světa."
		})

	# --- STAGE 4 ---
	if old_heat < Balance.HEAT_MAX and new_heat >= Balance.HEAT_MAX:
		heat_stage = 4
		_log({
			"type": "cycle",
			"text": "💀 [HEAT 100] Začíná závěrečná křížová výprava proti Temnému pánovi!"
		})

	# --- BEHAVIOR ENUM (paralelně s boolean flags, bude primární) ---
	if new_heat >= Balance.HEAT_STAGE_3:
		paladin_faction.current_behavior = Faction.Behavior.COORDINATED
	elif new_heat >= Balance.HEAT_STAGE_2:
		paladin_faction.current_behavior = Faction.Behavior.AGGRESSIVE
	elif new_heat >= Balance.HEAT_STAGE_1:
		paladin_faction.current_behavior = Faction.Behavior.PATROLLING
	else:
		paladin_faction.current_behavior = Faction.Behavior.PASSIVE

func check_end_conditions() -> Dictionary:
	# už skončeno
	if game_over:
		return game_over_result

	# LOSE: heat
	if heat >= Balance.HEAT_MAX:
		game_over = true
		game_over_result = {
			"ok": false,
			"outcome": "lose",
			"reason": "HEAT dosáhl 100. Začíná závěrečná křížová výprava."
		}
		emit_signal("game_ended", game_over_result)
		return game_over_result

	# WIN: ovládáš dostatek regionů
	var cnt: int = query.regions.count_player_owned_or_controlled()
	if cnt >= Balance.WIN_REGIONS_REQUIRED:
		game_over = true
		game_over_result = {
			"ok": true,
			"outcome": "win",
			"reason": "Ovládáš (vlastnictvím nebo korupcí) %d regionů." % cnt
		}
		emit_signal("game_ended", game_over_result)
		return game_over_result

	return { "ok": false, "outcome": "none", "reason": "" }

# ---------------------------
func _defeat_and_cycle() -> String:
	var msg := "Temný Pán poražen. Cyklus obnoven."
	load_scenario(DEFAULT_SCENARIO_PATH)
	_log({"text": msg, "type": "cycle"})
	return msg

func move_unit(unit_id:int, target_region_id:int) -> void:
	var result := unit_manager.move_unit(unit_id, target_region_id)

	# zaloguj logs z manageru
	for le in result.get("logs", []):
		_log(le)

	# zaloguj hlavní text (pokud chceš)
	if result.has("text"):
		_log(result)

	_process_domain_events(result.get("events", []))

	emit_signal("game_updated")

func _process_domain_events(events: Array) -> void:
	if events.is_empty():
		return

	var touched_units := false
	var touched_regions := false
	var unit_moved_payloads: Array[Dictionary] = []

	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var t := String(ev.get("type",""))

		match t:
			# --- units ---
			"unit_added", "unit_removed", "unit_state_changed", "unit_moved":
				touched_units = true
				if t == "unit_moved":
					unit_moved_payloads.append({
						"unit_id": ev["unit_id"],
						"from": ev["from"],
						"to": ev["to"]
					})

			# --- regions ---
			"region_owner_changed", "region_controller_changed", "region_tags_changed":
				touched_regions = true

			_:
				pass

	# Rebuild indexes FIRST so signal handlers see fresh cache
	if query != null:
		if touched_units:
			query.units.rebuild()
		if touched_regions:
			query.regions.rebuild()

	# Emit unit_moved AFTER rebuild — _refresh_unit_positions() now gets correct cache
	for p in unit_moved_payloads:
		emit_signal("unit_moved", p["unit_id"], p["from"], p["to"])

func process_lairs_end_of_turn() -> void:
	for region in region_manager.regions:
		if not region.has_lair():
			continue

		var lair_conf: Dictionary = Balance.LAIR.get(region.lair_id, {})
		if lair_conf.is_empty():
			continue

		var spawn_unit_id: String = lair_conf.get("spawn_unit", "")
		if spawn_unit_id == "":
			continue

		var max_units:int = int(lair_conf.get("max_units", 0))
		if max_units <= 0:
			continue

		# spočítáme, kolik jednotek z lairu už v regionu je
		var count_in_region:int = 0
		for u in unit_manager.units:
			if u.region_id == region.id and u.state != "lost":
				count_in_region += 1

		if count_in_region >= max_units:
			continue

		# pro jednoduchost spawni 1 jednotku KAŽDÉ KOLO dokud nejsi na limitu
		var faction_id:String = lair_conf.get("faction_id", "neutral")
		var spawn_res := unit_manager.spawn_unit_free(faction_id, spawn_unit_id, region.id)
		for le in spawn_res.get("logs"):
			_log(le)
		_process_domain_events(spawn_res.get("events"))
		
		# můžeš si do jednotky uložit odkud pochází:
		#new_unit.source_lair_id = region.lair_id

func apply_command_result(res: Dictionary) -> Dictionary:
	# jednotné místo: logs + events + UI signal
	for e in res.get("logs", []):
		_log(e)

	_process_domain_events(res.get("events", []))

	emit_signal("game_updated")
	return res

func exec(res: Dictionary) -> Dictionary:
	return apply_command_result(res)
