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

	var current_units: int = GameState.unit_manager.get_active_unit_count_for(Balance.PLAYER_FACTION)
	var at_limit: bool = current_units >= GameState.unit_manager.unit_limit
	var fac: Faction = GameState.faction_manager.get_faction(Balance.PLAYER_FACTION)
	var spawn_region: int = GameState.player_start_region_id

	# Tlačítko – Orčí banda
	var orc_btn := Button.new()
	orc_btn.text = "Povolat Orčí bandu (15 surovin)"
	orc_btn.disabled = at_limit
	orc_btn.pressed.connect(func(): GameState.exec(GameState.unit_manager.recruit_unit(Balance.PLAYER_FACTION, "orc_band", spawn_region)))
	container.add_child(orc_btn)

	# Tlačítko – Upír
	var vamp_cost: int = Balance.UNIT.get("vampire", {}).get("recruit_cost", {}).get("mana", 0)
	var vampire_btn := Button.new()
	vampire_btn.text = "Verbuj Upira (mana: %d)" % vamp_cost
	var can_afford_vamp: bool = fac.get_resource("mana") >= vamp_cost
	vampire_btn.disabled = at_limit or not can_afford_vamp
	if vampire_btn.disabled:
		vampire_btn.tooltip_text = "Dosazen limit jednotek." if at_limit else "Nedostatek many (potreba: %d)." % vamp_cost
	vampire_btn.pressed.connect(func(): GameState.exec(GameState.unit_manager.recruit_unit(Balance.PLAYER_FACTION, "vampire", spawn_region)))
	container.add_child(vampire_btn)

	# Tlačítko – Homunkulus
	var hom_cost: int = Balance.UNIT.get("homunculus", {}).get("recruit_cost", {}).get("mana", 0)
	var homunculus_btn := Button.new()
	homunculus_btn.text = "Verbuj Homuncula (mana: %d)" % hom_cost
	var can_afford_hom: bool = fac.get_resource("mana") >= hom_cost
	homunculus_btn.disabled = at_limit or not can_afford_hom
	if homunculus_btn.disabled:
		homunculus_btn.tooltip_text = "Dosazen limit jednotek." if at_limit else "Nedostatek many (potreba: %d)." % hom_cost
	homunculus_btn.pressed.connect(func(): GameState.exec(GameState.unit_manager.recruit_unit(Balance.PLAYER_FACTION, "homunculus", spawn_region)))
	container.add_child(homunculus_btn)
