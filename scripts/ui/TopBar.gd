# scripts/ui/TopBar.gd
extends PanelContainer

@onready var mana_block      : VBoxContainer = $HBoxContainer/Resources/ManaBlock
@onready var zlato_block     : VBoxContainer = $HBoxContainer/Resources/ZlatoBlock
@onready var hanebnost_block : VBoxContainer = $HBoxContainer/Resources/HanebnostBlock
@onready var vyzkum_block    : VBoxContainer = $HBoxContainer/Resources/VyzkumBlock
@onready var units_label     : Label         = $HBoxContainer/Units/UnitsLabel
@onready var heat_bar        : ProgressBar   = $HBoxContainer/HeatSection/HeatBar
@onready var heat_value      : Label         = $HBoxContainer/HeatSection/HeatValue
@onready var awareness_bar   : ProgressBar   = $HBoxContainer/AwarenessSection/AwarenessBar
@onready var awareness_value : Label         = $HBoxContainer/AwarenessSection/AwarenessValue
@onready var infamy_value    : Label         = $HBoxContainer/Resources/HanebnostBlock/Value
@onready var control_value   : Label         = $HBoxContainer/ControlSection/ControlValue
@onready var turn_label      : Label         = $HBoxContainer/TurnLabel
@onready var next_turn_btn   : Button        = $HBoxContainer/NextTurnButton

func _ready() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#1a1a2e")
	bg.content_margin_left   = 8.0
	bg.content_margin_right  = 8.0
	bg.content_margin_top    = 6.0
	bg.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", bg)

	GameState.connect("game_updated", Callable(self, "_refresh"))
	GameState.game_ended.connect(_on_game_ended)
	next_turn_btn.pressed.connect(_on_next_turn_pressed)
	zlato_block.get_node("Value").mouse_filter = Control.MOUSE_FILTER_PASS
	mana_block.get_node("Value").mouse_filter  = Control.MOUSE_FILTER_PASS
	_refresh()

func _refresh() -> void:
	var faction := GameState.faction_manager.get_faction(Balance.PLAYER_FACTION)
	var econ    := GameState.economic_manager.compute_income_and_upkeep("player")

	_update_resource_block(mana_block,      faction.resources["mana"],     int(econ.net_mana))
	_update_resource_block(zlato_block,     faction.resources["gold"],     int(econ.net_gold))
	_update_resource_block(hanebnost_block, faction.resources["infamy"],   0)
	_update_resource_block(vyzkum_block,    faction.resources["research"], 0)

	zlato_block.get_node("Value").tooltip_text = build_economy_tooltip(
			GameState.economy_tracker.entries, "gold",
			int(faction.resources["gold"]))
	mana_block.get_node("Value").tooltip_text = build_economy_tooltip(
			GameState.economy_tracker.entries, "mana",
			int(faction.resources["mana"]))

	units_label.text = "\u2694 %d / %d" % [
		GameState.unit_manager.get_active_unit_count_for(Balance.PLAYER_FACTION),
		GameState.unit_manager.unit_limit
	]

	_update_heat_bar(GameState.heat)
	_update_infamy(int(faction.resources.get("infamy", 0)))
	_update_awareness_bar(GameState.awareness)
	_update_control_count()
	turn_label.text = "Tah: %d" % GameState.turn


func _update_resource_block(block: VBoxContainer, value: int, delta: int) -> void:
	block.get_node("Value").text = str(value)
	var delta_label : Label = block.get_node("Delta")
	if delta > 0:
		delta_label.text = "(+%d)" % delta
		delta_label.add_theme_color_override("font_color", Color("#4caf50"))
	elif delta < 0:
		delta_label.text = "(%d)" % delta
		delta_label.add_theme_color_override("font_color", Color("#f44336"))
	else:
		delta_label.text = ""


func _update_heat_bar(value: int) -> void:
	heat_bar.value = value
	heat_value.text = "%d%%" % value
	heat_value.tooltip_text = build_breakdown_tooltip(
			GameState.heat_tracker.entries, "heat", value)
	var style := StyleBoxFlat.new()
	if value >= 100:
		style.bg_color = Color("#9c27b0")
	elif value >= 75:
		style.bg_color = Color("#f44336")
	elif value >= 50:
		style.bg_color = Color("#ff9800")
	else:
		style.bg_color = Color("#4caf50")
	heat_bar.add_theme_stylebox_override("fill", style)


