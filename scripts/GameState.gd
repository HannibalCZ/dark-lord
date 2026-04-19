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
@onready var events_manager: EventsManager = EventsManager.new()
@onready var org_manager: OrgManager = OrgManager.new()
@onready var progression_manager: ProgressionManager = ProgressionManager.new()
@onready var heat_tracker: HeatAwarenessTracker = HeatAwarenessTracker.new()
@onready var reputation_manager: ReputationManager = ReputationManager.new()

var rng := RandomNumberGenerator.new()
var turn:int = 1
var heat: int = 0
var old_heat: int = 0
var heat_stage:int = 0  # 0..4 podle toho, jaký threshold už byl dosažen
var doom:int = 0
var doom_income:int = 0
var game_over: bool = false
var game_over_result: Dictionary = {}
var player_start_region_id: int = -1
var _start_region_captured: bool = false
var awareness: int = 10      # stub — MVP nemá awareness mechaniku
var prev_awareness: int = 0 # předchozí hodnota pro EventsManager
var pending_events: Array[EventData] = []  # eventy čekající na zobrazení v Radě zasvěcených
var _welcome_shown: bool = false
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
	org_manager.game_state         = self
	progression_manager.game_state = self
	reputation_manager.game_state  = self
	events_manager.init(self)

	query = GameQuery.new(self)
	query.rebuild_indexes()
	commands = GameCommands.new(self)
	
	# případné navázání signálů (UI naslouchá přes GameState)
	spell_manager.magic_used.connect(func(): emit_signal("game_updated"))
	building_manager.buildings_changed.connect(func(): emit_signal("game_updated"))
	EventBus.unit_killed.connect(_on_unit_killed)
	
	rng.randomize()
	init_data()

# ---------------------------
func init_data() -> void:
	load_scenario(DEFAULT_SCENARIO_PATH)
	emit_signal("game_updated")
	if not _welcome_shown:
		call_deferred("_emit_welcome_event")

