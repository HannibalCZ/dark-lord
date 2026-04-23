extends Control

# --- Mapa ---
@onready var map_canvas: Control = $HBoxContainer/MapCanvas
@onready var map_content: Control = $HBoxContainer/MapCanvas/MapContent
@onready var connection_layer: Control = $HBoxContainer/MapCanvas/ConnectionLayer
@onready var right_panel: VBoxContainer = $HBoxContainer/RightPanel

# --- RegionSection ---
@onready var region_section: RegionSection = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/RegionSection

# --- ScrollContainer ---
@onready var scroll_container: ScrollContainer  = $HBoxContainer/RightPanel/ScrollContainer

# --- ActionsSection ---
@onready var actions_section: PanelContainer    = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection
@onready var dark_action_select: OptionButton   = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/DarkActionRow/DarkActionPicker
@onready var dark_action_confirm: Button        = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/DarkActionRow/DarkActionButton
@onready var dark_action_info: Label            = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/DarkActionDesc
@onready var unit_info: Label                   = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/UnitInfo
@onready var mission_select: OptionButton       = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/MissionRow/MissionPicker
@onready var mission_confirm: Button            = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/MissionRow/MissionButton
@onready var mission_info: Label                = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/MissionInfo
@onready var selected_unit_label: Label         = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/SelectedUnitLabel
@onready var deselect_btn: Button               = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/ActionsSection/VBoxContainer/DeselectBtn

# --- OrgSection ---
@onready var org_section: PanelContainer  = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/OrgSection
@onready var org_name: Label              = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/OrgSection/VBoxContainer/OrgHeader/OrgName
@onready var org_owner: Label             = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/OrgSection/VBoxContainer/OrgHeader/OrgOwner
@onready var doctrine_picker: OptionButton = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/OrgSection/VBoxContainer/DoctrinePicker
@onready var doctrine_effects: Label      = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/OrgSection/VBoxContainer/DoctrineEffects
@onready var destroy_button: Button       = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/OrgSection/VBoxContainer/DestroyButton
@onready var org_loyalty_label: Label     = $HBoxContainer/RightPanel/ScrollContainer/ScrollContent/OrgSection/VBoxContainer/OrgLoyaltyLabel

var org_visibility_label: Label = null   # vytvoren dynamicky v _ready()

var _tile_by_id: Dictionary = {}  # { region_id: int -> RegionTile }
var _connections: Array = []      # [ {a: Vector2, b: Vector2}, ... ]
var selected_region_idx: int = -1
var _selected_unit_id: int = -1
# parallel array — uchovává doctrine key pro každý item v doctrine_picker
var _doctrine_keys: Array[String] = []
var _current_movement_target_tile = null
var _highlighted_neighbor_tiles: Array = []
var _movement_in_progress: bool = false
var tile_scene: PackedScene = preload("res://scenes/ui/RegionTile.tscn")

const SCROLL_SPEED    := 250.0
const EDGE_MARGIN     := 40.0
const TILE_SIZE_PX    := Vector2(128.0, 128.0)
var _content_rect     := Rect2()
var _initial_center_done: bool = false

var mission_success_effects: Label
var mission_fail_effects: Label

