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
@onready var infamy_value    : Label         = $HBoxContainer/InfamySection/InfamyValue
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
	_refresh()

func _refresh() -> void:
	var faction := GameState.faction_manager.get_faction(Balance.PLAYER_FACTION)
	var econ    := GameState.economic_manager.compute_income_and_upkeep("player")

	_update_resource_block(mana_block,      faction.resources["mana"],     int(econ.net_mana))
	_update_resource_block(zlato_block,     faction.resources["gold"],     int(econ.net_gold))
	_update_resource_block(hanebnost_block, faction.resources["infamy"],   0)
	_update_resource_block(vyzkum_block,    faction.resources["research"], 0)

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