func _emit_welcome_event() -> void:
	_welcome_shown = true
	var welcome: EventData = events_manager.generate_welcome_event()
	pending_events = [welcome]
	EventBus.council_events_ready.emit(pending_events)

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
	_start_region_captured = false
	old_heat = heat

	# Startovní region hráče
	player_start_region_id = int(data.get("player_start_region_id", -1))
	if player_start_region_id == -1:
		push_warning("Scenario neobsahuje player_start_region_id")
	
	unit_manager.init_empty()
	faction_manager.init_empty()
	mission_manager.init()
	progression_manager.unlocked_nodes.clear()
	progression_manager.condition_trackers.clear()
	org_manager.orgs.clear()
	org_manager._next_id = 1
	events_manager.reset()

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

	_place_procedural_secrets()

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

		# Inicializace reputace ze zakladnich hodnot v Balance.gd.
		# Faze a modifier se nastavi pri prvnim update_all() v advance_turn().
		fac.reputation = Balance.REPUTATION_BASE.get(fac.id, 50)

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

	# 6b) Orgs ze scénáře — ukládáme přímo do orgs pole (bez EventBus),
	# aby neutrální orgs nevyvolávaly EventsManager notifikace při načtení.
	var orgs_arr: Array = data.get("orgs", [])
	for item in orgs_arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var od: Dictionary = item
		var org_type: String = String(od.get("org_type", ""))
		var owner: String    = String(od.get("owner", "neutral"))
		var org_rid: int     = int(od.get("region_id", -1))
		var doctrine: String = String(od.get("doctrine", ""))
		var loyalty: int     = int(od.get("loyalty", Balance.ORG_LOYALTY_START))

		if org_type == "" or org_rid < 0:
			push_warning("Skipping invalid org entry: %s" % str(od))
			continue
		if not Balance.ORG.has(org_type):
			push_warning("Org entry has unknown org_type='%s'" % org_type)
			continue
		if region_manager.get_region(org_rid) == null:
			push_warning("Org entry has invalid region_id=%d" % org_rid)
			continue

		var default_doctrine: String = Balance.ORG[org_type]["default_doctrine"]
		var used_doctrine: String = doctrine if doctrine != "" else default_doctrine
		if not Balance.ORG[org_type]["doctrines"].has(used_doctrine):
			push_warning("Org entry has unknown doctrine='%s' for type='%s'" % [used_doctrine, org_type])
			used_doctrine = default_doctrine

		var org: Dictionary = {
			"org_id":       "org_" + str(org_manager._next_id),
			"org_type":     org_type,
			"owner":        owner,
			"region_id":    org_rid,
			"doctrine":     used_doctrine,
			"founded_turn": turn,
			"loyalty":      loyalty,
			"is_rogue":     false,
			# Neutralni organizace ze scenare jsou vzdy viditelne.
			# Hracovy organizace ze scenare zacinaji skryte
			# (konzistentni s add_org()).
			"visible":      owner != Balance.ORG_OWNER_PLAYER
		}
		org_manager._next_id += 1
		org_manager.orgs.append(org)

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

	heat_tracker.reset()

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

	# 2) pasivni efekty organizaci
	entries += org_manager.apply_end_of_turn_effects()       # hracovy aktivni orgy
	org_manager.apply_neutral_and_rogue_effects()             # neutral + rogue orgy

	# 2b) loajalitni decay — po efektech, pred ekonomikou
	# (EconomicManager uz vidi aktualni loyalty pri vypoctu gold/mana prijmu)
	org_manager.apply_loyalty_decay()

	# 2c) odhaleni organizaci — po decay, aby loyalty byla aktualni
	# Shadow Network disinfo uz skryla org v apply_end_of_turn_effects()
	org_manager._check_org_visibility()

	# 3) ekonomika
	entries += economic_manager.apply_economy_cycle()

	# 4) cooldowny dark actions
	dark_actions_manager.tick_cooldowns()

	# 5) doom income
	if doom_income != 0:
		var doom_ctx := EffectContext.make(self, null, Balance.PLAYER_FACTION)
		effects_system.apply({"doom": doom_income}, doom_ctx)

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

	# Heat decay — přirozené snižování každý tah (po všech zdrojích, před prahy)
	if heat > 0:
		var decay_ctx := EffectContext.make(self, null, Balance.PLAYER_FACTION)
		decay_ctx.source_label = "Přirozený útlum"
		effects_system.apply({"heat": -Balance.HEAT_DECAY_PER_TURN}, decay_ctx)

	# Reputace — prepocitej pred heat thresholdy, aby modifier byl aktualni
	reputation_manager.update_all()

	# HEAT reakce
	_check_heat_thresholds(old_heat, heat)
	# AWARENESS reakce
	_check_awareness_thresholds(prev_awareness, awareness)

	# AI spawn (po heat thresholdech, aby paladin viděl aktuální stav)
	process_ai_spawning()
	# Průzkumník — jednorázový spawn oddělený od process_ai_spawning()
	_try_spawn_explorer()

	# =========================
	# F) Rada zasvěcených — generuj eventy z tohoto tahu
	#    MUSÍ být před old_heat = heat (EventsManager čte starou vs novou hodnotu)
	#    generate_events_for_turn() voláme VŽDY — _collected_player_results.clear()
	#    se musí provést i v tahu 1, jinak se výsledky tahu 1 mísí s tahem 2.
	#    Emit do UI přeskočíme v tahu 1 — uvítací event byl zobrazen při startu hry.
	# =========================
	pending_events = events_manager.generate_events_for_turn()
	#if turn > 1:
	EventBus.council_events_ready.emit(pending_events)

	old_heat = heat
	prev_awareness = awareness

	# zaloguj vše najednou (konsistentně)
	for e in entries:
		_log(e)

	# Zkontroluj zda startovní region stále patří hráči
	if player_start_region_id >= 0:
		var start_region: Region = region_manager.get_region(player_start_region_id)
		if start_region != null:
			# Případ A: nepřítel již vlastní region (po bitvě nebo pohybu bez odporu)
			if start_region.owner_faction_id != Balance.PLAYER_FACTION:
				_start_region_captured = true
			# Případ B: hráč stále vlastní region, ale nepřátelská armáda
			# je uvnitř a hráč nemá žádnou obrannou armádu
			else:
				var enemies: Array = query.units.enemies_in_region(
					player_start_region_id, Balance.PLAYER_FACTION, true)
				if enemies.size() > 0:
					var defenders: Array = []
					for u in query.units.in_region(player_start_region_id, false):
						if u.faction_id == Balance.PLAYER_FACTION \
								and u.type == "army":
							defenders.append(u)
					if defenders.size() == 0:
						_start_region_captured = true

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

	# Reputacni modifier — snizuje/zvysuje efektivni heat pro tuto frakci.
	# Hostile: -10 (frakce reaguje drive),
	# Infiltrated: +10 (reaguje pozdeji),
	# Controlled: +99 (prakticky nikdy neprekroci threshold)
	var rep_mod: int = paladin_faction.reputation_modifier
	var eff_old: int = old_heat + rep_mod
	var eff_new: int = new_heat + rep_mod

	# --- STAGE 1 ---
	if eff_old < Balance.HEAT_STAGE_1 and eff_new >= Balance.HEAT_STAGE_1:
		heat_stage = max(heat_stage, 1)
		_log({
			"type": "heat",
			"text": "🔥 [HEAT 25] Řády paladinů začínají sledovat temné aktivity."
		})

	# --- STAGE 2 ---
	if eff_old < Balance.HEAT_STAGE_2 and eff_new >= Balance.HEAT_STAGE_2:
		heat_stage = max(heat_stage, 2)
		_log({
			"type": "heat",
			"text": "🔥🔥 [HEAT 50] Frakce dobra mobilizují armády a vysílají inkvizitory."
		})

	# --- STAGE 3 ---
	if eff_old < Balance.HEAT_STAGE_3 and eff_new >= Balance.HEAT_STAGE_3:
		heat_stage = max(heat_stage, 3)
		paladin_faction.ai_regular_spawns_enabled = true
		_log({
			"type": "heat",
			"text": "🔥🔥🔥 [HEAT 85] Svaté výpravy proudí ze všech koutů světa."
		})

	# --- STAGE 4 ---
	if eff_old < Balance.HEAT_MAX and eff_new >= Balance.HEAT_MAX:
		heat_stage = 4
		_log({
			"type": "cycle",
			"text": "💀 [HEAT 100] Začíná závěrečná křížová výprava proti Temnému pánovi!"
		})

	# --- BEHAVIOR ENUM — zalozeno na efektivnim heat vcetne rep_mod ---
	if eff_new >= Balance.HEAT_STAGE_3:
		paladin_faction.current_behavior = Faction.Behavior.COORDINATED
	elif eff_new >= Balance.HEAT_STAGE_2:
		paladin_faction.current_behavior = Faction.Behavior.AGGRESSIVE
	elif eff_new >= Balance.HEAT_STAGE_1:
		paladin_faction.current_behavior = Faction.Behavior.PATROLLING
	else:
		paladin_faction.current_behavior = Faction.Behavior.PASSIVE