func _ready() -> void:
	# Pozadi sekcí
	var bg_actions := StyleBoxFlat.new()
	bg_actions.bg_color = Color("#16213e")
	bg_actions.content_margin_left   = 12.0
	bg_actions.content_margin_right  = 12.0
	bg_actions.content_margin_top    = 12.0
	bg_actions.content_margin_bottom = 12.0
	actions_section.add_theme_stylebox_override("panel", bg_actions)

	var bg_org := StyleBoxFlat.new()
	bg_org.bg_color = Color("#1a2535")
	bg_org.content_margin_left   = 12.0
	bg_org.content_margin_right  = 12.0
	bg_org.content_margin_top    = 12.0
	bg_org.content_margin_bottom = 12.0
	org_section.add_theme_stylebox_override("panel", bg_org)

	connection_layer.draw.connect(_on_connection_layer_draw)
	_build_grid()

	# signály — akce
	mission_confirm.pressed.connect(_on_mission_confirm)
	dark_action_confirm.pressed.connect(_on_dark_action_confirm)
	dark_action_select.item_selected.connect(_on_dark_action_selected)
	mission_select.item_selected.connect(_on_mission_selected)
	deselect_btn.pressed.connect(func(): _select_unit(-1))

	# signály — org sekce
	doctrine_picker.item_selected.connect(_on_doctrine_picker_item_selected)
	destroy_button.pressed.connect(_on_destroy_button_pressed)

	GameState.connect("unit_moved", Callable(self, "_on_unit_moved"))
	GameState.connect("turn_resolved", Callable(self, "_on_turn_resolved"))
	GameState.connect("game_updated", Callable(self, "_on_game_updated"))

	EventBus.connect("mission_resolved", Callable(self, "_on_mission_resolved"))

	# EventBus — org zmeny refreshuji OrgSection
	EventBus.org_founded.connect(_on_org_changed)
	EventBus.org_destroyed.connect(_on_org_changed)
	EventBus.org_doctrine_changed.connect(_on_doctrine_externally_changed)

	right_panel.visible = false
	_set_actions_enabled(false)
	org_section.visible = false

	mission_success_effects = Label.new()
	mission_success_effects.name = "MissionSuccessEffects"
	mission_success_effects.add_theme_font_size_override("font_size", 11)
	mission_success_effects.add_theme_color_override("font_color", Color("#4caf50"))
	mission_success_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_success_effects.visible = false

	mission_fail_effects = Label.new()
	mission_fail_effects.name = "MissionFailEffects"
	mission_fail_effects.add_theme_font_size_override("font_size", 11)
	mission_fail_effects.add_theme_color_override("font_color", Color("#f44336"))
	mission_fail_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_fail_effects.visible = false

	var _mission_parent: Node = mission_info.get_parent()
	_mission_parent.add_child(mission_success_effects)
	_mission_parent.add_child(mission_fail_effects)
	var _mi_idx: int = mission_info.get_index()
	_mission_parent.move_child(mission_success_effects, _mi_idx + 1)
	_mission_parent.move_child(mission_fail_effects, _mi_idx + 2)

	# Org visibility label — pridano dynamicky za org_loyalty_label
	org_visibility_label = Label.new()
	org_visibility_label.name = "OrgVisibilityLabel"
	org_visibility_label.add_theme_font_size_override("font_size", 12)
	org_visibility_label.visible = false
	var _org_vbox: Node = org_loyalty_label.get_parent()
	_org_vbox.add_child(org_visibility_label)
	_org_vbox.move_child(org_visibility_label, org_loyalty_label.get_index() + 1)

	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	set_process(is_visible_in_tree())

func _process(delta: float) -> void:
	_handle_scroll(delta)

func _handle_scroll(delta: float) -> void:
	var dir := Vector2.ZERO

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y -= 1.0

	var mouse := get_viewport().get_mouse_position()
	var canvas_rect := map_canvas.get_global_rect()
	if canvas_rect.has_point(mouse):
		if mouse.x < canvas_rect.position.x + EDGE_MARGIN:
			dir.x += 1.0
		elif mouse.x > canvas_rect.end.x - EDGE_MARGIN:
			dir.x -= 1.0
		if mouse.y < canvas_rect.position.y + EDGE_MARGIN:
			dir.y += 1.0
		elif mouse.y > canvas_rect.end.y - EDGE_MARGIN:
			dir.y -= 1.0

	if dir == Vector2.ZERO:
		return

	map_content.position += dir * SCROLL_SPEED * delta
	_clamp_map_content()
	connection_layer.queue_redraw()

func _clamp_map_content() -> void:
	if _content_rect.size == Vector2.ZERO:
		return
	var cs := map_canvas.size
	map_content.position = Vector2(
		clamp(map_content.position.x,
			EDGE_MARGIN - _content_rect.end.x,
			cs.x - EDGE_MARGIN - _content_rect.position.x),
		clamp(map_content.position.y,
			EDGE_MARGIN - _content_rect.end.y,
			cs.y - EDGE_MARGIN - _content_rect.position.y)
	)

