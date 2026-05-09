# managers/WorldAIManager.gd
# Řídí AI aktéry (paladíni a budoucí frakce) — utility scoring, plánování, dispatch.
# Voláno z GameState.advance_turn() sekce C po tags_manager.process_end_of_turn().
extends Resource
class_name WorldAIManager

var game_state: GameStateSingleton

# Interní stav aktérů — přistupovat pouze přes metody tohoto manažera.
var _actors: Dictionary = {}  # { faction_id: AIActor }

# ---------------------------------------------------------------------------
# Inicializace
# ---------------------------------------------------------------------------

# Vytvoří AIActor pro každý faction_id definovaný v AIProfiles.ACTORS.
# Volat z GameState.load_scenario() po načtení frakcí — ne z _ready().
func init_actors() -> void:
	_actors.clear()
	for faction_id in AIProfiles.ACTORS.keys():
		var actor := AIActor.new()
		actor.faction_id = faction_id
		_actors[faction_id] = actor

# ---------------------------------------------------------------------------
# Herní smyčka
# ---------------------------------------------------------------------------

# Hlavní entry point — volat z GameState.advance_turn().
func process_turn() -> void:
	for faction_id in _actors.keys():
		var actor: AIActor = _actors[faction_id]
		var profile: Dictionary = AIProfiles.ACTORS.get(faction_id, {})
		if profile.is_empty():
			continue
		_process_actor(actor, profile)

# ---------------------------------------------------------------------------
# Interní — jeden aktér
# ---------------------------------------------------------------------------

func _process_actor(actor: AIActor, profile: Dictionary) -> void:
	# 1. Vypočítej utility skóre pro všechny akce
	# 2. Najdi nejvýše hodnocenou akci
	# 3. Porovnej s aktivním plánem přes plan_switch_threshold
	# 4. Rozhodni zda pokračovat nebo přepnout
	# 5. Zaloguj rozhodnutí do actor.last_decision_log
	pass  # implementace v Task 3