func _update_awareness_bar(value: int) -> void:
	awareness_bar.value = value
	awareness_value.text = "%d%%" % value
	awareness_value.tooltip_text = build_breakdown_tooltip(
			GameState.heat_tracker.entries, "awareness", value)
	var style := StyleBoxFlat.new()
	if value >= 100:
		style.bg_color = Color("#9c27b0")
	elif value >= 67:
		style.bg_color = Color("#f44336")
	elif value >= 34:
		style.bg_color = Color("#ff9800")
	else:
		style.bg_color = Color("#4caf50")
	awareness_bar.add_theme_stylebox_override("fill", style)


static func build_breakdown_tooltip(
		entries: Array[Dictionary],
		stat: String,
		current_value: int) -> String:
	var delta_key: String = stat + "_delta"
	var relevant: Array[Dictionary] = []
	for e in entries:
		if e.get(delta_key, 0) != 0:
			relevant.append(e)

	if relevant.is_empty():
		return "%s: %d\n(zadna zmena tento tah)" % [stat.capitalize(), current_value]

	var total: int = 0
	for e in relevant:
		total += int(e.get(delta_key, 0))

	var sign: String = "+" if total >= 0 else ""
	var lines: Array[String] = []
	lines.append("%s: %d (%s%d tento tah)" % [stat.capitalize(), current_value, sign, total])
	lines.append("─────────────────")

	for e in relevant:
		var delta: int = int(e.get(delta_key, 0))
		if delta == 0:
			continue
		var label: String = e.get("source", "Neznamy zdroj")
		var delta_sign: String = "+" if delta >= 0 else ""
		lines.append("  %s: %s%d" % [label, delta_sign, delta])

	return "\n".join(lines)


static func build_economy_tooltip(
		entries: Array[Dictionary],
		stat: String,
		current_value: int) -> String:
	var delta_key: String = stat + "_delta"
	var relevant: Array[Dictionary] = []
	for e in entries:
		if e.get(delta_key, 0) != 0:
			relevant.append(e)

	if relevant.is_empty():
		return "%s: %d\n(zadna zmena tento tah)" % [stat.capitalize(), current_value]

	var total: int = 0
	for e in relevant:
		total += int(e.get(delta_key, 0))

	var sign: String = "+" if total >= 0 else ""
	var lines: Array[String] = []
	lines.append("%s: %d (%s%d tento tah)" % [stat.capitalize(), current_value, sign, total])
	lines.append("─────────────────")

	for e in relevant:
		var delta: int = int(e.get(delta_key, 0))
		if delta == 0:
			continue
		var label: String = e.get("source_label", "Neznamy zdroj")
		var delta_sign: String = "+" if delta >= 0 else ""
		lines.append("  %s: %s%d" % [label, delta_sign, delta])

	return "\n".join(lines)


func _update_infamy(value: int) -> void:
	infamy_value.text = str(value)
	if value >= 75:
		infamy_value.add_theme_color_override("font_color", Color("#9c27b0"))
	elif value >= 50:
		infamy_value.add_theme_color_override("font_color", Color("#e94560"))
	elif value >= 25:
		infamy_value.add_theme_color_override("font_color", Color("#ff9800"))
	else:
		infamy_value.add_theme_color_override("font_color", Color("#aaaaaa"))


func _update_control_count() -> void:
	var controlled: int = GameState.query.regions.count_player_controlled_civilized()
	var total: int = GameState.query.regions.count_total_civilized()
	control_value.text = "%d/%d" % [controlled, total]
	var ratio: float = float(controlled) / float(total) if total > 0 else 0.0
	if ratio >= 0.67:
		control_value.add_theme_color_override("font_color", Color("#4caf50"))
	elif ratio >= 0.33:
		control_value.add_theme_color_override("font_color", Color("#ff9800"))
	else:
		control_value.add_theme_color_override("font_color", Color("#aaaaaa"))


func _on_game_ended(result: Dictionary) -> void:
	next_turn_btn.disabled = true
	next_turn_btn.tooltip_text = "Hra skoncila - %s" % result.get("outcome", "")


func _on_next_turn_pressed() -> void:
	GameState.advance_turn()
