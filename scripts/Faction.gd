extends Resource
class_name Faction

@export var id:String
@export var name:String
@export var is_player:bool = false

var resources := {
	"gold": 0.0,
	"mana": 0.0,
	"infamy": 0.0,
	"research": 0.0,
}

var dark_actions_max: int = 0
var dark_actions_left: int = 0
var infernal_pact_count: int = 0 
var unit_limit: int = 1

var ai_defend_own_territory: bool = true
var ai_defend_other_factions: bool = false
var ai_can_attack_lairs: bool = false
var ai_regular_spawns_enabled: bool = false
var ai_final_crusade: bool = false
var ai_spawn_rate: float = 0
var ai_spawn_unit: String = ""

func change_resource(kind:String, amount:float) -> void:
	if not resources.has(kind):
		push_error("Faction %s: unknown resource '%s'" % [id, kind])
		return
	resources[kind] += amount

func get_resource(kind:String) -> float:
	return resources.get(kind, 0.0)