func _check_awareness_thresholds(old_aw: int, new_aw: int) -> void:
	if old_aw == new_aw:
		return
	if old_aw < Balance.AWARENESS_STAGE_INQUISITOR \
			and new_aw >= Balance.AWARENESS_STAGE_INQUISITOR:
		EventBus.inquisitor_gone_global.emit()

func check_end_conditions() -> Dictionary:
	# už skončeno
	if game_over:
		return game_over_result

	# WIN: 2/3 civilizovaných regionů pod kontrolou
	var controlled: int = query.regions.count_player_controlled_civilized()
	var total_civ: int = query.regions.count_total_civilized()
	if controlled >= Balance.WIN_REGIONS_REQUIRED:
		game_over = true
		game_over_result = {
			"ok": true,
			"outcome": "win",
			"reason": "Ovládas %d z %d civilizovanych regionu." % [controlled, total_civ]
		}
		emit_signal("game_ended", game_over_result)
		return game_over_result

	# LOSE: startovní region obsazen nepřítelem
	# flag _start_region_captured nastavuje CombatManager (Task 2)
	if _start_region_captured:
		game_over = true
		game_over_result = {
			"ok": false,
			"outcome": "lose",
			"reason": "Tvuj lair padl do rukou nepritele."
		}
		emit_signal("game_ended", game_over_result)
		return game_over_result

	return {"ok": false, "outcome": "none", "reason": ""}

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
	for region in query.regions.get_regions_with_lair():

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

		# Počítáme živé jednotky frakce lairu globálně (přes UnitQuery cache)
		var count_alive: int = query.units.active_count_for_faction(lair_faction_id)

		if count_alive >= max_units:
			continue

		# spawn_rate: spawni jen každých N tahů
		var spawn_rate: int = int(lair_conf.get("spawn_rate", 1))
		region.lair_spawn_counter += 1
		if region.lair_spawn_counter < spawn_rate:
			continue
		region.lair_spawn_counter = 0

		var spawn_res := unit_manager.spawn_unit_free(lair_faction_id, spawn_unit_id, region.id)
		for le in spawn_res.get("logs"):
			_log(le)
		_process_domain_events(spawn_res.get("events"))

