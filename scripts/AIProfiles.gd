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
			# Očekávaná skóre per Heat threshold (referenční tabulka pro ladění):
			# Heat  | patrol | threaten | assault | Vítěz
			# < 25  |  0.30  |   0.20   |  0.10   | patrol
			# 25-50 |  0.45  |   0.20   |  0.10   | patrol
			# 50-85 |  0.90  |   0.40   |  0.10   | patrol
			# 85-100|  0.27  |   0.80   |  0.20   | threaten
			# 100+  |  0.27  |   0.80   |  1.00   | assault

			# Hlídkování — základní reakce na rostoucí Heat; potlačeno při eskalaci (×0.3 nad 85)
			"patrol": {
				"base_score": 0.3,
				"goal": "maintain_order",
				"score_modifiers": [
					{ "condition": "heat > 25", "multiplier": 1.5 },
					{ "condition": "heat > 50", "multiplier": 2.0 },
					{ "condition": "heat > 85", "multiplier": 0.3 }
				],
				"handler": "spawn_unit",
				"handler_params": { "unit_key": "paladin_army" }
			},

			# Výhrůžka — mobilizace od Heat 50, dominuje na 85–100
			"threaten": {
				"base_score": 0.2,
				"goal": "eliminate_darkness",
				"score_modifiers": [
					{ "condition": "heat > 50", "multiplier": 2.0 },
					{ "condition": "heat > 85", "multiplier": 4.0 }
				],
				"handler": "move_army_toward_player",
				"handler_params": {},
				"target": {
					"select": "nearest",
					"filters": { "owner_rule": "good_faction" }
				}
			},

			# Útok — eskalace nad 85, dominuje při Heat 100+
			"assault": {
				"base_score": 0.1,
				"goal": "eliminate_darkness",
				"score_modifiers": [
					{ "condition": "heat > 85", "multiplier": 2.0 },
					{ "condition": "heat > 100", "multiplier": 10.0 }
				],
				"handler": "attack_player_base",
				"handler_params": {},
				"target": {
					"select": "nearest",
					"filters": { "owner_rule": "player" }
				}
			}
		}
	},

	"inquisition": {
		"display_name": "Inkvizice",
		"plan_switch_threshold": 0.20,

		"goals": {
			"eliminate_darkness": 1.0,
			"investigate_threats": 0.8
		},

		"actions": {
			# Awareness | dormant | investigate | Vítěz
			# < 30      |  0.60   |    0.20     | dormant
			# 30–50     |  0.30   |    0.40     | investigate
			# 50+       |  0.09   |    1.60     | investigate

			"dormant": {
				"base_score": 0.6,
				"goal": "eliminate_darkness",
				"score_modifiers": [
					{ "condition": "awareness > 30", "multiplier": 0.5 },
					{ "condition": "awareness > 50", "multiplier": 0.3 }
				],
				"handler": "stay_dormant",
				"handler_params": {}
			},

			"investigate": {
				"base_score": 0.2,
				"goal": "investigate_threats",
				"score_modifiers": [
					{ "condition": "awareness > 30", "multiplier": 2.0 },
					{ "condition": "awareness > 50", "multiplier": 4.0 }
				],
				"handler": "activate_inquisition",
				"handler_params": {}
			}
		}
	},

	"elf": {
		"plan_switch_threshold": 0.20,
		"goals": {
			"expand_territory": 1.0
		},
		"actions": {
			"colonize": {
				"base_score": 0.5,
				"goal": "expand_territory",
				"score_modifiers": [],
				"handler": "spawn_colonist",
				"handler_params": {},
				"conditions": []
			}
		}
	},

	# Heat   | trade | defend | Vítěz
	# < 25   |  0.60 |  0.20  | trade
	# 25–50  |  0.60 |  0.40  | trade
	# 50–85  |  0.42 |  0.60  | defend
	# 85+    |  0.21 |  0.60  | defend
	"merchant": {
		"display_name": "Obchodní města",
		"plan_switch_threshold": 0.20,

		"goals": {
			"maintain_trade": 1.0,
			"protect_territory": 0.6
		},

		"actions": {
			"trade": {
				"base_score": 0.6,
				"goal": "maintain_trade",
				"score_modifiers": [
					{ "condition": "heat > 50", "multiplier": 0.7 },
					{ "condition": "heat > 85", "multiplier": 0.5 }
				],
				"handler": "merchant_trade",
				"handler_params": {}
			},

			"defend": {
				"base_score": 0.2,
				"goal": "protect_territory",
				"score_modifiers": [
					{ "condition": "heat > 25", "multiplier": 2.0 },
					{ "condition": "heat > 50", "multiplier": 3.0 }
				],
				"handler": "merchant_defend",
				"handler_params": {}
			}
		}
	}
}
