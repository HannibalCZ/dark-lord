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

# ---------------------------
func init(gs: GameStateSingleton) -> void:
	game_state = gs
	EventBus.mission_resolved.connect(_on_mission_resolved)

# ---------------------------
# Voláno na začátku tahu (Rada zasvěcených).
# Vrátí filtrovaný seznam EventData z minulé herní fáze.
func generate_events_for_turn() -> Array[EventData]:
	var events: Array[EventData] = []

	_collect_movement_events(events)
	_collect_mission_events(events)
	_collect_heat_awareness_events(events)

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
# ZDROJ 3 — Změny Heat a Awareness (Stínový vezír)
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

	# Awareness (stub — v MVP zatím vždy 0)
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