func process_ai_spawning() -> void:
	for faction_id in Balance.AI_SPAWN:
		var cfg: Dictionary = Balance.AI_SPAWN[faction_id]
		var faction: Faction = faction_manager.get_faction(faction_id)
		if faction == null:
			continue

		# Ovladnuta frakce nespawnuje — reset counteru aby se neakumulovaly tahy
		if faction.reputation_phase == "controlled":
			faction.spawn_counter = 0
			continue

		var trigger_value: int = heat if cfg["trigger"] == "heat" else awareness
		# Reputacni modifier posouva efektivni threshold spawnu:
		# Hostile: -10 (spawnuje drive), Infiltrated: +10 (spawnuje pozdeji)
		var base_threshold: int = int(cfg["threshold"])
		var effective_threshold: int = base_threshold + faction.reputation_modifier
		faction.ai_regular_spawns_enabled = trigger_value >= effective_threshold

		if not faction.ai_regular_spawns_enabled:
			faction.spawn_counter = 0
			continue

		var current_count: int = query.units.count_units_by_faction_and_key(faction_id, String(cfg["unit_key"]))
		if current_count >= int(cfg["unit_limit"]):
			continue

		faction.spawn_counter += 1
		if faction.spawn_counter < int(cfg["spawn_rate"]):
			continue

		faction.spawn_counter = 0
		_spawn_faction_unit(faction_id, String(cfg["unit_key"]))


func _spawn_faction_unit(faction_id: String, unit_key: String) -> void:
	var region_id: int = -1

	# 1) první region ve vlastnictví frakce
	var owned := query.regions.regions_owned_by(faction_id)
	if not owned.is_empty():
		region_id = owned[0].id

	# 2) fallback: region kde má frakce živou jednotku
	if region_id < 0:
		for u in unit_manager.units:
			if u.faction_id == faction_id and u.state != "lost":
				region_id = u.region_id
				break

	# 3) nikde — přeskočíme
	if region_id < 0:
		push_warning("process_ai_spawning: frakce '%s' nema zadny region ani jednotku, spawn preskocen." % faction_id)
		return

	var spawn_res := unit_manager.spawn_unit_free(faction_id, unit_key, region_id)
	for le in spawn_res.get("logs", []):
		_log(le)
	_process_domain_events(spawn_res.get("events", []))
	EventBus.ai_unit_spawned.emit(faction_id, unit_key, region_id)

# ---------------------------
# BFS vzdálenost mezi dvěma regiony.
# Vrátí počet kroků (hran) nebo -1 pokud cesta neexistuje.
# RegionManager.get_bfs_distance() neexistuje — implementujeme inline.
func _bfs_distance(from_id: int, to_id: int) -> int:
	if from_id == to_id:
		return 0
	var visited: Dictionary = {}
	var queue: Array = [[from_id, 0]]
	visited[from_id] = true
	while not queue.is_empty():
		var current: Array = queue.pop_front()
		var cur_id: int = int(current[0])
		var dist: int = int(current[1])
		for neighbor in region_manager.adjacency.get(cur_id, []):
			if visited.has(neighbor):
				continue
			if neighbor == to_id:
				return dist + 1
			visited[neighbor] = true
			queue.append([neighbor, dist + 1])
	return -1  # nedosažitelný region

# Najde obchodní region nejvzdálenější od hráčova lairu (BFS vzdálenost).
# Průzkumník spawne co nejdál od hráče — maximalizuje průzkumné pokrytí.
func _find_explorer_spawn_region() -> int:
	var merchant_regions: Array[Region] = \
		region_manager.get_regions_by_faction("merchant")
	if merchant_regions.is_empty():
		# Fallback: libovolný region který hráč nevlastní
		for r in region_manager.regions:
			if r != null and r.owner_faction_id != Balance.PLAYER_FACTION:
				return r.id
		return -1

	var farthest_id: int = -1
	var max_dist: int = -1
	for region in merchant_regions:
		var dist: int = _bfs_distance(player_start_region_id, region.id)
		if dist > max_dist:
			max_dist = dist
			farthest_id = region.id
	return farthest_id

# Zkontroluje podmínky pro spawn průzkumníka a spawnuje pokud jsou splněny.
# Volá se z advance_turn() za process_ai_spawning() — nikdy je neslučuj.
# Podmínky: spawn 1 v tahu 1, spawn 2 při Awareness >= spawn_2_awareness.
func _try_spawn_explorer() -> void:
	var cfg: Dictionary = Balance.EXPLORER_SPAWN.get("merchant", {})
	if cfg.is_empty():
		return

	var merchant_faction: Faction = faction_manager.get_faction("merchant")
	if merchant_faction == null:
		return  # merchant frakce neexistuje v tomto scénáři

	var limit: int = int(cfg.get("unit_limit", 2))
	if merchant_faction.explorer_spawned_count >= limit:
		return  # Oba průzkumníci již byli spawnuti

	# Spawn 1 — tah 1 (první průzkumník na začátku hry)
	if merchant_faction.explorer_spawned_count == 0 \
			and turn == int(cfg.get("spawn_1_turn", 1)):
		_do_spawn_explorer(merchant_faction, cfg)
		return

	# Spawn 2 — Awareness >= threshold (druhý průzkumník při větší pozornosti)
	if merchant_faction.explorer_spawned_count == 1 \
			and awareness >= int(cfg.get("spawn_2_awareness", 35)):
		_do_spawn_explorer(merchant_faction, cfg)

