extends Control

@onready var grid: GridContainer = $HBoxContainer/RegionsGrid
@onready var right_panel: VBoxContainer = $HBoxContainer/RightPanel
@onready var region_info: Label      = $HBoxContainer/RightPanel/VBoxContainer/RegionInfo
@onready var unit_select: OptionButton = $HBoxContainer/RightPanel/VBoxContainer/UnitSelect
@onready var unit_info: Label        = $HBoxContainer/RightPanel/VBoxContainer/UnitInfo
@onready var mission_select: OptionButton = $HBoxContainer/RightPanel/VBoxContainer/MissionsBox/MissionSelect
@onready var mission_confirm: Button      = $HBoxContainer/RightPanel/VBoxContainer/MissionsBox/MissionConfirm
@onready var mission_info: Label = $HBoxContainer/RightPanel/VBoxContainer/MissionInfo

@onready var neighbor_select: OptionButton = $HBoxContainer/RightPanel/VBoxContainer/MoveBox/NeighborSelect
@onready var move_confirm: Button          = $HBoxContainer/RightPanel/VBoxContainer/MoveBox/MoveConfirm
@onready var dark_action_select: OptionButton = $HBoxContainer/RightPanel/VBoxContainer/DarkActionBox/DarkActionSelect
@onready var dark_action_confirm: Button      = $HBoxContainer/RightPanel/VBoxContainer/DarkActionBox/DarkActionConfirm
@onready var dark_action_info: Label = $HBoxContainer/RightPanel/VBoxContainer/DarkActionInfo

var selected_region_idx: int = -1
var tile_scene: PackedScene = preload("res://scenes/ui/RegionTile.tscn")

func _ready() -> void:
	grid.columns = 4
	_build_grid()

	# signály
	mission_confirm.pressed.connect(_on_mission_confirm)
	move_confirm.pressed.connect(_on_move_confirm)
	unit_select.item_selected.connect(_on_unit_selected)
	dark_action_confirm.pressed.connect(_on_dark_action_confirm)
	dark_action_select.item_selected.connect(_on_dark_action_selected)
	mission_select.item_selected.connect(_on_mission_selected)
	
	GameState.connect("unit_moved", Callable(self, "_on_unit_moved"))
	GameState.connect("turn_resolved", Callable(self, "_on_turn_resolved"))
	GameState.connect("game_updated", Callable(self, "_on_game_updated"))
	
	EventBus.connect("mission_resolved", Callable(self, "_on_mission_resolved"))
	
	right_panel.visible = false
	_set_actions_enabled(false)

func _on_game_updated() -> void:
	if grid.get_child_count() != GameState.region_manager.regions.size():
		_build_grid()
		return
	_refresh_selected_panel()

func _on_mission_selected(_idx: int) -> void:
	_update_mission_info()

func _on_dark_action_selected(_idx: int) -> void:
	_update_dark_action_info()

func _check_dark_action_requirements(action_key: String) -> Dictionary:
	var def: Dictionary = Balance.DARK_ACTIONS.get(action_key, {})
	var req: Dictionary = def.get("requirements", {})

	# zatím řešíme jen regionové akce s korupční fází
	var atype: String = String(def.get("type", "global"))

	if atype == "region":
		if selected_region_idx < 0:
			return {"ok": false, "reason": "Není vybrán žádný region."}

		var region: Region = GameState.query.regions.get_by_id(selected_region_idx)

		# min_corruption_phase – pracujeme s hráčovou korupcí
		if req.has("min_corruption_phase"):
			var min_phase: int = int(req["min_corruption_phase"])
			var phase_id: int = region.get_corruption_phase_for(Balance.PLAYER_FACTION)
			if phase_id < min_phase:
				return {
					"ok": false,
					"reason": "Region je málo zkorumpovaný (vyžadována fáze korupce %d)." % min_phase
				}

	# sem můžeš později přidat další typy požadavků (min_heat, infernal_pact apod.)
	return {"ok": true}

