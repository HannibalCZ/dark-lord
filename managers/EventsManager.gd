# managers/EventsManager.gd
extends Node
class_name EventsManager

# Není autoload — instanciuje ho GameState v Task C.
# Přístup k datům výhradně přes game_state nebo EventBus,
# nikdy přímé volání jiných manažerů.

var game_state: GameStateSingleton

# Výsledky hráčových misí z aktuálního tahu — sbíráme přes EventBus.
# generate_events_for_turn() je přečte a seznam vymaže.
var _collected_player_results: Array[Dictionary] = []

# Výsledky bitev z aktuálního tahu — sbíráme přes EventBus.
var _collected_combat_results: Array[Dictionary] = []

# Znicene organizace z aktuálního tahu — sbíráme přes EventBus.
var _collected_org_events: Array[Dictionary] = []

# Spawn eventů AI jednotek z aktuálního tahu — sbíráme přes EventBus.
var _collected_spawn_events: Array[Dictionary] = []

# ---------------------------
func init(gs: GameStateSingleton) -> void:
	game_state = gs
	EventBus.mission_resolved.connect(_on_mission_resolved)
	EventBus.combat_resolved.connect(_on_combat_resolved)
	EventBus.org_destroyed.connect(_on_org_destroyed)
	EventBus.org_doctrine_changed.connect(_on_org_doctrine_changed)
	EventBus.ai_unit_spawned.connect(_on_ai_unit_spawned)
	GameState.game_ended.connect(_on_game_ended)

# ---------------------------
# Voláno na začátku tahu (Rada zasvěcených).
# Vrátí filtrovaný seznam EventData z minulé herní fáze.
func generate_events_for_turn() -> Array[EventData]:
	var events: Array[EventData] = []

	_collect_movement_events(events)
	_collect_mission_events(events)
	_collect_combat_events(events)
	_collect_heat_awareness_events(events)
	_collect_org_events(events)
	_collect_spawn_events(events)

	_collected_player_results.clear()

	return _filter_events(events)

# ---------------------------
# Uvítací event — zobrazí se jednou při startu nové hry
# ---------------------------
func generate_welcome_event() -> EventData:
	var narrative: String = (
		"Pane, jménem Rady zasvěcených vás vítám v nové éře. "
		+ "Svět vás dosud nezná — vaše jméno se nevyslovuje v síních mocných ani v modlitbách chrámů. "
		+ "Operujeme ze stínu: neviditelní, trpěliví, neúprosní. "
		+ "Temný pán povstává."
	)
	var summary: String = "Nová hra zahájena. Tah 1."
	return EventData.create(
		Balance.ADVISOR_VEZIR,
		Balance.EVENT_IMPORTANT,
		narrative,
		summary
	)

# ---------------------------
# ZDROJ 1 — Pohyby AI armád (Temný kapitán)
# ---------------------------
func _collect_movement_events(events: Array[EventData]) -> void:
	var log: Array[Dictionary] = game_state.ai_manager.turn_movement_log
	if log.is_empty():
		return

	var lines: Array[String] = []
	for entry in log:
		var from_region: Region = game_state.region_manager.get_region(entry["from_region_id"])
		var to_region:   Region = game_state.region_manager.get_region(entry["to_region_id"])
		var from_name: String = from_region.name if from_region != null else "?"
		var to_name:   String = to_region.name   if to_region   != null else "?"
		lines.append("%s: %s → %s" % [entry["unit_name"], from_name, to_name])

	var moves_text: String = "\n".join(PackedStringArray(lines))
	var n: int = log.size()

	var narrative: String = (
		"Pane, nepřátelské síly se minulý tah pohnuly. "
		+ "Sledoval jsem každý jejich krok:\n%s\n"
		+ "Doporučuji vzít tato přeskupení v potaz při dalším plánování."
	) % moves_text

	var summary: String = "AI frakce provedly %d pohybů." % n

	events.append(EventData.create(
		Balance.ADVISOR_KAPITAN,
		Balance.EVENT_IMPORTANT,
		narrative,
		summary
	))

