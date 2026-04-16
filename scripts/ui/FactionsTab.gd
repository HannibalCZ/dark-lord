extends Control

const FACTION_COLORS := {
	"paladin":  Color("#cca644"),
	"elf":      Color("#4caf50"),
	"merchant": Color("#55aadd"),
	"orc":      Color("#8b0000"),
}

@onready var factions_container: VBoxContainer = $VBoxContainer/ScrollContainer/FactionsContainer

var _faction_ids: Array[String] = []

func _ready() -> void:
	GameState.game_updated.connect(_on_game_updated)
	_build_factions()

func _on_game_updated() -> void:
	_refresh_factions()

# ---------------------------------------------------------
# Build — jednou při inicializaci
# ---------------------------------------------------------

func _build_factions() -> void:
	for child in factions_container.get_children():
		child.queue_free()
	_faction_ids.clear()

	var ai_factions: Array = GameState.faction_manager.ai_factions()
	for faction in ai_factions:
		_faction_ids.append(faction.id)
		var card := _create_card(faction)
		factions_container.add_child(card)

func _create_card(faction: Faction) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "FactionCard_" + faction.id

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e1e2e")
	style.content_margin_left   = 8.0
	style.content_margin_right  = 8.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# --- Řádek 1: barevná tečka + jméno ---
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var dot := ColorRect.new()
	dot.name = "FactionDot"
	dot.custom_minimum_size = Vector2(16, 16)
	dot.color = FACTION_COLORS.get(faction.id, Color("#888888"))
	header_row.add_child(dot)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	header_row.add_child(spacer)

	var name_label := Label.new()
	name_label.name = "FactionName"
	name_label.text = faction.name
	name_label.add_theme_font_size_override("font_size", 14)
	header_row.add_child(name_label)

	# --- Separator ---
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# --- Řádek 2: chování + spawn ---
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	vbox.add_child(row2)

	var behavior_label := Label.new()
	behavior_label.name = "BehaviorLabel"
	behavior_label.text = "Chování: " + _behavior_display(faction)
	behavior_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(behavior_label)

	var spawn_label := Label.new()
	spawn_label.name = "SpawnLabel"
	spawn_label.text = _spawn_display(faction)
	row2.add_child(spawn_label)

	# --- Řádek 3: jednotky + regiony ---
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 12)
	vbox.add_child(row3)

	var units_label := Label.new()
	units_label.name = "UnitsLabel"
	units_label.text = "Jednotky: %d" % GameState.unit_manager.get_active_unit_count_for(faction.id)
	units_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(units_label)

	var regions_label := Label.new()
	regions_label.name = "RegionsLabel"
	regions_label.text = "Regiony: %d" % GameState.region_manager.get_regions_by_faction(faction.id).size()
	row3.add_child(regions_label)

	# --- Řádek 4: placeholder pro reputační systém ---
	var effect_label := Label.new()
	effect_label.name = "BehaviorEffectLabel"
	effect_label.text = "Heat threshold: vychozi"
	effect_label.add_theme_color_override("font_color", Color("#888888"))
	effect_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(effect_label)

	return card

# ---------------------------------------------------------
# Refresh — aktualizuje hodnoty bez rebuildu
# ---------------------------------------------------------

func _refresh_factions() -> void:
	for faction_id in _faction_ids:
		var faction: Faction = GameState.faction_manager.get_faction(faction_id)
		if faction == null:
			continue
		var card: Node = factions_container.get_node_or_null("FactionCard_" + faction_id)
		if card == null:
			continue
		_update_card(card, faction)

func _update_card(card: Node, faction: Faction) -> void:
	var vbox: Node = card.get_child(0)
	if vbox == null:
		return

	var row2: Node = vbox.get_child(2)  # index 0=header, 1=sep, 2=row2
	if row2 != null:
		var behavior_label: Label = row2.get_node_or_null("BehaviorLabel")
		if behavior_label != null:
			behavior_label.text = "Chování: " + _behavior_display(faction)
		var spawn_label: Label = row2.get_node_or_null("SpawnLabel")
		if spawn_label != null:
			spawn_label.text = _spawn_display(faction)

	var row3: Node = vbox.get_child(3)  # index 3=row3
	if row3 != null:
		var units_label: Label = row3.get_node_or_null("UnitsLabel")
		if units_label != null:
			units_label.text = "Jednotky: %d" % GameState.unit_manager.get_active_unit_count_for(faction.id)
		var regions_label: Label = row3.get_node_or_null("RegionsLabel")
		if regions_label != null:
			regions_label.text = "Regiony: %d" % GameState.region_manager.get_regions_by_faction(faction.id).size()

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------

func _behavior_display(faction: Faction) -> String:
	if faction.id == "orc":
		return "Najezdnik (fixni)"
	match faction.current_behavior:
		Faction.Behavior.PASSIVE:
			return "Pasivni"
		Faction.Behavior.PATROLLING:
			return "Hlidkovani"
		Faction.Behavior.AGGRESSIVE:
			return "Agresivni"
		Faction.Behavior.COORDINATED:
			return "Koordinovany utok"
		_:
			return "Neznamy"

func _spawn_display(faction: Faction) -> String:
	var cfg: Dictionary = Balance.AI_SPAWN.get(faction.id, {})
	if cfg.is_empty():
		return "Spawn: -"
	var enabled: bool = faction.ai_regular_spawns_enabled
	var counter: int = faction.spawn_counter
	var rate: int = cfg.get("spawn_rate", 0)
	if enabled:
		return "Spawn: %d/%d tahu" % [counter, rate]
	else:
		return "Spawn: neaktivni"