func _compute_map_bounds() -> void:
	if _tile_by_id.is_empty():
		_content_rect = Rect2()
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for tile: Control in _tile_by_id.values():
		mn = mn.min(tile.position)
		mx = mx.max(tile.position + TILE_SIZE_PX)
	_content_rect = Rect2(mn, mx - mn)

func _center_on_player_start() -> void:
	if _initial_center_done:
		return
	var start_id: int = GameState.player_start_region_id
	var region = GameState.query.regions.get_by_id(start_id)
	if region == null:
		return
	if map_canvas.size == Vector2.ZERO:
		return
	_initial_center_done = true
	var canvas_center: Vector2 = map_canvas.size / 2.0
	var region_pos: Vector2 = Vector2(region.position)
	var target: Vector2 = canvas_center - region_pos
	map_content.position = target
	_clamp_map_content()

func _on_game_updated() -> void:
	if _movement_in_progress:
		return
	if _tile_by_id.size() != GameState.region_manager.regions.size():
		_build_grid()
		return
	_refresh_unit_positions()
	_refresh_selected_panel()
	_refresh_org_indicators()

func _refresh_org_indicators() -> void:
	for region_id in _tile_by_id:
		var tile = _tile_by_id[region_id]
		var org: Dictionary = GameState.org_manager.get_org_in_region(region_id)
		var has_org: bool = not org.is_empty()
		var is_rogue: bool = org.get("is_rogue", false)
		var is_neutral: bool = has_org and org.get("owner", "") != Balance.PLAYER_FACTION
		# is_hidden: hracova org ktera jeste nebyla odhalena
		var is_hidden: bool = has_org \
				and not is_neutral \
				and not is_rogue \
				and not org.get("visible", true)
		tile.set_org_indicator(has_org, is_rogue, is_neutral, is_hidden)

func _on_mission_selected(_idx: int) -> void:
	_update_mission_info()

func _on_dark_action_selected(_idx: int) -> void:
	_update_dark_action_info()
	_refresh_actions()

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

func _refresh_actions() -> void:
	# Pokud je dropdown disabled (žádné dostupné akce), confirm zůstane disabled
	if dark_action_select.disabled:
		dark_action_confirm.disabled = true
		dark_action_confirm.tooltip_text = ""
		dark_action_confirm.modulate = Color(1, 1, 1, 0.4)
		return

	var action_key: String = UIHelpers.get_selected_key(dark_action_select)
	if action_key == "":
		# Vybrán placeholder — žádná akce nevybrána
		dark_action_confirm.disabled = true
		dark_action_confirm.tooltip_text = ""
		dark_action_confirm.modulate = Color(1, 1, 1, 0.4)
		return

	# 1) Zkontroluj requirements specifické pro region (korupční fáze atd.)
	var req_check: Dictionary = _check_dark_action_requirements(action_key)
	if not req_check.get("ok", false):
		dark_action_confirm.disabled = true
		dark_action_confirm.tooltip_text = String(req_check.get("reason", "Nelze seslat."))
		dark_action_confirm.modulate = Color(1, 1, 1, 0.4)
		return

	# 2) Zkontroluj can_cast: AP, mana, zlato, cooldown, agent atd.
	var cast_check: Dictionary = GameState.dark_actions_manager.can_cast(
		Balance.PLAYER_FACTION,
		action_key,
		selected_region_idx
	)
	if not cast_check.get("ok", false):
		dark_action_confirm.disabled = true
		dark_action_confirm.tooltip_text = String(cast_check.get("reason", "Nelze seslat."))
		dark_action_confirm.modulate = Color(1, 1, 1, 0.4)
		return

	# Vše v pořádku — akce je použitelná
	dark_action_confirm.disabled = false
	dark_action_confirm.tooltip_text = ""
	dark_action_confirm.modulate = Color(1, 1, 1, 1.0)

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

	var effects_str: String = _format_effects(effects)
	if effects_str != "":
		lines.append("Efekt: " + effects_str)
	else:
		lines.append("Efekt: žádný viditelný efekt")

	return "\n".join(lines)