# Provede samotný spawn průzkumníka a emituje event pro Radu zasvěcených.
func _do_spawn_explorer(faction: Faction, cfg: Dictionary) -> void:
	var spawn_region_id: int = _find_explorer_spawn_region()
	if spawn_region_id == -1:
		push_warning("_do_spawn_explorer: nenalezen zadny vhodny region, spawn preskocen.")
		return

	var unit_key: String = String(cfg.get("unit_key", "explorer"))
	# spawn_unit_free: faction_id první, unit_key druhý — stejný vzor jako _spawn_faction_unit()
	var spawn_res := unit_manager.spawn_unit_free("merchant", unit_key, spawn_region_id)
	for le in spawn_res.get("logs", []):
		_log(le)
	_process_domain_events(spawn_res.get("events", []))

	faction.explorer_spawned_count += 1

	var region: Region = region_manager.get_region(spawn_region_id)
	var region_name: String = region.name if region != null else "neznamy region"
	EventBus.explorer_appeared.emit(spawn_region_id, region_name)

# Aplikuje Heat boost při eliminaci průzkumníka.
# Voláno z MissionManager při úspěšné misi "eliminate" (Task 7).
# Dispatcher pro unit_killed signal — volá specializované handlery podle unit_key.
func _on_unit_killed(unit_id: int, unit_key: String, _region_id: int) -> void:
	if unit_key == "explorer":
		_on_explorer_killed(unit_id)
	# Budoucí rozšíření: inkvizitor, paladin, atd.

func _on_explorer_killed(_unit_id: int) -> void:
	var cfg: Dictionary = Balance.EXPLORER_SPAWN.get("merchant", {})
	var heat_boost: int = int(cfg.get("heat_on_kill", 8))
	var ctx := EffectContext.make(self, null, Balance.PLAYER_FACTION)
	ctx.source_label = "Pruzkumnik eliminovan — obchodnici zaznamenali zmizeni sveho zveda"
	effects_system.apply({"heat": heat_boost}, ctx)

func _place_procedural_secrets() -> void:
	if not Balance.PROCEDURAL_GENERATION_ENABLED:
		return

	# Inicializuj RNG se seedem
	var proc_rng := RandomNumberGenerator.new()
	if Balance.PROCEDURAL_SEED == 0:
		proc_rng.randomize()
	else:
		proc_rng.seed = Balance.PROCEDURAL_SEED

	# Získej způsobilé regiony
	# Způsobilé: region_kind == "wildlands", mimo startovní region, bez secret_id z JSON
	var eligible: Array[Region] = []
	for region in region_manager.regions:
		if region.region_kind != "wildlands":
			continue
		if region.id == player_start_region_id:
			continue
		if region.secret_id != "":
			continue
		eligible.append(region)

	if eligible.is_empty():
		return

	# Náhodně vyber počet tajemství podle hustoty
	var min_count: int = \
		max(1, int(floor(
			eligible.size()
			* Balance.PROCEDURAL_SECRET_DENSITY_MIN)))
	var max_count: int = \
		max(1, int(floor(
			eligible.size()
			* Balance.PROCEDURAL_SECRET_DENSITY_MAX)))
	var count: int = proc_rng.randi_range(min_count, max_count)

	# Zamíchej způsobilé regiony (Fisher-Yates)
	var shuffled: Array[Region] = eligible.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = proc_rng.randi_range(0, i)
		var tmp: Region = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	# Přiřaď tajemství prvním count regionům
	var secret_keys: Array = Balance.SECRET.keys()
	for i in range(min(count, shuffled.size())):
		var region: Region = shuffled[i]
		var secret_key: String = secret_keys[
			proc_rng.randi_range(0, secret_keys.size() - 1)]
		region.secret_id       = secret_key
		region.secret_known    = true
		region.secret_state    = "none"
		region.secret_progress = 0

func apply_command_result(res: Dictionary) -> Dictionary:
	# jednotné místo: logs + events + UI signal
	for e in res.get("logs", []):
		_log(e)

	_process_domain_events(res.get("events", []))

	emit_signal("game_updated")
	return res

func exec(res: Dictionary) -> Dictionary:
	return apply_command_result(res)
