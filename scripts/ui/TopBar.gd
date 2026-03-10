# scripts/ui/TopBar.gd
extends Control

@onready var mana_label      : Label        = $HBoxContainer/Label
@onready var res_label       : Label        = $HBoxContainer/Label2
@onready var noto_label      : Label        = $HBoxContainer/Label3
@onready var research_label  : Label        = $HBoxContainer/ResearchLabel
@onready var units_label     : Label        = $HBoxContainer/UnitsLabel # nový label
@onready var heat_bar        : ProgressBar  = $HBoxContainer/ProgressBar
@onready var turn_label      : Label        = $HBoxContainer/TurnLabel
@onready var next_turn_btn   : Button       = $HBoxContainer/Button

func _ready() -> void:
	GameState.connect("game_updated", Callable(self, "_refresh"))
	next_turn_btn.pressed.connect(_on_next_turn_pressed)
	_refresh()

func _refresh() -> void:
	var econ := GameState.economic_manager.compute_income_and_upkeep("player")
	mana_label.text = "Mana: %d (%+d)" % [GameState.faction_manager.get_faction(Balance.PLAYER_FACTION).resources["mana"], int(econ.net_mana)]
	res_label.text  = "Zlato: %d (%+d)" % [GameState.faction_manager.get_faction(Balance.PLAYER_FACTION).resources["gold"], int(econ.net_gold)]
	noto_label.text = "Hanebnost: %d" % GameState.faction_manager.get_faction(Balance.PLAYER_FACTION).resources["infamy"]
	research_label.text = "Výzkum: %d" % GameState.faction_manager.get_faction(Balance.PLAYER_FACTION).resources["research"]
	units_label.text = "Jednotky: %d / %d" % [GameState.unit_manager.get_active_unit_count_for(Balance.PLAYER_FACTION), GameState.unit_manager.unit_limit]
	heat_bar.value  = GameState.heat
	turn_label.text = "Tah: %d" % GameState.turn



func _on_next_turn_pressed() -> void:
	GameState.advance_turn()