func _update_dark_action_info() -> void:
	dark_action_info.text = ""

	if dark_action_select.disabled:
		dark_action_confirm.disabled = true
		return

	var action_key: String = UIHelpers.get_selected_key(dark_action_select)
	if action_key == "":
		dark_action_confirm.disabled = true
		return

	# základní popis
	var desc: String = _build_dark_action_description(action_key)

	# zkontroluj requirements
	var check: Dictionary = _check_dark_action_requirements(action_key)
	if not check.get("ok", false):
		dark_action_confirm.disabled = true
		var reason: String = String(check.get("reason", "Nelze seslat."))
		desc += "\n\nNelze seslat: %s" % reason
	else:
		dark_action_confirm.disabled = false

	dark_action_info.text = desc

func _build_dark_action_description(action_key: String) -> String:
	var def: Dictionary = Balance.DARK_ACTIONS.get(action_key, {})

	var name: String = def.get("display_name", action_key)
	var mana_cost: int = int(def.get("mana_cost", 0))
	var ap_cost: int = int(def.get("ap_cost", 0))

	var effects: Dictionary = def.get("effects", {})

	var lines: Array[String] = []
	lines.append(name)

	# jednoduché shrnutí nákladů
	var cost_parts: Array[String] = []
	if ap_cost > 0:
		cost_parts.append("AP: %d" % ap_cost)
	if mana_cost > 0:
		cost_parts.append("Mana: %d" % mana_cost)
	if not cost_parts.is_empty():
		lines.append("Náklady: " + ", ".join(cost_parts))

	# stručný popis efektů – jen základ
	var eff_parts: Array[String] = []

	if effects.has("gold"):
		var g: int = int(effects["gold"])
		if g > 0: eff_parts.append("+%d zlata" % g)

	if effects.has("mana"):
		var m: int = int(effects["mana"])
		if m > 0: eff_parts.append("+%d many" % m)

	if effects.has("heat"):
		var h: int = int(effects["heat"])
		if h > 0: eff_parts.append("+%d heat" % h)

	if effects.has("corruption"):
		var c: int = int(effects["corruption"])
		if c < 0:
			eff_parts.append("spálí %d korupce" % abs(c))

	if not eff_parts.is_empty():
		lines.append("Efekt: " + ", ".join(eff_parts))

	return "\n".join(lines)

func _update_mission_info() -> void:
	mission_info.text = ""

	var key: String = UIHelpers.get_selected_key(mission_select)
	if key == "":
		return

	var cfg: Dictionary = Balance.MISSION.get(key, {})
	if cfg.is_empty():
		return

	var name := String(cfg.get("display_name", key.capitalize()))
	var desc := String(cfg.get("description", ""))

	var cost: Dictionary = cfg.get("cost", {})
	var cost_str := ""
	if not cost.is_empty():
		var parts: Array[String] = []
		if int(cost.get("ap", 0)) != 0: parts.append("AP: %d" % int(cost["ap"]))
		if int(cost.get("mana", 0)) != 0: parts.append("Mana: %d" % int(cost["mana"]))
		if int(cost.get("gold", 0)) != 0: parts.append("Zlato: %d" % int(cost["gold"]))
		if not parts.is_empty():
			cost_str = "\nNáklady: " + ", ".join(parts)

	# šance – doporučený podpis: (key, unit, region)
	var uid: int = unit_select.get_selected_id()
	if uid == -1 or selected_region_idx < 0:
		return
	var unit: Unit = GameState.query.units.get_by_id(uid)
	var region: Region = GameState.query.regions.get_by_id(selected_region_idx)
	if unit == null or region == null:
		return

	# šance – breakdown
	var info: Dictionary = GameState.mission_manager.get_mission_success_info(key, unit, region)
	var base_c: float = float(info.get("base", 0.5))
	var region_delta: float = float(info.get("region_delta", 0.0))
	var unit_delta: float = float(info.get("unit_delta", 0.0))
	var total: float = float(info.get("chance", base_c))
	
	var lines: Array[String] = []
	lines.append("Šance: %d%%" % int(total * 100.0))
	
	# breakdown jen pokud je co ukazovat
	var have_modifiers := not is_equal_approx(region_delta, 0.0) or not is_equal_approx(unit_delta, 0.0)
	if have_modifiers:
		lines.append(" (base %d%%" % int(base_c * 100.0))
		if not is_equal_approx(region_delta, 0.0):
			var rd_pp: int = int(region_delta * 100.0)
			# „Inkvizitor v regionu: -50 %“ – zobecníme jako „Regionální modifikátory“
			lines.append(", region: %+d%%" % rd_pp)
		if not is_equal_approx(unit_delta, 0.0):
			var ud_pp: int = int(unit_delta * 100.0)
			lines.append(", jednotka: %+d%%" % ud_pp)
		lines.append(")")

	var chance_str = "\n" + "".join(lines)	

	#var chance: float = GameState.mission_manager.get_mission_success_chance(key, unit, region)
