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
	},

	"cult_network": {
		"display_name": "Kult",
		"plan_switch_threshold": 0.15,
		"goals": { "grow_influence": 1.0, "generate_resources": 0.4 },
		"actions": {
			# visibility | grow  | generate | hide  | expand | suppress | Vítěz
			# < 50       |  0.70 |   0.30   | 0.20  |  0.40  |   0.50   | grow
			# 50–70      |  0.35 |   0.09   | 0.50  |  0.40  |   0.50   | suppress/hide
			# > 70       |  0.35 |   0.03   | 1.25  |  0.40  |   0.50   | hide
			"grow": {
				"base_score": 0.70,
				"goal": "grow_influence",
				"effects": { "influence": 8, "visibility": 5 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 50", "multiplier": 0.5 }
				],
				"doctrine_modifiers": {
					"dark_rituals":       1.3,
					"ritual_empowerment": 1.1,
					"extortion": 1.0, "laundering": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			},
			"generate": {
				"base_score": 0.30,
				"goal": "generate_resources",
				"effects": { "gold": 3.0, "visibility": 8 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 70", "multiplier": 0.3 }
				],
				"doctrine_modifiers": {
					"dark_rituals":       1.4,
					"ritual_empowerment": 1.0,
					"extortion": 1.0, "laundering": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			},
			"hide": {
				"base_score": 0.20,
				"goal": "grow_influence",
				"effects": { "visibility": -15 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 50", "multiplier": 2.5 }
				],
				"doctrine_modifiers": {
					"dark_rituals":       0.9,
					"ritual_empowerment": 0.8,
					"extortion": 1.0, "laundering": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			},
			"expand": {
				"base_score": 0.40,
				"goal": "grow_influence",
				"effects": { "influence_cost": 20, "gold_cost": 10, "initial_influence": 10, "visibility": 10 },
				"handler": "network_expand",
				"score_modifiers": [
					{ "condition": "influence > 60", "multiplier": 2.0 }
				],
				"doctrine_modifiers": {
					"dark_rituals":       1.0,
					"ritual_empowerment": 1.4,
					"extortion": 1.0, "laundering": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			},
			"suppress": {
				"base_score": 0.50,
				"goal": "grow_influence",
				"effects": { "rival_influence": -12, "visibility": 15 },
				"handler": "network_suppress",
				"score_modifiers": [
					{ "condition": "rival_present", "multiplier": 3.0 }
				],
				"doctrine_modifiers": {
					"dark_rituals":       0.8,
					"ritual_empowerment": 1.3,
					"extortion": 1.0, "laundering": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			}
		}
	},

	"crime_syndicate_network": {
		"display_name": "Zločinecký syndikát",
		"plan_switch_threshold": 0.15,
		"goals": { "generate_resources": 1.0, "grow_influence": 0.6 },
		"actions": {
			# visibility | generate | grow  | expand | suppress | hide  | Vítěz
			# < 50       |   0.70   | 0.30  |  0.50  |   0.40   | 0.30  | generate
			# 50–70      |   0.49   | 0.30  |  0.50  |   0.40   | 0.75  | hide
			# > 70       |   0.15   | 0.30  |  0.50  |   0.40   | 1.88  | hide
			"generate": {
				"base_score": 0.70,
				"goal": "generate_resources",
				"effects": { "gold": 3.0, "visibility": 8 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 70", "multiplier": 0.7 },
					{ "condition": "visibility > 50", "multiplier": 0.3 }
				],
				"doctrine_modifiers": {
					"extortion":  1.4,
					"laundering": 0.9,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			},
			"grow": {
				"base_score": 0.30,
				"goal": "grow_influence",
				"effects": { "influence": 8, "visibility": 5 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 50", "multiplier": 0.5 }
				],
				"doctrine_modifiers": {
					"extortion":  0.9,
					"laundering": 1.1,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			},
			"suppress": {
				"base_score": 0.40,
				"goal": "grow_influence",
				"effects": { "rival_influence": -12, "visibility": 15 },
				"handler": "network_suppress",
				"score_modifiers": [
					{ "condition": "rival_present", "multiplier": 3.0 }
				],
				"doctrine_modifiers": {
					"extortion":  1.3,
					"laundering": 0.8,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			},
			"hide": {
				"base_score": 0.30,
				"goal": "generate_resources",
				"effects": { "visibility": -15 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 50", "multiplier": 2.5 }
				],
				"doctrine_modifiers": {
					"extortion":  0.7,
					"laundering": 1.5,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			},
			"expand": {
				"base_score": 0.50,
				"goal": "grow_influence",
				"effects": { "influence_cost": 20, "gold_cost": 15, "initial_influence": 10, "visibility": 10 },
				"handler": "network_expand",
				"score_modifiers": [
					{ "condition": "influence > 60", "multiplier": 2.0 }
				],
				"doctrine_modifiers": {
					"extortion":  1.1,
					"laundering": 1.2,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "informants": 1.0, "disinfo": 1.0
				}
			}
		}
	},

	"shadow_network_network": {
		"display_name": "Stínová síť",
		"plan_switch_threshold": 0.15,
		"goals": { "grow_influence": 1.0, "generate_resources": 0.5 },
		"actions": {
			# visibility | hide  | suppress | grow  | generate | expand | Vítěz
			# < 50       |  0.60 |   0.60   | 0.40  |   0.30   |  0.30  | hide/suppress
			# 50–70      |  1.50 |   0.60   | 0.20  |   0.09   |  0.30  | hide
			# > 70       |  3.75 |   0.60   | 0.20  |   0.03   |  0.30  | hide
			"hide": {
				"base_score": 0.60,
				"goal": "grow_influence",
				"effects": { "visibility": -15 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 50", "multiplier": 2.5 }
				],
				"doctrine_modifiers": {
					"informants": 1.3,
					"disinfo":    1.5,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "extortion": 1.0, "laundering": 1.0
				}
			},
			"suppress": {
				"base_score": 0.60,
				"goal": "grow_influence",
				"effects": { "rival_influence": -12, "visibility": 15 },
				"handler": "network_suppress",
				"score_modifiers": [
					{ "condition": "rival_present", "multiplier": 3.0 }
				],
				"doctrine_modifiers": {
					"informants": 1.0,
					"disinfo":    1.2,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "extortion": 1.0, "laundering": 1.0
				}
			},
			"grow": {
				"base_score": 0.40,
				"goal": "grow_influence",
				"effects": { "influence": 8, "visibility": 5 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 50", "multiplier": 0.5 }
				],
				"doctrine_modifiers": {
					"informants": 1.2,
					"disinfo":    0.9,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "extortion": 1.0, "laundering": 1.0
				}
			},
			"generate": {
				"base_score": 0.30,
				"goal": "generate_resources",
				"effects": { "gold": 3.0, "visibility": 8 },
				"handler": "network_action",
				"score_modifiers": [
					{ "condition": "visibility > 70", "multiplier": 0.3 }
				],
				"doctrine_modifiers": {
					"informants": 0.8,
					"disinfo":    0.7,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "extortion": 1.0, "laundering": 1.0
				}
			},
			"expand": {
				"base_score": 0.30,
				"goal": "grow_influence",
				"effects": { "influence_cost": 20, "gold_cost": 12, "initial_influence": 10, "visibility": 10 },
				"handler": "network_expand",
				"score_modifiers": [
					{ "condition": "influence > 60", "multiplier": 2.0 }
				],
				"doctrine_modifiers": {
					"informants": 1.1,
					"disinfo":    0.8,
					"dark_rituals": 1.0, "ritual_empowerment": 1.0, "extortion": 1.0, "laundering": 1.0
				}
			}
		}
	},

	# ---------------------------------------------------------------------------
	# Lair profily — per-region frakce
	# ---------------------------------------------------------------------------
	"lair_neutral": {
		"display_name": "Neutrální doupě",
		"plan_switch_threshold": 0.5,
		"goals": { "survive": 1.0 },
		"actions": {
			"idle": {
				"base_score": 1.0,
				"handler": "lair_idle",
				"effects": {}
			}
		}
	},
	"lair_defensive": {
		"display_name": "Obranná direktiva",
		"plan_switch_threshold": 0.3,
		"goals": { "defend_lair": 1.0 },
		"actions": {
			"stay": {
				"base_score": 0.9,
				"handler": "lair_stay",
				"effects": {}
			},
			"raid": {
				"base_score": 0.1,
				"handler": "lair_raid",
				"effects": {}
			}
		}
	},
	"lair_raider": {
		"display_name": "Nájezdnická direktiva",
		"plan_switch_threshold": 0.3,
		"goals": { "raid_territory": 1.0 },
		"actions": {
			"stay": {
				"base_score": 0.1,
				"handler": "lair_stay",
				"effects": {}
			},
			"raid": {
				"base_score": 0.9,
				"handler": "lair_raid",
				"effects": {}
			}
		}
	},
}