func _update_mission_info() -> void:
	mission_info.text = ""
	mission_success_effects.visible = false
	mission_fail_effects.visible = false

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
	var uid: int = _selected_unit_id
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
			lines.append(", region: %+d%%" % rd_pp)
		if not is_equal_approx(unit_delta, 0.0):
			var ud_pp: int = int(unit_delta * 100.0)
			lines.append(", jednotka: %+d%%" % ud_pp)
		lines.append(")")

	var chance_str = "\n" + "".join(lines)

	mission_info.text = "%s\n%s%s%s" % [name, desc, cost_str, chance_str]

	var success_fx: Dictionary = cfg.get("success", {})
	var fail_fx: Dictionary    = cfg.get("fail", {})
	mission_success_effects.text    = "Uspech: %s" % _format_effects_preview(success_fx)
	mission_fail_effects.text       = "Neuspech: %s" % _format_effects_preview(fail_fx)
	mission_success_effects.visible = true
	mission_fail_effects.visible    = true

func _format_effects_preview(effects: Dictionary) -> String:
	var parts: Array[String] = []
	if effects.has("gold") and effects["gold"] != 0:
		parts.append("%+d zlato" % effects["gold"])
	if effects.has("mana") and effects["mana"] != 0:
		parts.append("%+d mana" % effects["mana"])
	if effects.has("heat") and effects["heat"] != 0:
		parts.append("%+d heat" % effects["heat"])
	if effects.has("awareness") and effects["awareness"] != 0:
		parts.append("%+d awareness" % effects["awareness"])
	if effects.has("infamy") and effects["infamy"] != 0:
		parts.append("%+d infamy" % effects["infamy"])
	if effects.has("defense") and effects["defense"] != 0:
		parts.append("%+d obrana" % effects["defense"])
	if effects.has("corruption") and effects["corruption"] != 0:
		parts.append("%+d korupce" % effects["corruption"])
	if effects.has("purge_corruption_all") and effects["purge_corruption_all"] != 0:
		parts.append("ocista korupce (%+d)" % effects["purge_corruption_all"])
	if effects.has("secret_progress") and effects["secret_progress"] != 0:
		parts.append("postup patrani +%d" % effects["secret_progress"])
	if effects.has("lair_influence") and effects["lair_influence"] != 0:
		parts.append("vliv v doupeti +%d" % effects["lair_influence"])
	if parts.is_empty():
		return "zadny efekt"
	return ", ".join(parts)

func _on_mission_resolved(result: Dictionary) -> void:
	var region_id: int = result.get("region_id", -1)
	var tile = _tile_by_id.get(region_id)
	if tile == null:
		return

	var success: bool = result.get("success", false)
	if tile.has_method("play_feedback"):
		tile.call_deferred("play_feedback", success)

func _build_grid() -> void:
	for child in map_content.get_children():
		child.queue_free()
	_tile_by_id.clear()

	for i in GameState.region_manager.regions.size():
		var r: Region = GameState.query.regions.get_by_id(i)
		var t: Control = tile_scene.instantiate()
		map_content.add_child(t)
		t.position = Vector2(r.position) - Vector2(64, 64)
		t.call_deferred("setup", i, r)
		t.connect("tile_selected", Callable(self, "_on_tile_selected"))
		_tile_by_id[i] = t

	_compute_map_bounds()
	call_deferred("_center_on_player_start")
	_refresh_unit_positions()
	_refresh_region_colors()
	_refresh_tile_selection()
	_draw_connections()
	_refresh_borders()
	_refresh_org_indicators()

