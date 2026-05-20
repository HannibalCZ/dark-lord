# scripts/models/AIActor.gd
# Runtime stav jednoho AI aktéra — jeden záznam per faction_id.
extends Resource
class_name AIActor

var faction_id: String = ""
# klíč frakce shodný s FactionManager a AIProfiles.ACTORS

var current_plan: String = ""
# klíč akce z AIProfiles.ACTORS[faction_id].actions;
# prázdný řetězec = žádný aktivní plán

var plan_utility: float = 0.0
# utility skóre v okamžiku přijetí current_plan;
# slouží jako referenční hodnota pro plan_switch_threshold

var plan_turn: int = 0
# tah kdy byl current_plan přijat; pro debug a budoucí time-decay

var last_decision_log: Dictionary = {}
# snapshot posledního rozhodnutí pro debug:
# { "turn": int, "scores": { action_key: float }, "chosen": String }

var current_target_region_id: int = -1
# Strategický cíl vypočtený WorldAI pro aktuální tah.
# -1 = žádný cíl (patrol plán, nebo WorldAI target ještě nebyl vypočten).
# Čte AIManager pro jednotky jejichž frakce má WorldAI AIActor.
