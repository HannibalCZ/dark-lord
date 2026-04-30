extends Resource
class_name Faction

enum Behavior {
	PASSIVE,      # Heat < 25  — výchozí stav
	PATROLLING,   # Heat >= 25 — hlídkování na vlastním území
	ACTING,   # Heat >= 50 — útok na lairy
	AGGRESSIVE,   # Heat >= 75 — pripravi se na hranice
	COORDINATED   # Heat >= 100 — koordinovaný útok
}

var current_behavior: Behavior = Behavior.PASSIVE

@export var id:String
@export var name:String
@export var is_player:bool = false
var alignment: String = "neutral"

var resources := {
	"gold": 0.0,
	"mana": 0.0,
	"infamy": 0.0,
	"research": 0.0,
}

# Modifikátory herních hodnot — mění se při odemčení
# progression uzlu přes EffectsSystem (TYP A konvence).
# Mohou být kladné i záporné.
# Čteny přímo manažery při výpočtu — ne přes
# EffectsSystem každý tah.
var modifiers: Dictionary = {
	"mission_success":     0.0,  # float, přičte se
								  # k base_chance v MissionManager
	"army_power":          0,    # int, přičte se k total power
								  # v CombatManager
	"gold_per_region":     0.0,  # float, přičte se za každý
								  # vlastněný region v EconomicManager
	"mana_income":         0.0,  # float, přičte se k mana příjmu
								  # v EconomicManager
	"ap_max_modifier":     0,    # int, přičte se k dark_actions_max
	"unit_limit_modifier": 0,    # int, přičte se k UnitManager.unit_limit
								  # (limit se čte z UnitManager, ne Faction)
}

var dark_actions_max: int = 0
var dark_actions_left: int = 0
var infernal_pact_count: int = 0 
var unit_limit: int = 1

var ai_regular_spawns_enabled: bool = false
var ai_spawn_unit: String = ""
var spawn_counter: int = 0
var explorer_spawned_count: int = 0
# Počet průzkumníků spawnutých pro tuto frakci (max 2).
# Čte GameState._try_spawn_explorer() (Task 5) a porovnává
# s Balance.EXPLORER_SPAWN[faction_id]["unit_limit"].
# Inkrementuje se při každém spawnu průzkumníka.

# Reputace — cachovana hodnota,
# prepocitavana ReputationManagerem kazdy tah
var reputation: int = 0
var reputation_phase: String = "neutral"
# "hostile" | "neutral" | "infiltrated" | "controlled"
var reputation_modifier: int = 0
# Heat threshold modifier: -10 / 0 / +10 / +99

func change_resource(kind:String, amount:float) -> void:
	if not resources.has(kind):
		push_error("Faction %s: unknown resource '%s'" % [id, kind])
		return
	resources[kind] += amount

func get_resource(kind:String) -> float:
	return resources.get(kind, 0.0)
