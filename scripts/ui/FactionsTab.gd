extends Control

const FACTION_COLORS := {
	"paladin":     Color("#cca644"),
	"elf":         Color("#4caf50"),
	"inquisition": Color("#9c27b0"),
	"merchant":    Color("#55aadd"),
	"orc":         Color("#8b0000"),
}

@onready var factions_container: VBoxContainer = $VBoxContainer/ScrollContainer/FactionsContainer

var _faction_ids: Array[String] = []

func _ready() -> void:
	GameState.game_updated.connect(_on_game_updated)
	_build_factions()

func _on_game_updated() -> void:
	# Pokud přibyly nové frakce (např. network), přebuduj celý list
	var current_ids: Array = GameState.faction_manager.ai_factions().map(func(f): return f.id)
	var needs_rebuild: bool = current_ids.size() != _faction_ids.size()
	if not needs_rebuild:
		for id in current_ids:
			if id not in _faction_ids:
				needs_rebuild = true
				break
	if needs_rebuild:
		_build_factions()
	else:
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
		if faction.faction_type == "network":
			factions_container.add_child(_create_network_card(faction))
		else:
			factions_container.add_child(_create_card(faction))

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

	# --- Řádek 4: Heat threshold modifier z reputace ---
	var effect_label := Label.new()
	effect_label.name = "BehaviorEffectLabel"
	effect_label.text = _behavior_effect_display(faction)
	effect_label.add_theme_color_override("font_color", Color("#888888"))
	effect_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(effect_label)

	# --- Řádek 5: reputace — hodnota a fáze ---
	var rep_label := Label.new()
	rep_label.name = "ReputationLabel"
	rep_label.add_theme_font_size_override("font_size", 12)
	rep_label.text = "Reputace: %d — %s" % [
		faction.reputation,
		_reputation_phase_display(faction.reputation_phase)
	]
	rep_label.add_theme_color_override(
		"font_color", _reputation_phase_color(faction.reputation_phase))
	vbox.add_child(rep_label)

	# --- Řádek 6: breakdown výpočtu reputace (sekundární, šedší) ---
	var breakdown_label := Label.new()
	breakdown_label.name = "ReputationBreakdownLabel"
	breakdown_label.add_theme_font_size_override("font_size", 11)
	breakdown_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
	var bd: Dictionary = GameState.reputation_manager.get_reputation_breakdown(faction.id)
	breakdown_label.text = "  Zaklad: +%d | Korupce: +%d | Sit: +%d" % [
		bd["base"], bd["corruption"], bd["shadow_net"]
	]
	vbox.add_child(breakdown_label)

	# --- Řádek 7: pokladna (gold / mana) ---
	var economy_label := Label.new()
	economy_label.name = "EconomyLabel"
	economy_label.add_theme_font_size_override("font_size", 12)
	economy_label.add_theme_color_override("font_color", Color("#888888"))
	var fac_gold := faction.get_resource("gold")
	var fac_mana := faction.get_resource("mana")
	economy_label.visible = fac_gold > 0 or fac_mana > 0
	economy_label.text = "Pokladna: %dg / %dm" % [int(fac_gold), int(fac_mana)]
	vbox.add_child(economy_label)

	return card