func _on_tile_selected(region_idx: int) -> void:
	# Pohybový check — má přednost před vším ostatním
	if _selected_unit_id != -1 and _is_movement_target(region_idx):
		_execute_move_to(region_idx)
		return

	_clear_all_movement_highlights()

	var player_units: Array = _get_player_units_in_region(region_idx)

	# Cyklování — klik na stejný region kde je vybraná jednotka a je jich víc
	if region_idx == selected_region_idx \
			and _selected_unit_id != -1 \
			and player_units.size() > 1:
		var current_idx: int = -1
		for i in player_units.size():
			if player_units[i].id == _selected_unit_id:
				current_idx = i
				break
		var next_idx: int = (current_idx + 1) % player_units.size()
		selected_region_idx = region_idx
		_refresh_selected_panel()
		_select_unit(player_units[next_idx].id)
		_refresh_tile_selection()
		return

	# Nový region — auto-vyber první jednotku
	selected_region_idx = region_idx
	_refresh_selected_panel()
	_refresh_tile_selection()

	if player_units.size() > 0:
		_select_unit(player_units[0].id)
	else:
		_select_unit(-1)

func _refresh_tile_selection() -> void:
	for i in _tile_by_id:
		var tile = _tile_by_id[i]
		var is_sel = (i == selected_region_idx)
		tile.call_deferred("set_selected", is_sel)

func _refresh_selected_panel() -> void:
	if selected_region_idx < 0 or selected_region_idx >= GameState.region_manager.regions.size():
		right_panel.visible = false
		return

	right_panel.visible = true
	region_section.show_for_region(selected_region_idx)

	_build_dark_actions_menu()
	_update_unit_info()
	_build_mission_menu()

	_update_org_section(selected_region_idx)
	_set_actions_enabled(_selected_unit_id != -1)
	scroll_container.scroll_vertical = 0

# --------------------------
# UNIT + MISE

func _update_unit_info() -> void:
	var uid = _selected_unit_id
	if uid == -1:
		unit_info.text = "Jednotka nevybrána."
		return
	var u = GameState.query.units.get_by_id(uid)
	if u == null:
		unit_info.text = "Jednotka nenalezena."
		return
	unit_info.text = "Jednotka: %s (%s) | Síla: %d | Zbývá tahů: %d" % [u.name, u.type, u.power, u.moves_left]

func _build_mission_menu(region_idx: int = selected_region_idx) -> void:
	mission_success_effects.visible = false
	mission_fail_effects.visible = false
	var uid: int = _selected_unit_id
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

	mission_select.clear()
	UIHelpers.add_option_with_key(mission_select, "— vyber misi —", "")

	for key in keys:
		var cfg: Dictionary = Balance.MISSION.get(key, {})
		if cfg.is_empty():
			continue
		var label: String = String(cfg.get("display_name", key.capitalize()))
		UIHelpers.add_option_with_key(mission_select, label, key)

	mission_select.select(1)
	mission_confirm.disabled = false
	_update_mission_info()

func _set_actions_enabled(enabled: bool) -> void:
	mission_select.disabled = not enabled
	mission_confirm.disabled = not enabled

func _on_mission_confirm() -> void:
	var uid := _selected_unit_id
	if uid == -1 or selected_region_idx == -1:
		return

	var key: String = UIHelpers.get_selected_key(mission_select)
	if key == "":
		return

	GameState.exec(GameState.commands.plan_mission(uid, selected_region_idx, key))

func _clear_movement_target_highlight() -> void:
	if _current_movement_target_tile != null:
		_current_movement_target_tile.set_movement_target(false)
		_current_movement_target_tile = null

func _clear_all_movement_highlights() -> void:
	for tile in _highlighted_neighbor_tiles:
		tile.set_movement_target(false)
	_highlighted_neighbor_tiles.clear()
	_current_movement_target_tile = null

func _get_player_units_in_region(region_id: int) -> Array:
	var units: Array = []
	for u in GameState.query.units.in_region(region_id, false):
		if u.faction_id == Balance.PLAYER_FACTION and u.state == "healthy":
			units.append(u)
	return units

func _select_unit(unit_id: int) -> void:
	_selected_unit_id = unit_id
	_clear_all_movement_highlights()
	if unit_id == -1:
		_update_selected_unit_display(null)
		return
	var u: Unit = GameState.query.units.get_by_id(unit_id)
	if u == null:
		_selected_unit_id = -1
		_update_selected_unit_display(null)
		return
	_update_selected_unit_display(u)
	_update_unit_info()
	_highlight_available_neighbors(u.region_id)
	_build_mission_menu()
	_update_mission_info()

