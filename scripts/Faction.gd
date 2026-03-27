extends Resource
class_name Faction

enum Behavior {
	PASSIVE,      # Heat < 25  — výchozí stav
	PATROLLING,   # Heat >= 25 — hlídkování na vlastním území
	AGGRESSIVE,   # Heat >= 50 — útok na lairy
	COORDINATED   # Heat >= 75 — koordinovaný útok
}

var current_behavior: Behavior = Behavior.PASSIVE

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

var ai_regular_spawns_enabled: bool = false
var ai_spawn_unit: String = ""
var spawn_counter: int = 0

func change_resource(kind:String, amount:float) -> void:
	if not resources.has(kind):
		push_error("Faction %s: unknown resource '%s'" % [id, kind])
		return
	resources[kind] += amount

func get_resource(kind:String) -> float:
	return resources.get(kind, 0.0)
