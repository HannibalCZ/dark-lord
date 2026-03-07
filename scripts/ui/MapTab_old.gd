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
# NOVÉ – temné akce
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
	# tady řeš jen věci typu: přepočet panelu, změna textů, ale NE kompletní rebuild gridu
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

		var region: Region = GameState.region_manager.get_region(selected_region_idx)

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

	var sel_id: int = dark_action_select.get_selected_id()
	if sel_id == -1:
		dark_action_confirm.disabled = true
		return

	var key_variant = dark_action_select.get_item_metadata(sel_id)
	if key_variant == null:
		dark_action_confirm.disabled = true
		return

	var action_key: String = String(key_variant)
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

	var key: String = _get_selected_mission_key()
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
	var unit: Unit = GameState.unit_manager.get_unit(uid)
	var region: Region = GameState.region_manager.get_region(selected_region_idx)
	if unit == null or region == null:
		return
		
	var chance: float = GameState.mission_manager.get_mission_success_chance(key)

	var chance_str := "\nŠance: %d%%" % int(chance * 100.0)

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
		var r: Region = GameState.region_manager.regions[i]
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
	var r: Region = GameState.region_manager.regions[selected_region_idx]
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
	
	for u in GameState.unit_manager.units:
		if u.faction_id == player_id and u.state == "healthy" and u.region_id == region_idx:
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
	var u = GameState.unit_manager.get_unit(uid)
	if u == null:
		unit_info.text = "Jednotka nenalezena."
		return
	unit_info.text = "Jednotka: %s (%s) | Síla: %d | Zbývá tahů: %d" % [u.name, u.type, u.power, u.moves_left]