# ---------------------------
# ZDROJ 2 — Výsledky hráčových misí (Stínový vezír)
# ---------------------------
func _collect_mission_events(events: Array[EventData]) -> void:
	for result in _collected_player_results:
		var mission_key: String = String(result.get("mission_key", ""))
		var region_id:   int    = int(result.get("region_id", -1))
		var success:     bool   = bool(result.get("success", false))
		var is_fatal:    bool   = bool(result.get("is_fatal", false))

		var region: Region = (
			game_state.region_manager.get_region(region_id)
			if region_id >= 0 else null
		)
		var region_name: String = region.name if region != null else "neznámém místě"

		var mission_cfg:  Dictionary = Balance.MISSION.get(mission_key, {})
		var mission_name: String     = String(mission_cfg.get("display_name", mission_key))

		var priority:  String
		var narrative: String
		var summary:   String

		if success:
			priority  = Balance.EVENT_IMPORTANT
			narrative = (
				"Mise '%s' v oblasti %s byla úspěšně dokončena, Pane. "
				+ "Naši agenti odvedli svou práci tiše a efektivně. "
				+ "Výsledky jsou v souladu s očekáváním."
			) % [mission_name, region_name]
			summary = "Mise %s v %s: ÚSPĚCH." % [mission_key, region_name]

		elif is_fatal:
			priority  = Balance.EVENT_CRITICAL
			narrative = (
				"Přináším nepříjemné zprávy, Pane. "
				+ "Agent provádějící misi '%s' v oblasti %s byl odhalen nepřítelem a zajat. "
				+ "Tato ztráta je citelná — doporučuji přijmout opatření."
			) % [mission_name, region_name]
			summary = "Mise %s v %s: NEÚSPĚCH — agent zajat." % [mission_key, region_name]

		else:
			priority  = Balance.EVENT_ROUTINE
			narrative = (
				"Mise '%s' v oblasti %s selhala, avšak bez větších následků, Pane. "
				+ "Agent se stáhl v pořádku a čeká na další rozkazy."
			) % [mission_name, region_name]
			summary = "Mise %s v %s: NEÚSPĚCH." % [mission_key, region_name]

		events.append(EventData.create(
			Balance.ADVISOR_VEZIR,
			priority,
			narrative,
			summary
		))

# ---------------------------
# ZDROJ 3 — Výsledky bitev (Temný kapitán)
# ---------------------------
func _collect_combat_events(events: Array[EventData]) -> void:
	for result in _collected_combat_results:
		var region_name:        String = String(result.get("region_name", "?"))
		var att_fac:            String = String(result.get("attacker_faction", "?"))
		var def_fac:            String = String(result.get("defender_faction", "?"))
		var player_involved:    bool   = bool(result.get("player_involved", false))
		var player_was_defender: bool  = bool(result.get("player_was_defender", false))
		var attacker_won:       bool   = bool(result.get("attacker_won", false))

		var priority:  String
		var narrative: String
		var summary:   String

		if player_involved:
			if player_was_defender and attacker_won:
				# Hráč bránil a prohrál → CRITICAL
				priority  = Balance.EVENT_CRITICAL
				narrative = (
					"Pane, nase pozice v %s byla prolomena. "
					+ "%s nas premohla — utrpeli jsme porazku, kterou nelze ignorovat. "
					+ "Doporucuji okamzita opatreni."
				) % [region_name, att_fac]
				summary = "%s zvitezila v %s — nasa obrana se zhroutila." % [att_fac, region_name]

			elif not player_was_defender and attacker_won:
				# Hráč útočil a vyhrál → IMPORTANT
				priority  = Balance.EVENT_IMPORTANT
				narrative = (
					"Vyborne, Pane. Nase sily v %s zvitezily. "
					+ "%s byla odrazena a region je pod nasi kontrolou."
				) % [region_name, def_fac]
				summary = "Nasa armada zvitezila v %s." % region_name

			elif player_was_defender and not attacker_won:
				# Hráč bránil a ubránil → IMPORTANT
				priority  = Balance.EVENT_IMPORTANT
				narrative = (
					"Pane, nasa obrana v %s odrazila utok. "
					+ "%s byla odrazena — pozice drzi."
				) % [region_name, att_fac]
				summary = "Obrana %s uspesna, utok %s odrazen." % [region_name, att_fac]

			else:
				# Hráč útočil a prohrál → IMPORTANT
				priority  = Balance.EVENT_IMPORTANT
				narrative = (
					"Pane, nase sily v %s utrpely porazku. "
					+ "%s nas odrazila — armadu jsme ztratili."
				) % [region_name, def_fac]
				summary = "Nasa armada porazena v %s." % region_name

		else:
			# AI vs AI → ROUTINE (půjde pouze do logu)
			priority  = Balance.EVENT_ROUTINE
			narrative = "%s zauctocila na %s v %s." % [att_fac, def_fac, region_name]
			summary   = "AI vs AI bitva v %s." % region_name

		events.append(EventData.create(
			Balance.ADVISOR_KAPITAN,
			priority,
			narrative,
			summary
		))

	_collected_combat_results.clear()