func _highlight_available_neighbors(region_id: int) -> void:
	_clear_all_movement_highlights()
	var u: Unit = GameState.query.units.get_by_id(_selected_unit_id)
	if u == null or u.moves_left <= 0:
		return
	var neighbors = GameState.query.regions.neighbors(region_id)
	for neighbor_id in neighbors:
		var tile = _tile_by_id.get(neighbor_id)
		if tile != null:
			tile.set_movement_target(true)
			_highlighted_neighbor_tiles.append(tile)

func _update_selected_unit_display(u: Unit) -> void:
	if u == null:
		selected_unit_label.visible = false
		deselect_btn.visible = false
		return
	selected_unit_label.text = "%s | Sila: %d | Tahy: %d" % [u.unit_key, u.power, u.moves_left]
	selected_unit_label.visible = true
	deselect_btn.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey \
			and event.keycode == KEY_ESCAPE \
			and event.pressed:
		_select_unit(-1)

func _is_movement_target(region_id: int) -> bool:
	for tile in _highlighted_neighbor_tiles:
		if tile.region_id == region_id:
			return true
	return false

func _execute_move_to(target_region_id: int) -> void:
	var uid: int = _selected_unit_id
	if uid == -1:
		return

	# Nastav PRED exec() aby interni game_updated videl spravny region
	selected_region_idx = target_region_id
	_movement_in_progress = true
	var result = GameState.exec(
			GameState.commands.move_unit(uid, target_region_id))
	_movement_in_progress = false

	if not result.get("ok", false):
		selected_region_idx = -1
		_select_unit(-1)
		return

	_clear_all_movement_highlights()

	var u: Unit = GameState.query.units.get_by_id(uid)

	if u != null and u.moves_left > 0:
		_highlight_available_neighbors(u.region_id)
	else:
		_select_unit(-1)

	GameState.game_updated.emit()

func _on_turn_resolved() -> void:
	_refresh_region_colors()
	_refresh_unit_positions()
	_refresh_borders()
	_refresh_selected_panel()

func _refresh_region_colors() -> void:
	for i in _tile_by_id:
		var r: Region = GameState.query.regions.get_by_id(i)
		var tile = _tile_by_id[i]
		if tile.has_method("refresh_from_region"):
			tile.call_deferred("refresh_from_region", r)

func _refresh_borders() -> void:
	for region_id in _tile_by_id:
		var r: Region = GameState.query.regions.get_by_id(region_id)
		var tile = _tile_by_id[region_id]
		tile.set_owner_border(r.owner_faction_id)

func _draw_connections() -> void:
	_connections.clear()
	var drawn: Dictionary = {}
	for region_id in _tile_by_id:
		var r: Region = GameState.query.regions.get_by_id(region_id)
		var neighbors: Array[int] = GameState.query.regions.neighbors(region_id)
		for neighbor_id in neighbors:
			var key: int = min(region_id, neighbor_id) * 1000 + max(region_id, neighbor_id)
			if drawn.has(key):
				continue
			drawn[key] = true
			var neighbor_r: Region = GameState.query.regions.get_by_id(neighbor_id)
			_connections.append({"a": Vector2(r.position), "b": Vector2(neighbor_r.position)})
	connection_layer.queue_redraw()

func _on_connection_layer_draw() -> void:
	var offset := map_content.position
	for conn in _connections:
		connection_layer.draw_line(conn["a"] + offset, conn["b"] + offset, Color(0.4, 0.4, 0.5, 0.6), 2.0, true)

