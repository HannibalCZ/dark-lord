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
	var player_units: Array = GameState.query.units.by_faction.get(Balance.PLAYER_FACTION, [])
	for u: Unit in player_units:
		if u.state == "healthy" and u.id not in planned_unit_ids:
			_idle_agent_regions.append(u.region_id)

	agents_badge.visible = not _idle_agent_regions.is_empty()


func _refresh_org_badge() -> void:
	_low_loyalty_org_regions.clear()
	for org: Dictionary in GameState.org_manager.get_player_orgs():
		if org["loyalty"] < 30:
			_low_loyalty_org_regions.append(org["region_id"])

	org_badge.visible = not _low_loyalty_org_regions.is_empty()


func _refresh_heat_badge() -> void:
	heat_badge.visible = GameState.heat >= Balance.HEAT_STAGE_3


func _refresh_awareness_badge() -> void:
	awareness_badge.visible = GameState.awareness >= Balance.AWARENESS_STAGE_INQUISITOR


func _refresh_ap_badge() -> void:
	var faction: Faction = GameState.faction_manager.get_faction(Balance.PLAYER_FACTION)
	var ap: int = faction.dark_actions_left if faction != null else 0
	ap_badge.visible = ap > 0
	ap_label.text = str(ap)


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
