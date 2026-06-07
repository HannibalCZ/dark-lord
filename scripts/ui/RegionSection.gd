class_name RegionSection
extends VBoxContainer

@onready var stat_panel: PanelContainer = $StatPanel
@onready var region_name_label: Label   = $StatPanel/VBoxContainer/RegionName
@onready var region_owner: Label        = $StatPanel/VBoxContainer/RegionOwner
@onready var obrana_val: Label          = $StatPanel/VBoxContainer/StatsRow/LeftCol/ObranaVal
@onready var prijem_val: Label          = $StatPanel/VBoxContainer/StatsRow/LeftCol/PrijemVal
@onready var korupce_val: Label         = $StatPanel/VBoxContainer/StatsRow/RightCol/KorupceVal
@onready var strach_val: Label          = $StatPanel/VBoxContainer/StatsRow/RightCol/StrachVal
@onready var corruption_effect_label: Label = $StatPanel/VBoxContainer/CorruptionEffectLabel
@onready var occupation_label: Label        = $StatPanel/VBoxContainer/OccupationLabel
@onready var population_label: Label       = $StatPanel/VBoxContainer/PopulationLabel
@onready var stability_label: Label        = $StatPanel/VBoxContainer/StabilityLabel
@onready var prosperity_label: Label       = $StatPanel/VBoxContainer/ProsperityLabel

@onready var units_section: PanelContainer = $UnitsSection
@onready var units_header: Button          = $UnitsSection/VBoxContainer/UnitsHeader
@onready var units_content: VBoxContainer  = $UnitsSection/VBoxContainer/UnitsContent

@onready var tags_section: PanelContainer = $TagsSection
@onready var tags_header: Button          = $TagsSection/VBoxContainer/TagsHeader
@onready var tags_content: VBoxContainer  = $TagsSection/VBoxContainer/TagsContent

@onready var secrets_section: PanelContainer = $SecretsSection
@onready var secrets_header: Button          = $SecretsSection/VBoxContainer/SecretsHeader
@onready var secrets_content: VBoxContainer  = $SecretsSection/VBoxContainer/SecretsContent

@onready var lair_info_section: PanelContainer   = $LairInfoSection
@onready var lair_info_header: Button            = $LairInfoSection/VBoxContainer/LairInfoHeader
@onready var lair_info_content: VBoxContainer    = $LairInfoSection/VBoxContainer/LairInfoContent
@onready var lair_info_label: Label              = $LairInfoSection/VBoxContainer/LairInfoContent/LairInfoLabel
@onready var lair_influence_label: Label         = $LairInfoSection/VBoxContainer/LairInfoContent/LairInfluenceLabel
@onready var lair_control_label: Label           = $LairInfoSection/VBoxContainer/LairInfoContent/LairControlLabel
@onready var lair_decay_label: Label             = $LairInfoSection/VBoxContainer/LairInfoContent/LairDecayLabel

@onready var lair_directive_options: VBoxContainer   = $LairInfoSection/VBoxContainer/LairInfoContent/LairDirectiveOptions
@onready var defensive_button: Button                = $LairInfoSection/VBoxContainer/LairInfoContent/LairDirectiveOptions/LairButtonRow/DefensiveButton
@onready var raider_button: Button                   = $LairInfoSection/VBoxContainer/LairInfoContent/LairDirectiveOptions/LairButtonRow/RaiderButton

@onready var network_faction_section: PanelContainer   = $NetworkFactionSection
@onready var network_faction_header: Button            = $NetworkFactionSection/VBoxContainer/NetworkFactionHeader
@onready var network_faction_content: VBoxContainer    = $NetworkFactionSection/VBoxContainer/NetworkFactionContent
@onready var network_faction_name_label: Label         = $NetworkFactionSection/VBoxContainer/NetworkFactionContent/NetworkFactionNameLabel
@onready var network_founder_label: Label              = $NetworkFactionSection/VBoxContainer/NetworkFactionContent/NetworkFounderLabel
@onready var network_influence_label: Label            = $NetworkFactionSection/VBoxContainer/NetworkFactionContent/NetworkInfluenceLabel
@onready var network_loyalty_label: Label              = $NetworkFactionSection/VBoxContainer/NetworkFactionContent/NetworkLoyaltyLabel
@onready var network_doctrine_container: VBoxContainer = $NetworkFactionSection/VBoxContainer/NetworkFactionContent/NetworkDoctrineContainer
@onready var network_doctrine_picker: OptionButton     = $NetworkFactionSection/VBoxContainer/NetworkFactionContent/NetworkDoctrineContainer/NetworkDoctrinePicker
@onready var network_doctrine_effects: Label           = $NetworkFactionSection/VBoxContainer/NetworkFactionContent/NetworkDoctrineContainer/NetworkDoctrineEffects