func _refresh_unit_positions() -> void:
	for i in _tile_by_id:
		var region_tile = _tile_by_id[i]

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
	var from_tile = _tile_by_id.get(from_region)
	if from_tile != null:
		from_tile.call_deferred("play_move_animation")
	var to_tile = _tile_by_id.get(to_region)
	if to_tile != null:
		to_tile.call_deferred("play_move_animation")

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
			if selected_region_idx >= 0:
				filtered.append(key)

	if filtered.is_empty():
		UIHelpers.set_single_placeholder(dark_action_select, "Žádné temné akce")
		dark_action_select.disabled = true
		dark_action_confirm.disabled = true
		dark_action_info.text = ""
		return

	UIHelpers.add_option_with_key(dark_action_select, "— vyber temnou akci —", "")

	for key in filtered:
		var def: Dictionary = Balance.DARK_ACTIONS.get(key, {})
		var name: String = String(def.get("display_name", key))
		UIHelpers.add_option_with_key(dark_action_select, name, key)

	dark_action_select.select(1)
	dark_action_select.disabled = false

	_update_dark_action_info()
	_refresh_actions()

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
		GameState._log({"type": "warn", "text": "Nelze seslat akci: %s" % reason})
		_update_dark_action_info()
		return

	var def: Dictionary = Balance.DARK_ACTIONS.get(key, {})
	var atype: String = String(def.get("type", "global"))

	var region_id: int = -1
	if atype == "region":
		if selected_region_idx < 0:
			GameState._log({"type": "warn", "text": "Není vybrán žádný region pro temnou akci."})
			return
		region_id = selected_region_idx

	var _res: Dictionary = GameState.exec(GameState.commands.cast_dark_action(key, region_id, Balance.PLAYER_FACTION))

	# refresh UI — _build_dark_actions_menu() volá _update_dark_action_info() + _refresh_actions() interně
	_build_dark_actions_menu()
	region_section.show_for_region(selected_region_idx)

# --------------------------
# ORG SECTION

func _update_org_section(region_id: int) -> void:
	var data: Dictionary = GameState.org_manager.get_org_display_data(region_id)
	if not data.get("has_org", false):
		org_section.visible = false
		org_loyalty_label.visible = false
		return

	org_section.visible = true
	org_name.text = data["display_name"]

	if data["is_player_org"]:
		org_owner.visible = false
		destroy_button.visible = false
		doctrine_picker.visible = true
		doctrine_effects.visible = true
		_populate_doctrine_picker(region_id)
	else:
		org_owner.visible = true
		org_owner.text = _format_owner(data["owner"])
		doctrine_picker.visible = false
		doctrine_effects.visible = false
		destroy_button.visible = true

	# Loajalita — cti primo z org Dictionary, ne z display_data
	var org: Dictionary = GameState.org_manager.get_org_in_region(region_id)
	var loyalty: int = org.get("loyalty", Balance.ORG_LOYALTY_START)
	var is_rogue: bool = org.get("is_rogue", false)

	var phase_text: String
	var phase_color: Color
	if is_rogue:
		phase_text = "Rogue"
		phase_color = Color("#888888")
	elif loyalty >= Balance.ORG_LOYALTY_FAITHFUL:
		phase_text = "Verna"
		phase_color = Color("#4caf50")
	elif loyalty >= Balance.ORG_LOYALTY_STABLE:
		phase_text = "Stabilni"
		phase_color = Color("#ffd700")
	else:
		phase_text = "Nestabilni"
		phase_color = Color("#f44336")

	org_loyalty_label.text = "%d — %s" % [loyalty, phase_text]
	org_loyalty_label.add_theme_color_override("font_color", phase_color)
	org_loyalty_label.visible = true

	# Viditelnost organizace — zobrazit pouze pro hracovy orgy
	if org_visibility_label != null and data["is_player_org"]:
		var is_visible_to_enemy: bool = org.get("visible", false)
		if is_visible_to_enemy:
			org_visibility_label.text = "Stav: Odhalena"
			org_visibility_label.add_theme_color_override(
				"font_color", Color("#f44336"))
		else:
			org_visibility_label.text = "Stav: Skryta"
			org_visibility_label.add_theme_color_override(
				"font_color", Color("#4caf50"))
		org_visibility_label.visible = true
	elif org_visibility_label != null:
		org_visibility_label.visible = false


