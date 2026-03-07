# scripts/classes/Unit.gd
extends Resource
class_name Unit

var id: int = -1
var unit_key:String
var faction_id: String
var region_id: int = -1        # ID regionu, kde se jednotka nachází (zatím -1 = základna)
var name: String = ""
var type: String = ""     # "agent" nebo "army"
var power: int = 0
var state: String = "healthy"  # "healthy", "busy", "lost"
var moves_per_turn: int = 1
var moves_left: int = 1

func init(_id:int, _unit_temp:String, _region_id:int, _faction_id:String) -> Unit:
	id = _id
	unit_key = _unit_temp 
	region_id = _region_id
	faction_id = _faction_id
	
	var unit_temp = Balance.UNIT.get(_unit_temp,{})
	
	name = unit_temp.get("display_name", "")
	type = unit_temp.get("type", "")
	power = unit_temp.get("power", 0)
	moves_per_turn = unit_temp.get("moves", 0)
	moves_left = moves_per_turn
	return self

func is_available() -> bool:
	return state == "healthy"

func is_agent() -> bool:
	return type == "agent"

func is_army() -> bool:
	return type == "army"

func mark_busy() -> void:
	state = "busy"

func mark_lost() -> void:
	state = "lost"

func mark_healthy() -> void:
	state = "healthy"

func can_do_mission(key:String) -> bool:
	var cfg: Dictionary = Balance.UNIT.get(unit_key, {})
	var arr: Array = cfg.get("can_do", [])
	return key in arr
	
func can_perform_mission(mission_type:int) -> bool:
	# 1) mapuj enum → mission key (např. "sabotage")
	var mkey: String = Balance.mission_key_from_enum(mission_type)
	if mkey == "":
		return false

	# 2) načti definici jednotky a její whitelist "can_do"
	var ucfg: Dictionary = Balance.UNIT.get(unit_key, {})
	if ucfg.is_empty():
		return false

	var allowed: Array = ucfg.get("can_do", [])
	return mkey in allowed
		