func _create_network_card(faction: Faction) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "FactionCard_" + faction.id

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1a1228")
	style.content_margin_left   = 8.0
	style.content_margin_right  = 8.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Řádek 1: fialová tečka + název typu
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(16, 16)
	dot.color = Color("#9c27b0")
	header_row.add_child(dot)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	header_row.add_child(spacer)

	const TYPE_DISPLAY := {
		"cult":             "Kult",
		"crime_syndicate":  "Syndikát",
		"shadow_network":   "Stínová síť"
	}
	var name_label := Label.new()
	name_label.text = TYPE_DISPLAY.get(faction.network_type, faction.network_type)
	name_label.add_theme_font_size_override("font_size", 14)
	header_row.add_child(name_label)

	vbox.add_child(HSeparator.new())

	# Řádek 2: visibility + počet regionů s vlivem
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	vbox.add_child(row2)

	var vis_label := Label.new()
	vis_label.name = "VisibilityLabel"
	vis_label.text = "Viditelnost: %d/100" % faction.visibility
	vis_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(vis_label)

	var regions_count := faction.influence.keys().filter(
		func(rid): return faction.influence[rid] > 0).size()
	var inf_label := Label.new()
	inf_label.name = "InfluenceLabel"
	inf_label.text = "Regiony: %d" % regions_count
	row2.add_child(inf_label)

	# --- Řádek 3: pokladna (gold / mana) ---
	var economy_label := Label.new()
	economy_label.name = "EconomyLabel"
	economy_label.add_theme_font_size_override("font_size", 12)
	economy_label.add_theme_color_override("font_color", Color("#888888"))
	var fac_gold := faction.get_resource("gold")
	var fac_mana := faction.get_resource("mana")
	economy_label.text = "Pokladna: %dg / %dm" % [int(fac_gold), int(fac_mana)]
	vbox.add_child(economy_label)

	# --- Řádek 4: vliv per region (loajalita / síla přítomnosti) ---
	var influence_detail := Label.new()
	influence_detail.name = "InfluenceDetailLabel"
	influence_detail.add_theme_font_size_override("font_size", 11)
	influence_detail.add_theme_color_override("font_color", Color("#aaaaaa"))
	influence_detail.text = _influence_detail_text(faction)
	vbox.add_child(influence_detail)

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
	if faction.faction_type == "network":
		_update_network_card(card, faction)
		return
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

	# BehaviorEffectLabel — Heat threshold modifier
	var effect_label: Label = vbox.get_node_or_null("BehaviorEffectLabel")
	if effect_label != null:
		effect_label.text = _behavior_effect_display(faction)

	# ReputationLabel — hodnota a fáze s barvou
	var rep_label: Label = vbox.get_node_or_null("ReputationLabel")
	if rep_label != null:
		rep_label.text = "Reputace: %d — %s" % [
			faction.reputation,
			_reputation_phase_display(faction.reputation_phase)
		]
		rep_label.add_theme_color_override(
			"font_color", _reputation_phase_color(faction.reputation_phase))

	# ReputationBreakdownLabel — breakdown výpočtu
	var breakdown_label: Label = vbox.get_node_or_null("ReputationBreakdownLabel")
	if breakdown_label != null:
		var bd: Dictionary = GameState.reputation_manager.get_reputation_breakdown(faction.id)
		breakdown_label.text = "  Zaklad: +%d | Korupce: +%d | Sit: +%d" % [
			bd["base"], bd["corruption"], bd["shadow_net"]
		]

	# EconomyLabel — pokladna (gold / mana)
	var economy_label: Label = vbox.get_node_or_null("EconomyLabel")
	if economy_label != null:
		var fac_gold := faction.get_resource("gold")
		var fac_mana := faction.get_resource("mana")
		economy_label.visible = fac_gold > 0 or fac_mana > 0
		economy_label.text = "Pokladna: %dg / %dm" % [int(fac_gold), int(fac_mana)]

func _update_network_card(card: Node, faction: Faction) -> void:
	var vbox: Node = card.get_child(0)
	if vbox == null:
		return
	var row2: Node = vbox.get_child(2)  # index 0=header, 1=sep, 2=row2
	if row2 == null:
		return
	var vis_label: Label = row2.get_node_or_null("VisibilityLabel")
	if vis_label != null:
		vis_label.text = "Viditelnost: %d/100" % faction.visibility
	var inf_label: Label = row2.get_node_or_null("InfluenceLabel")
	if inf_label != null:
		var count := faction.influence.keys().filter(
			func(rid): return faction.influence[rid] > 0).size()
		inf_label.text = "Regiony: %d" % count

	var economy_label: Label = vbox.get_node_or_null("EconomyLabel")
	if economy_label != null:
		var fac_gold := faction.get_resource("gold")
		var fac_mana := faction.get_resource("mana")
		economy_label.text = "Pokladna: %dg / %dm" % [int(fac_gold), int(fac_mana)]

	var influence_detail: Label = vbox.get_node_or_null("InfluenceDetailLabel")
	if influence_detail != null:
		influence_detail.text = _influence_detail_text(faction)

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

func _reputation_phase_display(phase: String) -> String:
	match phase:
		"hostile":     return "Nepratelska"
		"neutral":     return "Neutralni"
		"infiltrated": return "Infiltrovana"
		"controlled":  return "Ovladnuta"
		_:             return "Neznama"

func _reputation_phase_color(phase: String) -> Color:
	match phase:
		"hostile":     return Color("#f44336")
		"neutral":     return Color("#aaaaaa")
		"infiltrated": return Color("#ffd700")
		"controlled":  return Color("#4caf50")
		_:             return Color("#aaaaaa")

func _influence_detail_text(faction: Faction) -> String:
	if faction.influence.is_empty():
		return "Vliv: —"
	# Seřaď regiony sestupně podle vlivu, zobraz max 4
	var pairs: Array = []
	for rid in faction.influence.keys():
		var val: int = faction.influence[rid]
		if val > 0:
			pairs.append([rid, val])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	var parts: Array[String] = []
	var shown: int = 0
	for pair in pairs:
		var region: Region = GameState.query.regions.get_by_id(pair[0])
		var rname: String = region.name if region != null and region.name != "" else "R%d" % pair[0]
		parts.append("%s: %d" % [rname, pair[1]])
		shown += 1
		if shown >= 4:
			break
	var text: String = "Vliv: " + " | ".join(parts)
	if pairs.size() > 4:
		text += " (+%d)" % (pairs.size() - 4)
	return text

func _behavior_effect_display(faction: Faction) -> String:
	var mod: int = faction.reputation_modifier
	if mod == 0:
		return "Heat threshold: vychozi"
	elif mod == 99:
		return "Heat threshold: ignoruje Heat"
	elif mod > 0:
		return "Heat threshold: +%d" % mod
	else:
		return "Heat threshold: %d" % mod