# ---------------------------
# ZDROJ 4 — Změny Heat a Awareness (Stínový vezír)
# (přečíslováno — původně ZDROJ 3)
# ---------------------------
func _collect_heat_awareness_events(events: Array[EventData]) -> void:
	var old_h: int = game_state.old_heat
	var new_h: int = game_state.heat
	var old_a: int = game_state.prev_awareness
	var new_a: int = game_state.awareness

	# Heat
	if new_h != old_h:
		var crossed: bool = (
			(old_h < Balance.HEAT_STAGE_1 and new_h >= Balance.HEAT_STAGE_1) or
			(old_h < Balance.HEAT_STAGE_2 and new_h >= Balance.HEAT_STAGE_2) or
			(old_h < Balance.HEAT_STAGE_3 and new_h >= Balance.HEAT_STAGE_3) or
			(old_h < Balance.HEAT_MAX     and new_h >= Balance.HEAT_MAX)
		)

		var priority: String = Balance.EVENT_IMPORTANT if crossed else Balance.EVENT_ROUTINE

		var narrative: String
		if crossed:
			narrative = (
				"Pane, síly dobra překročily nový práh bdělosti — Heat dosáhl %d. "
				+ "Jejich odezva se stupňuje a operace se komplikují. "
				+ "Doporučuji zvýšenou opatrnost při dalších krocích."
			) % new_h
		else:
			narrative = (
				"Úroveň pozornosti sil dobra se změnila z %d na %d, Pane. "
				+ "Situace je zatím pod kontrolou, avšak sledujeme ji nadále."
			) % [old_h, new_h]

		var summary: String = "Heat: %d → %d." % [old_h, new_h]

		events.append(EventData.create(
			Balance.ADVISOR_VEZIR,
			priority,
			narrative,
			summary
		))

	# Awareness — práh 50 (Inkvizitoři zostřují pohled)
	if old_a < 50 and new_a >= 50:
		events.append(EventData.create(
			Balance.ADVISOR_VEZIR,
			Balance.EVENT_IMPORTANT,
			"Pane, nase aktivity zacaly pritahovat nebezpecnou pozornost. Inkvizitoři zostřují svůj pohled — doporucuji opatrnost.",
			"Awareness prekrocila 50 — Inkvizitoři zmenili chovani."
		))

	# Awareness — obecná změna
	if new_a != old_a:
		var priority: String = Balance.EVENT_IMPORTANT if new_a > old_a else Balance.EVENT_ROUTINE
		var narrative: String = (
			"Pane, míra obecného podezření světa se změnila z %d na %d. "
			+ "Naše aktivity nezůstávají zcela nepovšimnuty."
		) % [old_a, new_a]
		var summary: String = "Awareness: %d → %d." % [old_a, new_a]

		events.append(EventData.create(
			Balance.ADVISOR_VEZIR,
			priority,
			narrative,
			summary
		))

# ---------------------------
# Filtrování výsledku
# ---------------------------
func _filter_events(all_events: Array[EventData]) -> Array[EventData]:
	var critical_list:  Array[EventData] = []
	var important_list: Array[EventData] = []

	for ev in all_events:
		match ev.priority:
			Balance.EVENT_CRITICAL:
				critical_list.append(ev)
			Balance.EVENT_IMPORTANT:
				important_list.append(ev)
			# EVENT_ROUTINE → zahazujeme, jdou pouze do LogManageru

	# Cap na IMPORTANT
	if important_list.size() > Balance.COUNCIL_MAX_IMPORTANT:
		important_list = important_list.slice(0, Balance.COUNCIL_MAX_IMPORTANT)

	var result: Array[EventData] = []
	result.append_array(critical_list)
	result.append_array(important_list)

	# Celkový limit (CRITICAL mají přednost — jsou přidány první)
	if result.size() > Balance.COUNCIL_MAX_TOTAL:
		result = result.slice(0, Balance.COUNCIL_MAX_TOTAL)

	return result

# ---------------------------
# Konec hry — okamzity event do Rady zasvecených
# ---------------------------
func _on_game_ended(result: Dictionary) -> void:
	var is_win: bool = result.get("outcome", "") == "win"
	var reason: String = result.get("reason", "")
	var event := EventData.create(
		Balance.ADVISOR_VEZIR if is_win else Balance.ADVISOR_KAPITAN,
		Balance.EVENT_CRITICAL,
		_build_end_game_narrative(is_win, reason),
		reason
	)
	var end_events: Array[EventData] = []
	end_events.append(event)
	EventBus.council_events_ready.emit(end_events)