var _region: Region = null
var _nf_doctrine_keys: Array[String] = []

func _ready() -> void:
	var bg_stat := StyleBoxFlat.new()
	bg_stat.bg_color = Color("#1e1e2e")
	bg_stat.content_margin_left   = 12.0
	bg_stat.content_margin_right  = 12.0
	bg_stat.content_margin_top    = 12.0
	bg_stat.content_margin_bottom = 12.0
	stat_panel.add_theme_stylebox_override("panel", bg_stat)

	var bg_units := StyleBoxFlat.new()
	bg_units.bg_color = Color("#1a2a1a")
	bg_units.content_margin_left   = 12.0
	bg_units.content_margin_right  = 12.0
	bg_units.content_margin_top    = 12.0
	bg_units.content_margin_bottom = 12.0
	units_section.add_theme_stylebox_override("panel", bg_units)

	var bg_tags := StyleBoxFlat.new()
	bg_tags.bg_color = Color("#1a1a2a")
	bg_tags.content_margin_left   = 12.0
	bg_tags.content_margin_right  = 12.0
	bg_tags.content_margin_top    = 12.0
	bg_tags.content_margin_bottom = 12.0
	tags_section.add_theme_stylebox_override("panel", bg_tags)

	var bg_secrets := StyleBoxFlat.new()
	bg_secrets.bg_color = Color("#2a1a1a")
	bg_secrets.content_margin_left   = 12.0
	bg_secrets.content_margin_right  = 12.0
	bg_secrets.content_margin_top    = 12.0
	bg_secrets.content_margin_bottom = 12.0
	secrets_section.add_theme_stylebox_override("panel", bg_secrets)

	var bg_lair_info := StyleBoxFlat.new()
	bg_lair_info.bg_color = Color("#221a10")
	bg_lair_info.content_margin_left   = 12.0
	bg_lair_info.content_margin_right  = 12.0
	bg_lair_info.content_margin_top    = 12.0
	bg_lair_info.content_margin_bottom = 12.0
	lair_info_section.add_theme_stylebox_override("panel", bg_lair_info)

	units_header.pressed.connect(func(): _toggle_section(units_content, units_header))
	tags_header.pressed.connect(func(): _toggle_section(tags_content, tags_header))
	secrets_header.pressed.connect(func(): _toggle_section(secrets_content, secrets_header))
	lair_info_header.pressed.connect(func(): _toggle_section(lair_info_content, lair_info_header))
	defensive_button.pressed.connect(_on_defensive_pressed)
	raider_button.pressed.connect(_on_raider_pressed)
	network_faction_header.pressed.connect(func(): _toggle_section(network_faction_content, network_faction_header))
	network_doctrine_picker.item_selected.connect(_on_network_doctrine_selected)

	var bg_network := StyleBoxFlat.new()
	bg_network.bg_color = Color("#1a1228")
	bg_network.content_margin_left   = 12.0
	bg_network.content_margin_right  = 12.0
	bg_network.content_margin_top    = 12.0
	bg_network.content_margin_bottom = 12.0
	network_faction_section.add_theme_stylebox_override("panel", bg_network)

func show_for_region(region_id: int) -> void:
	if region_id == -1:
		visible = false
		return
	visible = true
	var region: Region = GameState.query.regions.get_by_id(region_id)
	if region == null:
		return
	_region = region
	_update_region_section(region)
	_update_units_section(region_id)
	_update_tags_section(region_id)
	_update_secrets_section(region_id)
	_refresh_lair_info(region)
	_refresh_lair_directive(region)
	_refresh_network_faction(region)

# --------------------------
# REGION SECTION

