# scripts/AIProfiles.gd
# Konfigurace všech AI aktérů — cíle, akce, utility scoring.
# Čte se pouze — žádné runtime mutace.
extends Node

# ---------------------------------------------------------------------------
# Formát záznamu v ACTORS:
#
# "actor_key": {
#     "display_name": String          — lokalizovaný název pro UI/log
#     "plan_switch_threshold": float  — minimální relativní zlepšení utility
#                                       aby se plán přepnul (0.0–1.0)
#     "goals": {
#         "goal_key": float           — váha cíle; ovlivňuje výsledné skóre
#     }
#     "actions": {
#         "action_key": {
#             "base_score": float     — základní utility před modifikátory
#             "goal": String          — klíč cíle z goals{}; akce přispívá
#                                       k tomuto cíli
#             "score_modifiers": [    — seznam podmínek aplikovaných v pořadí
#                 {
#                     "condition": String   — výraz vyhodnocovaný v AIManager:
#                                             dostupné proměnné:
#                                               heat       (int, 0–100)
#                                               awareness  (int, 0–100)
#                                               infamy     (int, 0–100)
#                                               turn       (int)
#                                             operátory: > < >= <= ==
#                                             příklad: "heat > 50"
#                     "multiplier": float   — koeficient aplikovaný na base_score
#                                             když je podmínka splněna;
#                                             modifikátory se násobí (ne sčítají)
#                 }
#             ]
#             "handler": String       — klíč handleru v AIManager._handlers;
#                                       dostupné handlery:
#                                         "spawn_unit"            — spawne jednotku v regionu
#                                         "move_army_toward_player" — přesune armádu k hráči
#                                         "attack_player_base"    — zahájí útok na hráčovu základnu
#             "handler_params": {}    — parametry předané handleru;
#                                       "spawn_unit" vyžaduje: { "unit_key": String }
#         }
#     }
# }
# ---------------------------------------------------------------------------

const ACTORS: Dictionary = {
	"paladin": {
		"display_name": "Paladinská říše",
		# Minimální relativní nárůst utility (vůči aktuálnímu plánu) pro přepnutí.
		# Např. 0.25 = nový plán musí být o 25 % lepší než stávající.
		"plan_switch_threshold": 0.25,

		# Cíle aktéra — klíče referencují actions[x].goal
		"goals": {
			"maintain_order": 1.0,
			"protect_territory": 0.8,
			"eliminate_darkness": 0.6
		},

		"actions": {
			# Hlídkování — základní reakce na rostoucí Heat
			"patrol": {
				"base_score": 0.3,
				"goal": "maintain_order",
				"score_modifiers": [
					{ "condition": "heat > 25", "multiplier": 1.5 },
					{ "condition": "heat > 50", "multiplier": 2.0 }
				],
				"handler": "spawn_unit",
				"handler_params": { "unit_key": "paladin_army" }
			},

			# Výhrůžka — mobilizace při vysokém Heat
			"threaten": {
				"base_score": 0.1,
				"goal": "eliminate_darkness",
				"score_modifiers": [
					{ "condition": "heat > 85", "multiplier": 5.0 }
				],
				"handler": "move_army_toward_player",
				"handler_params": {}
			},

			# Útok — eskalace při překročení Heat stropu
			"assault": {
				"base_score": 0.05,
				"goal": "eliminate_darkness",
				"score_modifiers": [
					{ "condition": "heat > 100", "multiplier": 10.0 }
				],
				"handler": "attack_player_base",
				"handler_params": {}
			}
		}
	}
}
