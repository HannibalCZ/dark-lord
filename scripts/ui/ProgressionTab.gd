extends Control

const COLOR_UNLOCKED  = Color("#4caf50")
const COLOR_AVAILABLE = Color("#ffd700")
const COLOR_LOCKED    = Color("#555555")

@onready var rp_label: Label = $VBoxContainer/TopBar/RPLabel
@onready var tree_container: VBoxContainer = $VBoxContainer/TreeScroll/TreeContainer

func _ready() -> void:
	GameState.game_updated.connect(_on_game_updated)
	EventBus.progression_node_unlocked.connect(_on_node_unlocked)
	_build_tree()
	_refresh_rp()

func _on_game_updated() -> void:
	_refresh_rp()
	_refresh_node_states()

func _on_node_unlocked(_faction_id: String, _node_key: String) -> void:
	_refresh_rp()
	_refresh_node_states()


# ---------------------------------------------------------
# Build
# ---------------------------------------------------------

func _build_tree() -> void:
	for child in tree_container.get_children():
		child.queue_free()

	for tier in range(1, 6):
		var tier_label := Label.new()
		tier_label.text = _tier_display_name(tier)
		if tier == 5:
			tier_label.add_theme_font_size_override("font_size", 18)
			tier_label.add_theme_color_override("font_color", Color("#ff6b35"))
		else:
			tier_label.add_theme_font_size_override("font_size", 13)
			tier_label.add_theme_color_override("font_color", Color("#cccccc"))
		tree_container.add_child(tier_label)

		# Skupiny uzlu podle větve pro dany tier
		var branch_groups: Dictionary = {}
		for key in Balance.PROGRESSION:
			var node_def: Dictionary = Balance.PROGRESSION[key]
			if int(node_def.get("tier", 0)) != tier:
				continue
			var branch: String = node_def.get("branch", "common")
			if not branch_groups.has(branch):
				branch_groups[branch] = []
			branch_groups[branch].append(key)

		var sorted_branches: Array = branch_groups.keys()
		sorted_branches.sort()

		for branch in sorted_branches:
			if branch != "common":
				var branch_label := Label.new()
				branch_label.text = _branch_display_name(branch)
				branch_label.add_theme_font_size_override("font_size", 10)
				branch_label.add_theme_color_override("font_color", _branch_color(branch))
				tree_container.add_child(branch_label)

			var tier_row := HBoxContainer.new()
			tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
			tier_row.add_theme_constant_override("separation", 8)
			for node_key in branch_groups[branch]:
				var node_btn := _create_node_button(node_key)
				tier_row.add_child(node_btn)
			tree_container.add_child(tier_row)

		if tier < 5:
			var sep := HSeparator.new()
			tree_container.add_child(sep)


func _tier_display_name(tier: int) -> String:
	match tier:
		1: return "Tier 1 — Spolecny zaklad"
		2: return "Tier 2 — Podmíneny zaklad"
		3: return "Tier 3 — Specializace"
		4: return "Tier 4 — Hluboka specializace"
		5: return "Tier 5 — Apotheoza"
		_: return "Tier %d" % tier


func _branch_display_name(branch: String) -> String:
	match branch:
		"shadow":   return "Stinova vetev"
		"military": return "Valecnicka vetev"
		"mystic":   return "Mysticka vetev"
		_:          return branch


func _branch_color(branch: String) -> Color:
	match branch:
		"shadow":   return Color("#9c27b0")
		"military": return Color("#f44336")
		"mystic":   return Color("#2196f3")
		_:          return Color("#aaaaaa")


# ---------------------------------------------------------
# Node button
# ---------------------------------------------------------

func _create_node_button(node_key: String) -> Button:
	var node_data: Dictionary = Balance.get_progression_node(node_key)
	var status: Dictionary = GameState.progression_manager.can_unlock(
			Balance.PLAYER_FACTION, node_key)
	var is_unlocked: bool = GameState.progression_manager.is_unlocked(
			Balance.PLAYER_FACTION, node_key)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 60)
	btn.name = "NodeBtn_" + node_key

	var cost_rp: int = node_data["cost"]["rp"]
	btn.text = "%s\n%d RP" % [node_data["display_name"], cost_rp]

	# T5 Apotheoza — zvetseny font
	var tier: int = int(node_data.get("tier", 0))
	if tier == 5:
		btn.add_theme_font_size_override("font_size", 14)

	btn.tooltip_text = node_data["description"]
	if not is_unlocked and not status["ok"]:
		btn.tooltip_text += "\n\n" + status["reason"]

	_apply_node_color(btn, is_unlocked, status["ok"])
	btn.disabled = is_unlocked or not status["ok"]

	btn.pressed.connect(func(): _on_node_pressed(node_key))
	return btn


func _on_node_pressed(node_key: String) -> void:
	var node_data: Dictionary = Balance.get_progression_node(node_key)
	var cost_rp: int = node_data["cost"]["rp"]

	var dialog := ConfirmationDialog.new()
	dialog.title = "Odemknout uzel?"
	dialog.dialog_text = "Odemknout '%s' za %d RP?" % [
			node_data["display_name"], cost_rp]
	add_child(dialog)
	dialog.popup_centered()

	dialog.confirmed.connect(func():
		dialog.queue_free()
		_confirm_unlock(node_key)
	)
	dialog.canceled.connect(func(): dialog.queue_free())


func _confirm_unlock(node_key: String) -> void:
	var result: Dictionary = GameState.progression_manager.unlock_node(
			Balance.PLAYER_FACTION, node_key)
	if result["ok"]:
		_refresh_node_states()
		_refresh_rp()
	else:
		push_warning("Unlock failed: " + result["reason"])


# ---------------------------------------------------------
# Refresh
# ---------------------------------------------------------

func _refresh_rp() -> void:
	var faction = GameState.faction_manager.get_faction(Balance.PLAYER_FACTION)
	if faction == null:
		return
	var rp: int = int(faction.get_resource("research"))
	rp_label.text = "RP: %d" % rp


func _refresh_node_states() -> void:
	for tier in range(1, 6):
		var status_list: Array = GameState.progression_manager.get_tier_status(
				Balance.PLAYER_FACTION, tier)
		for item in status_list:
			var btn_name: String = "NodeBtn_" + item["key"]
			var btn = tree_container.find_child(btn_name, true, false)
			if btn == null:
				continue
			var is_unlocked: bool = item["state"] == "unlocked"
			var is_available: bool = item["state"] == "available"
			_apply_node_color(btn, is_unlocked, is_available)
			btn.disabled = is_unlocked or not is_available


func _apply_node_color(btn: Button, is_unlocked: bool, is_available: bool) -> void:
	var color: Color
	if is_unlocked:
		color = COLOR_UNLOCKED
	elif is_available:
		color = COLOR_AVAILABLE
	else:
		color = COLOR_LOCKED
	btn.add_theme_color_override("font_color", color)


func _get_nodes_for_tier(tier: int) -> Array:
	var result: Array = []
	for key in Balance.PROGRESSION:
		if int(Balance.PROGRESSION[key].get("tier", 0)) == tier:
			result.append(key)
	return result