func _build_end_game_narrative(is_win: bool, reason: String) -> String:
	if is_win:
		return (
			"Pane, je hotovo. Svet se sklonil pred vasi vuli. "
			+ "%s Temnota zvitezila — ne silou, ale trpelivosti "
			+ "a lsti. Vase jmeno bude sepskat po generace."
		) % reason
	else:
		return (
			"Pane — padli jsme. %s Nepritel obsadil nasi "
			+ "pevnost. Neni kam ustoupit. Byl to cestny boj, "
			+ "ale nestacilo to."
		) % reason


# ---------------------------
# Signal handler — sbírá výsledky hráčových misí přes EventBus
# ---------------------------
func _on_mission_resolved(data: Dictionary) -> void:
	if game_state == null:
		return

	var uid: int = int(data.get("unit_id", -1))
	if uid < 0:
		return

	var unit: Unit = game_state.query.units.get_by_id(uid)
	if unit == null:
		return

	# Pouze hráčovy mise
	if unit.faction_id != Balance.PLAYER_FACTION:
		return

	# Fatální = agent skončil ve stavu "lost"
	var is_fatal: bool = (not data.get("success", true)) and (unit.state == "lost")

	var entry: Dictionary = data.duplicate()
	entry["is_fatal"] = is_fatal
	_collected_player_results.append(entry)

# ---------------------------
# Signal handler — sbírá výsledky bitev přes EventBus
# ---------------------------
func _on_combat_resolved(result: Dictionary) -> void:
	_collected_combat_results.append(result)

# ---------------------------
# ZDROJ 5 — Znicene organizace (Temny kapitan)
# ---------------------------
func _collect_org_events(events: Array[EventData]) -> void:
	for e in _collected_org_events:
		var region_id: int = int(e.get("region_id", -1))
		var region: Region = (
			game_state.region_manager.get_region(region_id)
			if region_id >= 0 else null
		)
		var region_name: String = region.name if region != null else "neznamem miste"

		events.append(EventData.create(
			Balance.ADVISOR_KAPITAN,
			Balance.EVENT_CRITICAL,
			"Pane, nase organizace v %s byla odhalena a zlikvidovana." % region_name,
			"Organizace znicena v regionu %s." % region_name
		))

	_collected_org_events.clear()

# ---------------------------
# Signal handler — sbírá znicene organizace přes EventBus
# ---------------------------
func _on_org_destroyed(region_id: int) -> void:
	_collected_org_events.append({ "region_id": region_id })

# ---------------------------
# ZDROJ 6 — Spawn AI jednotek (Temny kapitan)
# ---------------------------
func _collect_spawn_events(events: Array[EventData]) -> void:
	for e in _collected_spawn_events:
		var faction_id: String = String(e.get("faction_id", "?"))
		var unit_key:   String = String(e.get("unit_key", "?"))
		var region_id:  int    = int(e.get("region_id", -1))

		var faction: Faction = (
			game_state.faction_manager.get_faction(faction_id)
			if game_state != null else null
		)
		var faction_name: String = faction.name if faction != null else faction_id

		var region: Region = (
			game_state.region_manager.get_region(region_id)
			if region_id >= 0 else null
		)
		var region_name: String = region.name if region != null else "neznamem miste"

		var unit_cfg: Dictionary = Balance.UNIT.get(unit_key, {})
		var unit_name: String = String(unit_cfg.get("display_name", unit_key))

		events.append(EventData.create(
			Balance.ADVISOR_KAPITAN,
			Balance.EVENT_IMPORTANT,
			"Pane, %s posiluje sve rady. Nova jednotka (%s) byla spatrena v %s." % [
				faction_name, unit_name, region_name
			],
			"%s: spawnovana jednotka %s v %s." % [faction_name, unit_key, region_name]
		))

	_collected_spawn_events.clear()

# ---------------------------
# Signal handler — AI unit spawned
# ---------------------------
func _on_ai_unit_spawned(faction_id: String, unit_key: String, region_id: int) -> void:
	_collected_spawn_events.append({
		"faction_id": faction_id,
		"unit_key":   unit_key,
		"region_id":  region_id
	})

# ---------------------------
# Signal handler — zmena doktríny organizace (ROUTINE — jen do logu)
# ---------------------------
func _on_org_doctrine_changed(region_id: int, new_doctrine: String) -> void:
	if game_state == null:
		return
	var region: Region = game_state.region_manager.get_region(region_id)
	var region_name: String = region.name if region != null else "region %d" % region_id
	game_state._log({
		"type": "org",
		"text": "Doktrína organizace v %s zmenena na '%s'." % [region_name, new_doctrine]
	})