func _update_region_section(region: Region) -> void:
	region_name_label.text = region.name
	region_owner.text = region.controller_faction_id

	var max_def: int = region.max_defense
	obrana_val.text = "%d/%d" % [region.defense, max_def]

	prijem_val.text = _format_income(region)
	strach_val.text = "%d/100" % region.fear

	var corruption_pct: int = int(region.get_corruption_for(Balance.PLAYER_FACTION))
	var phase: int = region.get_corruption_phase_for(Balance.PLAYER_FACTION)
	var phase_name: String = Balance.CORRUPTION_PHASE_NAMES.get(phase, "Neznama")
	korupce_val.text = "%d%% — Faze %d (%s)" % [corruption_pct, phase, phase_name]

	var phase_effect: String = Balance.CORRUPTION_PHASE_EFFECTS.get(phase, "")
	if phase_effect != "":
		corruption_effect_label.text = "Efekt: " + phase_effect
		corruption_effect_label.visible = true
	else:
		corruption_effect_label.visible = false

	if region.occupying_faction != "" and region.defense <= 0:
		occupation_label.text = "Upozorneni: Region je na pokraji padu"
		occupation_label.add_theme_color_override("font_color", Color("#e53935"))
		occupation_label.visible = true
	elif region.occupying_faction != "":
		var attacker_fac = GameState.faction_manager.get_faction(region.occupying_faction)
		var attacker_name: String = region.occupying_faction
		if attacker_fac != null and attacker_fac.name != "":
			attacker_name = attacker_fac.name
		occupation_label.text = "Dobyvani: %s" % attacker_name
		occupation_label.add_theme_color_override("font_color", Color("#e65100"))
		occupation_label.visible = true
	else:
		if not region.inhabited:
			occupation_label.text = "Neobydlený — vyžaduje kolonizaci"
			occupation_label.add_theme_color_override("font_color", Color("#78909c"))
			occupation_label.visible = true
		else:
			occupation_label.visible = false

	var pop_cap: int = Balance.TERRAIN.get(region.terrain, {}).get("pop_cap", 0)
	var terrain_name: String = Balance.TERRAIN.get(region.terrain, {}).get("display_name", region.terrain)
	population_label.text = "Terén: %s  |  Obyvatelstvo: %d / %d" % [terrain_name, region.population, pop_cap]

	stability_label.text = "Stabilita: %d / %d" % [region.stability, Balance.STABILITY_MAX]
	if region.stability <= Balance.STABILITY_UNREST_THRESHOLD:
		stability_label.add_theme_color_override("font_color", Color("#e53935"))
	elif region.stability < 60:
		stability_label.add_theme_color_override("font_color", Color("#ff9800"))
	else:
		stability_label.add_theme_color_override("font_color", Color("#4caf50"))

	var pros_cap: int = Balance.TERRAIN.get(region.terrain, {}).get("prosperity_cap", 100)
	prosperity_label.text = "Prosperita: %d / %d" % [region.prosperity, pros_cap]

func _format_income(region: Region) -> String:
	var inc := region.get_income()
	return "%dG / %dM / %dR" % [int(inc["gold"]), int(inc["mana"]), int(inc["research"])]

# --------------------------
# UNITS SECTION

func _update_units_section(region_id: int) -> void:
	var units = GameState.query.units.in_region(region_id, false)
	if units.is_empty():
		units_section.visible = false
		return

	units_section.visible = true
	units_header.text = "▶ JEDNOTKY (%d)" % units.size()
	units_content.visible = false

	for child in units_content.get_children():
		child.queue_free()

	for u in units:
		var label := Label.new()
		var faction_name := _format_faction(u.faction_id)
		var warband_str: String = ""
		if u.is_warband():
			var t: int = u.turns_remaining
			var tah_str: String = "tah" if t == 1 else ("tahy" if t < 5 else "tahů")
			warband_str = "  ⏳ %d %s" % [t, tah_str]
		label.text = "%s  [%s]  sila: %d  stav: %s%s" % [u.name, faction_name, u.power, u.state_label(), warband_str]
		label.add_theme_font_size_override("font_size", 12)
		if u.faction_id == Balance.PLAYER_FACTION:
			label.add_theme_color_override("font_color", Color("#4caf50"))
		else:
			label.add_theme_color_override("font_color", Color("#f44336"))
		units_content.add_child(label)

func _format_faction(faction_id: String) -> String:
	match faction_id:
		Balance.PLAYER_FACTION: return "Temny pan"
		"paladin":              return "Paladini"
		"elf":                  return "Elfove"
		"inquisition":          return "Inkvizice"
		"orc":                  return "Orkove"
		_:                      return faction_id

# --------------------------
# TAGS SECTION