#
	#var chance_str := "\nŠance: %d%%" % int(chance * 100.0)

	mission_info.text = "%s\n%s%s%s" % [name, desc, cost_str, chance_str]

func _on_mission_resolved(result: Dictionary) -> void:
	var region_id: int = result.get("region_id", -1)
	if region_id < 0 or region_id >= grid.get_child_count():
		return

	var success: bool = result.get("success", false)
	var tile = grid.get_child(region_id)

	if tile.has_method("play_feedback"):
		tile.call_deferred("play_feedback", success)

func _build_grid() -> void:
	for child in grid.get_children():
		child.queue_free()

	for i in GameState.region_manager.regions.size():
		var r: Region = GameState.query.regions.get_by_id(i)
		var t: Control = tile_scene.instantiate()
		grid.add_child(t)
		t.call_deferred("setup", i, r) 
		t.connect("tile_selected", Callable(self, "_on_tile_selected"))

	_refresh_unit_positions()
	_refresh_region_colors()
	_refresh_tile_selection()

func _on_tile_selected(region_idx: int) -> void:
	selected_region_idx = region_idx
	_refresh_selected_panel()
	_refresh_tile_selection()

func _refresh_tile_selection() -> void:
	for i in grid.get_child_count():
		var tile = grid.get_child(i)
		var is_sel = (i == selected_region_idx)
		# voláme RegionTile.set_selected
		tile.call_deferred("set_selected", is_sel)

func _refresh_selected_panel() -> void:
	if selected_region_idx < 0 or selected_region_idx >= GameState.region_manager.regions.size():
		right_panel.visible = false
		return

	right_panel.visible = true
	var r: Region = GameState.query.regions.get_by_id(selected_region_idx)
	region_info.text = r.get_info_text()
	
	_build_dark_actions_menu()
	_populate_unit_select(selected_region_idx)
	_update_unit_info()  # na začátek nic/placeholder
	_build_mission_menu()  # dle vybrané jednotky (zatím žádná) -> disabled
	_build_neighbors_menu(selected_region_idx)

	# mise/move jsou vidět vždy, ale bez jednotky disabled
	_set_actions_enabled(unit_select.get_item_count() > 0 and unit_select.get_selected_id() != -1)

func _populate_unit_select(region_idx:int) -> void:
	unit_select.clear()
	unit_select.add_item("— vyber jednotku —", -1)
	var player_id = Balance.PLAYER_FACTION
	var first_index: int = -1
	var count: int = 0
	
	for u in GameState.query.units.in_region(region_idx, false):
		if u.faction_id == player_id and u.state == "healthy":
			var label := "%s (%s)" % [u.name, u.type]
			unit_select.add_item(label, u.id)
			count += 1
			if first_index == -1:
				# index v OptionButtonu (0 = placeholder, 1..count = jednotky)
				first_index = unit_select.get_item_count() - 1

	if count == 1 and first_index != -1:
		unit_select.select(first_index)
	else:
		unit_select.select(0)

func _update_unit_info() -> void:
	var uid = unit_select.get_selected_id()
	if uid == -1:
		unit_info.text = "Jednotka nevybrána."
		return
	var u = GameState.query.units.get_by_id(uid)
	if u == null:
		unit_info.text = "Jednotka nenalezena."
		return
	unit_info.text = "Jednotka: %s (%s) | Síla: %d | Zbývá tahů: %d" % [u.name, u.type, u.power, u.moves_left]

