extends HBoxContainer

signal highlight_regions_requested(region_ids: Array[int], color: Color)
signal clear_highlights_requested()

const ALERT_COLOR = Color(1.0, 0.65, 0.0, 0.35)

@onready var agents_badge: Button = $AgentsBadge
@onready var org_badge: Button = $OrgBadge
@onready var heat_badge: Button = $HeatBadge
@onready var awareness_badge: Button = $AwarenessBadge
@onready var ap_badge: Button = $APBadge
@onready var ap_label: Label = $APBadge/APLabel

var _active_highlight_badge: String = ""
var _idle_agent_regions: Array[int] = []
var _low_loyalty_org_regions: Array[int] = []


func _ready() -> void:
	GameState.game_updated.connect(_on_game_updated)
	agents_badge.pressed.connect(_on_agents_badge_pressed)
	org_badge.pressed.connect(_on_org_badge_pressed)
	heat_badge.pressed.connect(_on_heat_badge_pressed)
	awareness_badge.pressed.connect(_on_awareness_badge_pressed)
	ap_badge.pressed.connect(_on_ap_badge_pressed)
	_on_game_updated()


func _on_game_updated() -> void:
	_refresh_agents_badge()
	_refresh_org_badge()
	_refresh_heat_badge()
	_refresh_awareness_badge()
	_refresh_ap_badge()


func _refresh_agents_badge() -> void:
	var planned_unit_ids: Array[int] = []
	for m: Mission in GameState.mission_manager.planned_missions:
		if m.unit != null:
			planned_unit_ids.append(m.unit.id)

	_idle_agent_regions.clear()
	var idle_agents: Array = []
	var player_units: Array = GameState.query.units.by_faction.get(Balance.PLAYER_FACTION, [])
	for u: Unit in player_units:
		if not u.is_busy and not u.is_lost and not u.is_wounded and u.id not in planned_unit_ids:
			_idle_agent_regions.append(u.region_id)
			idle_agents.append(u)

	agents_badge.visible = not _idle_agent_regions.is_empty()
	if idle_agents.is_empty():
		agents_badge.tooltip_text = ""
	else:
		var tooltip: String = "Agenti bez mise (%d)" % idle_agents.size()
		for u: Unit in idle_agents:
			var region_name: String = GameState.region_manager.get_region(u.region_id).name
			tooltip += "\n• %s — %s" % [u.name, region_name]
		agents_badge.tooltip_text = tooltip


func _refresh_org_badge() -> void:
	_low_loyalty_org_regions.clear()
	var low_loyalty_orgs: Array = []
	for org: Dictionary in GameState.org_manager.get_player_orgs():
		if org["loyalty"] < 30:
			_low_loyalty_org_regions.append(org["region_id"])
			low_loyalty_orgs.append(org)

	org_badge.visible = not _low_loyalty_org_regions.is_empty()
	if low_loyalty_orgs.is_empty():
		org_badge.tooltip_text = ""
	else:
		var tooltip: String = "Nestabilní organizace (%d)" % low_loyalty_orgs.size()
		for org: Dictionary in low_loyalty_orgs:
			var org_name: String = Balance.ORG[org["org_type"]]["display_name"]
			var region_name: String = GameState.region_manager.get_region(org["region_id"]).name
			tooltip += "\n• %s — %s (loajalita: %d)" % [org_name, region_name, org["loyalty"]]
		org_badge.tooltip_text = tooltip


func _refresh_heat_badge() -> void:
	heat_badge.visible = GameState.heat >= Balance.HEAT_STAGE_3
	if heat_badge.visible:
		heat_badge.tooltip_text = "Heat je kritický (%d)\nSíly dobra zvýšily aktivitu." % GameState.heat
	else:
		heat_badge.tooltip_text = ""


func _refresh_awareness_badge() -> void:
	awareness_badge.visible = GameState.awareness >= Balance.AWARENESS_STAGE_INQUISITOR
	if awareness_badge.visible:
		awareness_badge.tooltip_text = "Awareness je kritická (%d)\nInkvizitor může být aktivní." % GameState.awareness
	else:
		awareness_badge.tooltip_text = ""


func _refresh_ap_badge() -> void:
	var faction: Faction = GameState.faction_manager.get_faction(Balance.PLAYER_FACTION)
	var ap: int = faction.dark_actions_left if faction != null else 0
	ap_badge.visible = ap > 0
	ap_label.text = str(ap)
	if ap > 0:
		ap_badge.tooltip_text = "Nevyužité Dark Actions (%d)\nZbývající AP propadnou na konci tahu." % ap
	else:
		ap_badge.tooltip_text = ""


func _on_agents_badge_pressed() -> void:
	_handle_highlight_click("agents", _idle_agent_regions)


func _on_org_badge_pressed() -> void:
	_handle_highlight_click("orgs", _low_loyalty_org_regions)


func _on_heat_badge_pressed() -> void:
	pass


func _on_awareness_badge_pressed() -> void:
	pass


func _on_ap_badge_pressed() -> void:
	pass


func _handle_highlight_click(badge_name: String, region_ids: Array[int]) -> void:
	if _active_highlight_badge == badge_name:
		_active_highlight_badge = ""
		emit_signal("clear_highlights_requested")
	else:
		_active_highlight_badge = badge_name
		emit_signal("highlight_regions_requested", region_ids, ALERT_COLOR)