func _build_mission_menu(region_idx: int = selected_region_idx) -> void:
	mission_select.clear()

	# placeholder vždy s metadata ""
	mission_select.add_item("— vyber jednotku —")
	mission_select.set_item_metadata(0, "")
	mission_select.select(0)

	var uid: int = unit_select.get_selected_id()
	if uid == -1:
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	var unit: Unit = GameState.unit_manager.get_unit(uid)
	if unit == null:
		mission_select.set_item_text(0, "— žádná jednotka —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	if region_idx < 0 or region_idx >= GameState.region_manager.regions.size():
		mission_select.set_item_text(0, "— vyber region —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	var region: Region = GameState.region_manager.get_region(region_idx)
	if region == null:
		mission_select.set_item_text(0, "— region nenalezen —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	# ✅ klíčové: získej mission keys (data-driven)
	# Preferovaně přes MissionManager API:
	var keys: Array[String] = GameState.mission_manager.get_available_missions_for(unit, region)

	# Pokud ještě get_available_missions_for nemáš v keys, můžeš dočasně použít:
	# var keys: Array[String] = []
	# for k in Balance.MISSION.keys():
	# 	if unit.can_do_mission_key(k) and GameState.mission_manager.can_do_mission(unit, region, k):
	# 		keys.append(k)

	if keys.is_empty():
		mission_select.set_item_text(0, "— žádné mise pro tuto jednotku/region —")
		mission_confirm.disabled = true
		mission_info.text = ""
		return

	# přidej mise (bez id), metadata = key
	for k in keys:
		var cfg: Dictionary = Balance.MISSION.get(k, {})
		if cfg.is_empty():
			continue
		var label: String = String(cfg.get("display_name", k.capitalize()))

		mission_select.add_item(label)
		var idx: int = mission_select.get_item_count() - 1
		mission_select.set_item_metadata(idx, k)

	# vyber první skutečnou misi (index 1)
	mission_select.select(1)
	mission_confirm.disabled = false
	_update_mission_info()
			
func _build_neighbors_menu(region_idx:int) -> void:
	neighbor_select.clear()
	var neighbors = GameState.region_manager.adjacency.get(region_idx, [])
	if neighbors.is_empty():
		neighbor_select.add_item("— žádní sousedé —", -1)
		move_confirm.disabled = true
		return

	for n in neighbors:
		var rr: Region = GameState.region_manager.regions[n]
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

	var key := _get_selected_mission_key()
	if key == "":
		return

	GameState.plan_mission(uid, selected_region_idx, key)

func _on_move_confirm() -> void:
	var uid = unit_select.get_selected_id()
	var target = neighbor_select.get_selected_id()
	if uid == -1 or target == -1:
		return
	GameState.move_unit(uid, target)

func _on_turn_resolved() -> void:
	_refresh_region_colors()
	_refresh_unit_positions()
	_refresh_selected_panel()

func _refresh_region_colors() -> void:
	for i in GameState.region_manager.regions.size():
		var r: Region = GameState.region_manager.regions[i]
		var tile = grid.get_child(i)

		if tile.has_method("refresh_from_region"):
			tile.call_deferred("refresh_from_region", r)

func _refresh_unit_positions() -> void:
	for i in GameState.region_manager.regions.size():
		var region_tile = grid.get_child(i)
		var units_here = []
		for u in GameState.unit_manager.units:
			if u.region_id == i and u.state != "lost" and u.faction_id == Balance.PLAYER_FACTION:
				units_here.append(u)
		var enemy_here = []
		for u in GameState.unit_manager.units:
			if u.region_id == i and u.state != "lost" and u.faction_id != Balance.PLAYER_FACTION:
				enemy_here.append(u)
		region_tile.call_deferred("update_units_display", units_here, enemy_here)

func _on_unit_moved(_unit_id: int, from_region: int, to_region: int) -> void:
	_refresh_unit_positions()
	_refresh_region_colors()
	if from_region < grid.get_child_count():
		grid.get_child(from_region).call_deferred("play_move_animation")
	if to_region < grid.get_child_count():
		grid.get_child(to_region).call_deferred("play_move_animation")


func _get_faction_color(faction_id: String) -> String:
	match faction_id:
		"elf": return "4CAF50"      # zelená
		"paladin": return "CCAA44"  # zlatá
		"merchant": return "55AADD" # modrá
		"neutral": return "AAAAAA"   # šedá
		Balance.PLAYER_FACTION: return "440099"	# fialova
		_: return "FFFFFF"             # fallback bílá

# --------------------------
# DARK ACTIONS UI

func _build_dark_actions_menu() -> void:
	dark_action_select.clear()

	var faction_id = Balance.PLAYER_FACTION
	var dam = GameState.dark_actions_manager
	var available_keys:Array[String] = dam.get_available_actions_for_faction(faction_id)

	# Filtr – zobrazujeme jen akce, které dávají smysl pro aktuální region
	var filtered:Array[String] = []
	for key in available_keys:
		var def:Dictionary = Balance.DARK_ACTIONS.get(key, {})
		var atype:String = String(def.get("type", "global"))
		if atype == "global":
			filtered.append(key)
		elif atype == "region":
			# musí být vybraný region
			if selected_region_idx >= 0:
				filtered.append(key)

	if filtered.is_empty():
		dark_action_select.add_item("Žádné temné akce", -1)
		dark_action_select.disabled = true
		dark_action_confirm.disabled = true
		dark_action_info.text = ""  
		return

	var idx:int = 0
	for key in filtered:
		var def:Dictionary = Balance.DARK_ACTIONS.get(key, {})
		var name:String = def.get("display_name", key)
		dark_action_select.add_item(name, idx)
		dark_action_select.set_item_metadata(idx, key)
		idx += 1

	dark_action_select.select(0)
	dark_action_select.disabled = false
	dark_action_confirm.disabled = false

	_update_dark_action_info()

func _on_dark_action_confirm() -> void:
	if dark_action_select.disabled:
		return

	var sel_id:int = dark_action_select.get_selected_id()
	if sel_id == -1:
		return

	var key:String = String(dark_action_select.get_item_metadata(sel_id))
	if key == "":
		return

	# BEZPEČNOST: znovu ověř requirements
	var check := _check_dark_action_requirements(key)
	if not check.get("ok", false):
		var reason = String(check.get("reason", "Podmínky nejsou splněny."))
		Log_Manager.add({"type":"warn", "text":"❌ Nelze seslat akci: %s" % reason})
		_update_dark_action_info()
		return

	var def:Dictionary = Balance.DARK_ACTIONS.get(key, {})
	var atype:String = String(def.get("type", "global"))

	var region_id:int = -1
	if atype == "region":
		if selected_region_idx < 0:
			Log_Manager.add({"type":"warn", "text":"⚠ Není vybrán žádný region pro temnou akci."})
			return
		region_id = selected_region_idx

	var res:Dictionary = GameState.dark_actions_manager.cast(Balance.PLAYER_FACTION, key, region_id)
	if not res.get("ok", false):
		var reason = String(res.get("reason", "Neznámý důvod."))
		Log_Manager.add({"type":"warn", "text":"❌ Nelze seslat akci: %s" % reason})
	else:
		var display_name:String = def.get("display_name", key)
		Log_Manager.add({"type":"spell", "text":"🔮 Seslal jsi: %s" % display_name})

		# po seslání se změní cooldowny a AP → obnov menu
		_build_dark_actions_menu()
		_update_dark_action_info()
		# některé akce mohly změnit tagy/doom → aktualizujeme region info
		region_info.text = GameState.region_manager.get_region(selected_region_idx).get_info_text()

func _get_selected_mission_key() -> String:
	if mission_select.disabled:
		return ""

	var idx := mission_select.get_selected() # <-- INDEX, ne ID
	if idx < 0:
		return ""

	var meta : Variant = mission_select.get_item_metadata(idx) # <-- meta je Variant
	if meta == null:
		return ""

	# akceptuj String i StringName (Godot 4)
	if typeof(meta) == TYPE_STRING or typeof(meta) == TYPE_STRING_NAME:
		return str(meta)

	return ""