func _update_tags_section(region_id: int) -> void:
	var region: Region = GameState.query.regions.get_by_id(region_id)
	var visible_tags: Array = region.tags.filter(func(t): return t.get("visible", false))
	if visible_tags.is_empty():
		tags_section.visible = false
		return

	tags_section.visible = true
	tags_header.text = "▶ EFEKTY (%d)" % visible_tags.size()
	tags_content.visible = false

	for child in tags_content.get_children():
		child.queue_free()

	for tag in visible_tags:
		var label := Label.new()
		var dname: String = tag.get("display_name", tag.get("id", "?"))
		var duration_str: String
		if tag.get("ticks_down", false):
			duration_str = "(ještě %d tahů)" % tag.get("duration", 0)
		else:
			duration_str = "(aktivní)"
		var effects_str: String = _format_tag_effects(tag)
		if effects_str != "":
			label.text = "* %s %s - %s" % [dname, duration_str, effects_str]
		else:
			label.text = "* %s %s" % [dname, duration_str]
		label.add_theme_font_size_override("font_size", 12)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		tags_content.add_child(label)

func _format_tag_effects(tag: Dictionary) -> String:
	var parts: Array[String] = []

	var mul: Dictionary = tag.get("mul", {})
	for key in mul:
		var val: float = float(mul[key])
		parts.append("× %s %s" % [_fmt_float(val), key.replace("_", " ")])

	var add_vals: Dictionary = tag.get("add", {})
	for key in add_vals:
		var val: float = float(add_vals[key])
		var lbl: String = key.replace("_", " ")
		if val >= 0.0:
			parts.append("+%s %s" % [_fmt_float(val), lbl])
		else:
			parts.append("%s %s" % [_fmt_float(val), lbl])

	return "  ".join(parts)

func _fmt_float(val: float) -> String:
	if is_equal_approx(val, float(int(val))):
		return str(int(val))
	return "%.2f" % val

# --------------------------
# SECRETS SECTION

func _update_secrets_section(region_id: int) -> void:
	var region: Region = GameState.query.regions.get_by_id(region_id)
	if not (region.secret_known and region.has_secret()):
		secrets_section.visible = false
		return

	secrets_section.visible = true
	secrets_header.text = "▶ TAJEMSTVI"
	secrets_content.visible = false

	for child in secrets_content.get_children():
		child.queue_free()

	var sconf: Dictionary = Balance.SECRET.get(region.secret_id, {})
	var sname: String = sconf.get("display_name", region.secret_id)
	var difficulty: int = int(sconf.get("difficulty", 0))

	var label := Label.new()
	if region.secret_state == "resolved":
		label.text = "%s (vyreseno)" % sname
		label.add_theme_color_override("font_color", Color("#888888"))
	else:
		var progress: int = min(region.secret_progress, difficulty) if difficulty > 0 else region.secret_progress
		label.text = "%s: %d/%d" % [sname, progress, difficulty]
	label.add_theme_font_size_override("font_size", 12)
	secrets_content.add_child(label)

# --------------------------
# LAIR INFO

func _refresh_lair_info(region: Region) -> void:
	if not region.has_lair():
		lair_info_section.visible = false
		return

	lair_info_section.visible = true
	lair_info_header.text = "▶ DOUPĚ"
	lair_info_content.visible = false

	var lair_cfg: Dictionary = Balance.LAIR.get(region.lair_id, {})
	var display_name: String = lair_cfg.get("display_name", region.lair_id)

	lair_info_label.text = display_name
	lair_influence_label.text = "Vliv: %d / %d" % [
		region.lair_influence,
		Balance.LAIR_INFLUENCE_CONTROL_THRESHOLD
	]

	if region.lair_control == "player":
		lair_control_label.text = "Stav: Pod kontrolou"
		lair_decay_label.visible = true
		lair_decay_label.text = "Úbytek: −%d / tah" % Balance.LAIR_INFLUENCE_DECAY
	else:
		lair_control_label.text = "Stav: Neutrální"
		lair_decay_label.visible = false

# --------------------------
# LAIR DIRECTIVE

func _refresh_lair_directive(region: Region) -> void:
	if not region.has_lair() or region.lair_control != "player":
		lair_directive_options.visible = false
		return
	lair_directive_options.visible = true
	var is_defensive: bool = region.lair_directive == Balance.LAIR_DIRECTIVE_DEFENSIVE
	defensive_button.disabled = is_defensive
	raider_button.disabled = not is_defensive