func _populate_doctrine_picker(region_id: int) -> void:
	doctrine_picker.clear()
	_doctrine_keys.clear()
	var doctrines: Array[Dictionary] = GameState.org_manager.get_available_doctrines(region_id)
	var current_idx: int = 0
	for i in doctrines.size():
		var d: Dictionary = doctrines[i]
		doctrine_picker.add_item(d["display_name"])
		_doctrine_keys.append(d["key"])
		if d["is_current"]:
			current_idx = i
	doctrine_picker.select(current_idx)
	_update_doctrine_effects(region_id)


func _update_doctrine_effects(region_id: int) -> void:
	var doctrines: Array[Dictionary] = GameState.org_manager.get_available_doctrines(region_id)
	var selected: int = doctrine_picker.selected
	if selected < 0 or selected >= doctrines.size():
		doctrine_effects.text = ""
		return
	doctrine_effects.text = _format_org_effects(doctrines[selected]["effects"])


func _format_owner(owner: String) -> String:
	match owner:
		Balance.ORG_OWNER_ROGUE:   return "Odpadlicka organizace"
		Balance.ORG_OWNER_NEUTRAL: return "Nezavisla organizace"
		Balance.ORG_OWNER_RIVAL:   return "Rivalitni Temny pan"
		_: return owner


func _format_org_effects(effects: Dictionary) -> String:
	var parts: Array[String] = []
	if effects.has("gold"):
		parts.append("%+d zlato/tah" % int(effects["gold"]))
	if effects.has("mana"):
		parts.append("%+d mana/tah" % int(effects["mana"]))
	if effects.has("heat"):
		parts.append("%+d heat/tah" % int(effects["heat"]))
	if effects.has("awareness"):
		parts.append("%+d awareness/tah" % int(effects["awareness"]))
	if effects.has("mission_bonus"):
		parts.append("+%d%% sance na mise" % int(effects["mission_bonus"]))
	if effects.get("dark_action_empowered", false):
		parts.append("Dark Actions zesíleny")
	if parts.is_empty():
		return "Žádné pasivní efekty"
	return "  ".join(parts)


func _format_effects(effects: Dictionary) -> String:
	if effects.is_empty():
		return ""
	var parts: Array[String] = []
	for key in effects:
		var val = effects[key]
		match key:
			"heat":
				parts.append("%+d Heat" % int(val))
			"awareness":
				parts.append("%+d Zájem" % int(val))
			"gold":
				parts.append("%+d zlato" % int(val))
			"mana":
				parts.append("%+d mana" % int(val))
			"infamy":
				parts.append("%+d Infamy" % int(val))
			"corruption":
				parts.append("%+d Korupce" % int(val))
			"org_loyalty":
				parts.append("%+d Loajalita" % int(val))
			"destroy_org":
				if val:
					parts.append("Zničí organizaci")
			"kill_unit":
				if val:
					parts.append("Eliminuje jednotku")
	return ", ".join(parts)


func _on_doctrine_picker_item_selected(index: int) -> void:
	if index < 0 or index >= _doctrine_keys.size():
		return
	var new_key: String = _doctrine_keys[index]
	var current: Dictionary = GameState.org_manager.get_org_display_data(selected_region_idx)
	if new_key == current.get("doctrine_key", ""):
		return  # žádná změna
	GameState.org_manager.set_doctrine(selected_region_idx, new_key)
	_update_doctrine_effects(selected_region_idx)


func _on_destroy_button_pressed() -> void:
	var uid: int = _selected_unit_id
	if uid == -1 or selected_region_idx < 0:
		GameState._log({"type": "warn", "text": "Vyberte jednotku schopnou provest purge."})
		return
	GameState.exec(GameState.commands.plan_mission(uid, selected_region_idx, "purge"))


func _on_org_changed(_ignored) -> void:
	if selected_region_idx >= 0:
		_update_org_section(selected_region_idx)


func _on_doctrine_externally_changed(region_id: int, _doctrine: String) -> void:
	if region_id == selected_region_idx:
		_populate_doctrine_picker(region_id)