func _build_mission_menu(region_idx: int = selected_region_idx) -> void:
	var uid: int = unit_select.get_selected_id()
	if uid == -1:
		UIHelpers.set_single_placeholder(mission_select, "— vyber jednotku —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	var unit: Unit = GameState.query.units.get_by_id(uid)
	if unit == null:
		UIHelpers.set_single_placeholder(mission_select, "— žádná jednotka —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	if region_idx < 0 or region_idx >= GameState.region_manager.regions.size():
		UIHelpers.set_single_placeholder(mission_select, "— vyber region —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	var region: Region = GameState.query.regions.get_by_id(region_idx)
	if region == null:
		UIHelpers.set_single_placeholder(mission_select, "— region nenalezen —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	var keys: Array[String] = GameState.mission_manager.get_available_missions_for(unit, region)
	if keys.is_empty():
		UIHelpers.set_single_placeholder(mission_select, "— žádné mise pro tuto jednotku/region —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	# vyplň menu
	mission_select.clear()
	# placeholder nahoře (metadata = "")
	UIHelpers.add_option_with_key(mission_select, "— vyber misi —", "")

	for key in keys:
		var cfg: Dictionary = Balance.MISSION.get(key, {})
		if cfg.is_empty():
			continue
		var label: String = String(cfg.get("display_name", key.capitalize()))
		UIHelpers.add_option_with_key(mission_select, label, key)

	# vyber první skutečnou misi (index 1)
	mission_select.select(1)
	mission_confirm.disabled = false
	_update_mission_info()
			
func _build_neighbors_menu(region_idx:int) -> void:
	neighbor_select.clear()
	var neighbors = GameState.query.regions.neighbors(region_idx)
	if neighbors.is_empty():
		neighbor_select.add_item("— žádní sousedé —", -1)
		move_confirm.disabled = true
		return

	for n in neighbors:
		var rr: Region = GameState.query.regions.get_by_id(n)
		neighbor_select.add_item(rr.name, n)
	neighbor_select.select(0)
	move_confirm.disabled = false
	
func _set_actions_enabled(enabled: bool) -> void:
	mission_select.disabled = not enabled
	mission_confirm.disabled = not enabled
	# Move závisí na jednotce i sousedech, ale necháme vidět a jen disablovat:
	move_confirm.disabled = not enabled or neighbor_select.get_selected_id() == -1

func _on_unit_selected(_idx:int) -> void:
	_update_unit_info()
	_build_mission_menu()
	_set_actions_enabled(unit_select.get_selected_id() != -1)

func _on_mission_confirm() -> void:
	var uid := unit_select.get_selected_id()
	if uid == -1 or selected_region_idx == -1:
		return

	var key: String = UIHelpers.get_selected_key(mission_select)
	if key == "":
		return

	#GameState.plan_mission(uid, selected_region_idx, key)
	GameState.exec(GameState.commands.plan_mission(uid, selected_region_idx, key))

func _on_move_confirm() -> void:
	var uid = unit_select.get_selected_id()
	var target = neighbor_select.get_selected_id()
	if uid == -1 or target == -1:
		return
	#GameState.move_unit(uid, target)
	GameState.exec(GameState.commands.move_unit(uid, target))

func _on_turn_resolved() -> void:
	_refresh_region_colors()
	_refresh_unit_positions()
	_refresh_selected_panel()

func _refresh_region_colors() -> void:
	for i in GameState.region_manager.regions.size():
		var r: Region = GameState.query.regions.get_by_id(i)
		var tile = grid.get_child(i)

		if tile.has_method("refresh_from_region"):
			tile.call_deferred("refresh_from_region", r)

func _refresh_unit_positions() -> void:
	for i in GameState.region_manager.regions.size():
		var region_tile = grid.get_child(i)

		var units_here: Array = []
		var enemy_here: Array = []

		for u in GameState.query.units.in_region(i, false):
			if u.faction_id == Balance.PLAYER_FACTION:
				units_here.append(u)
			else:
				enemy_here.append(u)

		region_tile.call_deferred("update_units_display", units_here, enemy_here)

func _on_unit_moved(_unit_id: int, from_region: int, to_region: int) -> void:
	_refresh_unit_positions()
	_refresh_region_colors()
	if from_region < grid.get_child_count():
		grid.get_child(from_region).call_deferred("play_move_animation")
	if to_region < grid.get_child_count():
		grid.get_child(to_region).call_deferred("play_move_animation")

# --------------------------
# DARK ACTIONS UI

func _build_dark_actions_menu() -> void:
	dark_action_select.clear()

	var faction_id: String = Balance.PLAYER_FACTION
	var dam = GameState.dark_actions_manager
	var available_keys: Array[String] = dam.get_available_actions_for_faction(faction_id)

	# Filtr – zobrazujeme jen akce, které dávají smysl pro aktuální region
	var filtered: Array[String] = []
	for key in available_keys:
		var def: Dictionary = Balance.DARK_ACTIONS.get(key, {})
		var atype: String = String(def.get("type", "global"))

		if atype == "global":
			filtered.append(key)
		elif atype == "region":
			# regionové akce mají smysl jen pokud je vybraný region
			if selected_region_idx >= 0:
				filtered.append(key)

	if filtered.is_empty():
		UIHelpers.set_single_placeholder(dark_action_select, "Žádné temné akce")
		dark_action_select.disabled = true
		dark_action_confirm.disabled = true
		dark_action_info.text = ""
		return

	# Placeholder vždy první, key = ""
	UIHelpers.add_option_with_key(dark_action_select, "— vyber temnou akci —", "")

	for key in filtered:
		var def: Dictionary = Balance.DARK_ACTIONS.get(key, {})
		var name: String = String(def.get("display_name", key))
		UIHelpers.add_option_with_key(dark_action_select, name, key)

	# vyber první reálnou akci (index 1)
	dark_action_select.select(1)
	dark_action_select.disabled = false

	_update_dark_action_info()

func _on_dark_action_confirm() -> void:
	if dark_action_select.disabled:
		return

	var key: String = UIHelpers.get_selected_key(dark_action_select)
	if key == "":
		return

	# BEZPEČNOST: znovu ověř requirements
	var check := _check_dark_action_requirements(key)
	if not check.get("ok", false):
		var reason = String(check.get("reason", "Podmínky nejsou splněny."))
		GameState._log({"type":"warn", "text":"❌ Nelze seslat akci: %s" % reason})
		_update_dark_action_info()
		return

	var def:Dictionary = Balance.DARK_ACTIONS.get(key, {})
	var atype:String = String(def.get("type", "global"))

	var region_id:int = -1
	if atype == "region":
		if selected_region_idx < 0:
			GameState._log({"type":"warn", "text":"⚠ Není vybrán žádný region pro temnou akci."})
			return
		region_id = selected_region_idx

	#var res:Dictionary = GameState.dark_actions_manager.cast(Balance.PLAYER_FACTION, key, region_id)
	var res : Dictionary = GameState.exec(GameState.commands.cast_dark_action(key, region_id, Balance.PLAYER_FACTION))
	#if not res.get("ok", false):
		#var reason = String(res.get("reason", "Neznámý důvod."))
		#GameState._log({"type":"warn", "text":"❌ Nelze seslat akci: %s" % reason})
		#_update_dark_action_info()
		#return
#
	## 1) zaloguj vše (pokud DarkActionsManager vrací logs)
	#for e in res.get("logs", []):
		#GameState._log(e)
#
	## 2) zpracuj domain events (rebuilduje query, emituje unit_moved, atd.)
	#GameState._process_domain_events(res.get("events", []))

	# 3) refresh UI
	_build_dark_actions_menu()
	_update_dark_action_info()

	# region info přes query
	var r := GameState.query.regions.get_by_id(selected_region_idx)
	if r != null:
		region_info.text = r.get_info_text()
