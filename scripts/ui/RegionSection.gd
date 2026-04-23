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

@onready var units_section: PanelContainer = $UnitsSection
@onready var units_header: Button          = $UnitsSection/VBoxContainer/UnitsHeader
@onready var units_content: VBoxContainer  = $UnitsSection/VBoxContainer/UnitsContent

@onready var tags_section: PanelContainer = $TagsSection
@onready var tags_header: Button          = $TagsSection/VBoxContainer/TagsHeader
@onready var tags_content: VBoxContainer  = $TagsSection/VBoxContainer/TagsContent

@onready var secrets_section: PanelContainer = $SecretsSection
@onready var secrets_header: Button          = $SecretsSection/VBoxContainer/SecretsHeader
@onready var secrets_content: VBoxContainer  = $SecretsSection/VBoxContainer/SecretsContent

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

	units_header.pressed.connect(func(): _toggle_section(units_content, units_header))
	tags_header.pressed.connect(func(): _toggle_section(tags_content, tags_header))
	secrets_header.pressed.connect(func(): _toggle_section(secrets_content, secrets_header))

func show_for_region(region_id: int) -> void:
	if region_id == -1:
		visible = false
		return
	visible = true
	var region: Region = GameState.query.regions.get_by_id(region_id)
	if region == null:
		return
	_update_region_section(region)
	_update_units_section(region_id)
	_update_tags_section(region_id)
	_update_secrets_section(region_id)

# --------------------------
# REGION SECTION

func _update_region_section(region: Region) -> void:
	region_name_label.text = region.name
	region_owner.text = region.controller_faction_id

	var max_def: int = Balance.REGION_TYPE.get(region.region_type, {}).get("defense", 3)
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
		occupation_label.visible = false

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
		label.text = "%s  [%s]  sila: %d  stav: %s" % [u.name, faction_name, u.power, u.state]
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
		var effects_str: String = _format_tag_effects(tag)
		if effects_str != "":
			label.text = "* %s - %s" % [dname, effects_str]
		else:
			label.text = "* %s" % dname
		label.add_theme_font_size_override("font_size", 12)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		tags_content.add_child(label)

func _format_tag_effects(tag: Dictionary) -> String:
	var parts: Array[String] = []
	var stat_labels := {
		"gold_income":       "prijem zlata",
		"mana_income":       "prijem many",
		"research_income":   "prijem vyzkumu",
		"fear":              "strach",
		"defense":           "obrana",
		"ai_agent_priority": "priorita AI"
	}

	var mul: Dictionary = tag.get("mul", {})
	for stat in mul:
		var val: float = float(mul[stat])
		var lbl: String = stat_labels.get(stat, stat)
		parts.append("%s x%s" % [lbl, _fmt_float(val)])

	var add_vals: Dictionary = tag.get("add", {})
	for stat in add_vals:
		var val: float = float(add_vals[stat])
		var lbl: String = stat_labels.get(stat, stat)
		if val >= 0.0:
			parts.append("+%s %s" % [_fmt_float(val), lbl])
		else:
			parts.append("%s %s" % [_fmt_float(val), lbl])

	return "  ".join(parts)

func _fmt_float(val: float) -> String:
	if is_equal_approx(val, float(int(val))):
		return str(int(val))
	return "%.2g" % val

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
# TOGGLE HELPER

func _toggle_section(content: VBoxContainer, header: Button) -> void:
	content.visible = not content.visible
	var title: String = header.text.substr(2)
	header.text = ("▼ " if content.visible else "▶ ") + title