func _on_defensive_pressed() -> void:
	if _region == null:
		return
	_region.lair_directive = Balance.LAIR_DIRECTIVE_DEFENSIVE
	GameState.world_ai_manager.update_lair_actor_profile(_region.id)
	_refresh_lair_directive(_region)

func _on_raider_pressed() -> void:
	if _region == null:
		return
	_region.lair_directive = Balance.LAIR_DIRECTIVE_RAIDER
	GameState.world_ai_manager.update_lair_actor_profile(_region.id)
	_refresh_lair_directive(_region)

# --------------------------
# NETWORK FACTION

func _refresh_network_faction(region: Region) -> void:
	var data: Dictionary = GameState.faction_manager.get_network_faction_display_data(region.id)
	if data.is_empty():
		network_faction_section.visible = false
		return

	network_faction_section.visible = true
	var type_display: String = {"cult": "Kult", "crime_syndicate": "Syndikát", "shadow_network": "Stínová síť"}.get(data["network_type"], data["network_type"])
	network_faction_header.text = "▶ ORGANIZACE — %s" % type_display
	network_faction_content.visible = false

	network_faction_name_label.text = data["display_name"]

	var founder: String = data.get("founder_name", "")
	if not founder.is_empty():
		network_founder_label.text = "Vůdce: %s" % founder
		network_founder_label.visible = true
	else:
		network_founder_label.visible = false

	network_influence_label.text = "Vliv: %d" % data["influence"]

	var loyalty: int = data["loyalty"]
	var phase_text: String
	var phase_color: Color
	if data["is_rogue"]:
		phase_text = "Odpadlá"
		phase_color = Color("#f44336")
	elif loyalty >= Balance.ORG_LOYALTY_FAITHFUL:
		phase_text = "Věrná"
		phase_color = Color("#4caf50")
	elif loyalty >= Balance.ORG_LOYALTY_STABLE:
		phase_text = "Stabilní"
		phase_color = Color("#ffd700")
	else:
		phase_text = "Nestabilní"
		phase_color = Color("#f44336")
	network_loyalty_label.text = "%d — %s" % [loyalty, phase_text]
	network_loyalty_label.add_theme_color_override("font_color", phase_color)

	var show_doctrine: bool = data["is_player_org"] and not data["is_rogue"]
	network_doctrine_container.visible = show_doctrine
	if show_doctrine:
		_populate_network_doctrine_picker(region.id)


func _populate_network_doctrine_picker(region_id: int) -> void:
	network_doctrine_picker.clear()
	_nf_doctrine_keys.clear()
	var doctrines: Array[Dictionary] = GameState.faction_manager.get_available_doctrines_by_region(region_id)
	var current_idx: int = 0
	for i in doctrines.size():
		var d: Dictionary = doctrines[i]
		network_doctrine_picker.add_item(d["display_name"])
		_nf_doctrine_keys.append(d["key"])
		if d["is_current"]:
			current_idx = i
	network_doctrine_picker.select(current_idx)
	_update_network_doctrine_effects(region_id)


func _update_network_doctrine_effects(region_id: int) -> void:
	var doctrines: Array[Dictionary] = GameState.faction_manager.get_available_doctrines_by_region(region_id)
	var selected: int = network_doctrine_picker.selected
	if selected < 0 or selected >= doctrines.size():
		network_doctrine_effects.text = ""
		return
	network_doctrine_effects.text = _format_nf_effects(doctrines[selected]["effects"])


func _on_network_doctrine_selected(index: int) -> void:
	if _region == null or index < 0 or index >= _nf_doctrine_keys.size():
		return
	var new_key: String = _nf_doctrine_keys[index]
	var data: Dictionary = GameState.faction_manager.get_network_faction_display_data(_region.id)
	if new_key == data.get("doctrine", ""):
		return
	GameState.faction_manager.set_doctrine_by_region(_region.id, new_key)
	_update_network_doctrine_effects(_region.id)


func _format_nf_effects(effects: Dictionary) -> String:
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
		parts.append("+%d%% šance na mise" % int(effects["mission_bonus"]))
	if effects.get("dark_action_empowered", false):
		parts.append("Dark Actions zesíleny")
	if parts.is_empty():
		return "Žádné pasivní efekty"
	return "  ".join(parts)

# --------------------------
# TOGGLE HELPER

func _toggle_section(content: VBoxContainer, header: Button) -> void:
	content.visible = not content.visible
	var title: String = header.text.substr(2)
	header.text = ("▼ " if content.visible else "▶ ") + title
