# scripts/ui/MissionsTab.gd
extends Control

@onready var units_list    : ItemList = $VBoxContainer/UnitsList
@onready var missions_list : ItemList = $VBoxContainer/MissionsList
@onready var cancel_btn    : Button   = $VBoxContainer/Button

func _ready() -> void:
	GameState.connect("turn_resolved", Callable(self, "_refresh"))
	GameState.connect("game_updated", Callable(self, "_refresh"))
	_refresh()
	cancel_btn.pressed.connect(_on_cancel_pressed)

func _refresh() -> void:
	units_list.clear()
	for u: Unit in GameState.unit_manager.units:
		units_list.add_item("%s | %s | Síla:%d | Stav:%s" % [u.name, u.type, u.power, u.state])

	missions_list.clear()
	for m: Mission in GameState.mission_manager.planned_missions:
		if m == null or m.unit == null or m.region == null:
			missions_list.add_item("⚠ Neplatná mise")
			continue

		var key := m.mission_key
		var cfg: Dictionary = Balance.MISSION.get(key, {})
		var mname := String(cfg.get("display_name", key))

		missions_list.add_item("%s -> %s (%s)" % [m.unit.name, m.region.name, mname])

func _on_cancel_pressed() -> void:
	var idx := missions_list.get_selected_items()
	if idx.size() == 0:
		return
	GameState.cancel_mission(idx[0])
