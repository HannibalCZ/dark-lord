extends Control
@onready var container: VBoxContainer = $VBoxContainer/BuildingsContainer

func _ready() -> void:
	_refresh()
	GameState.connect("game_updated", Callable(self, "_refresh"))

func _refresh() -> void:
	for child in container.get_children():
		child.queue_free()

	for b in GameState.building_manager.buildings:
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.size_flags_vertical = Control.SIZE_FILL
		hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		hbox.custom_minimum_size = Vector2(0, 32) # výška řádku
		
		var label = Label.new()
		label.text = "%s – %s [Cena: %d]" % [b["name"], b["desc"], b["cost"]]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)

		var btn = Button.new()
		if b["built"] :
			btn.text = "Postaveno" 
		else : btn.text = "Postavit"
		btn.disabled = b["built"] or GameState.faction_manager.get_faction(Balance.PLAYER_FACTION).resources["gold"] < b["cost"]
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.custom_minimum_size = Vector2(120, 28)
		btn.pressed.connect(func(): GameState.build_building(b["id"]))
		hbox.add_child(btn)

		container.add_child(hbox)
		
	# Oddělovač
	var sep := HSeparator.new()
	container.add_child(sep)

	# Nadpis
	var recruit_label := Label.new()
	recruit_label.text = "Rekrutace jednotek"
	container.add_child(recruit_label)

	# Tlačítko – Orčí banda
	var orc_btn := Button.new()
	orc_btn.text = "Povolat Orčí bandu (15 surovin)"
	var current_units: int = GameState.unit_manager.get_active_unit_count_for(Balance.PLAYER_FACTION)
	orc_btn.disabled = current_units >= GameState.unit_manager.unit_limit
	orc_btn.pressed.connect(func(): GameState.exec(GameState.unit_manager.recruit_unit(Balance.PLAYER_FACTION, "orc_band", 0)))
	container.add_child(orc_btn)
