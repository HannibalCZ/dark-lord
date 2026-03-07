# scripts/data/Balance.gd
extends Node

const PLAYER_FACTION = "player"
const CORRUPTION_THRESHOLD = 50

const CORRUPTION_CONTROLLER_PHASE := 3

const CORRUPTION_PHASE_DATA := [
	{
		"id": 0,
		"name": "clean",
		"display_name": "Čistý",
		"min": 0,
		"max": 24,
		"owner_income_mult": 1.0,
		"controller_income_mult": 0.0,
		"fear_per_turn": 0,
		"ai_priority_bonus": 0,
	},
	{
		"id": 1,
		"name": "disturbed",
		"display_name": "Narušený",
		"min": 25,
		"max": 49,
		"owner_income_mult": 0.9,
		"controller_income_mult": 0.1,
		"fear_per_turn": 1,
		"ai_priority_bonus": 5,
	},
	{
		"id": 2,
		"name": "tainted",
		"display_name": "Zkažený",
		"min": 50,
		"max": 74,
		"owner_income_mult": 0.75,
		"controller_income_mult": 0.4,
		"fear_per_turn": 3,
		"ai_priority_bonus": 10,
	},
	{
		"id": 3,
		"name": "subverted",
		"display_name": "Podvržený",
		"min": 75,
		"max": 99,
		"owner_income_mult": 0.5,
		"controller_income_mult": 0.5,
		"fear_per_turn": 5,
		"ai_priority_bonus": 20,
	},
	{
		"id": 4,
		"name": "dominated",
		"display_name": "Dominovaný",
		"min": 100,
		"max": 9999, # prakticky neomezené
		"owner_income_mult": 0.0,
		"controller_income_mult": 1.0,
		"fear_per_turn": 7,
		"ai_priority_bonus": 30,
	}
]

const MISSION = {
	"sabotage": {
		"id": "sabotage",
		"display_name": "Sabotáž",
		"description": "Oslab infrastrukturu regionu a získej trochu zlata. Zvyšuje pozornost sil dobra.",
		"base_chance": 0.70,
		"requirements": {
			"region_kind_in": ["civilized"],
		},
		"cost": {              # připraveno – můžeš teď nebo později začít používat
			"ap": 1,
			"mana": 0,
			"gold": 0,
		},
		"success": { "heat":8, "gold":5, "defense":-15, "tags": ["blockade"] },
		"fail":    { "heat": 4 },
		"ui_icon": "res://ui/icons/missions/sabotage.png",
		"ui_order": 1
	},
	"corrupt": {
		"id": "corrupt",
		"display_name": "Korupce",
		"description": "Šíří skrytou korupci ve frakci, aby převzala kontrolu nad regionem.",
		"base_chance": 0.80,
		"requirements": {
			"region_kind_in": ["civilized"],
		},
		"cost": {
			"ap": 1,
			"mana": 0,
			"gold": 0,
		},
		"success": { "corruption": 60, "heat": 5  },
		"fail":    { "heat": 3 },
		"ui_icon": "res://ui/icons/missions/corrupt.png",
		"ui_order": 2
	},
	"raid": {
		"id": "raid",
		"display_name": "Nájezd",
		"description": "Vyplení region a získá zlato, ale zvyšuje HEAT a poškozuje obranu.",
		"base_chance": 0.60,
		"requirements": {
			"region_kind_in": ["civilized"],
		},
		"cost": {
			"ap": 1,
			"mana": 0,
			"gold": 0,
		},
		"success": { 
			"heat":20, "gold":12, "defense":-5, 
			"tags": ["raid"]},
		"fail":    {"heat": 8},
		"ui_icon": "res://ui/icons/missions/raid.png",
		"ui_order": 3
	},
	"purge": {
		"id": "purge",
		"display_name": "Očista",
		"description": "Sníží korupci všech frakcí v regionu. Používá ji spíš AI / hrdinové.",
		"base_chance": 0.70,
		"requirements": {
			"region_kind_in": ["civilized"],
		},
		"cost": {
			"ap": 1,
			"mana": 0,
			"gold": 0,
		},
		"success": { "purge_corruption_all": -30 },
		"fail":    {},
		"ui_icon": "res://ui/icons/missions/purge.png",
		"ui_order": 4
	},
	"explore": {
		"id": "explore",
		"display_name": "Pátrání",
		"description": "Tvůj agent postupně odhaluje tajemství skryté v divočině.",
		"base_chance": 0.80,
		"requirements": {
			"region_kind_in": ["wildlands"],
			"requires_secret": true,
			"secret_known": true,
			"secret_state_not_in": ["resolved"]
		},
		"cost": {
			"ap": 1,
			"mana": 0,
			"gold": 0,
		},
		# Explore jen posouvá odhalení tajemství.
		# Tajemství má svou 'difficulty' a vlastní 'effects' v SECRET.
		"success": {
			"secret_progress": 10,
			# volitelně malé bonusy, např. "infamy": 1
		},
		"fail": {
			"secret_progress": 5,
			"heat": 3
		},
		"ui_icon": "res://ui/icons/missions/explore.png",
		"ui_order": 5
	},
	"bribe": {
		"id": "bribe",
		"display_name": "Uplatit doupě",
		"description": "Zaplať zlato obyvatelům doupěte a získej jejich přízeň.",
		"base_chance": 0.80,
		"requirements": {
			"requires_lair": true
		},
		"cost": { "ap": 1, "mana": 0, "gold": 10 },
		"success": {
			"lair_influence": 5,      # nový typ efektu – ovlivní region.lair_influence
		},
		"fail": {
			"heat": 3,
		},
		"ui_icon": "res://ui/icons/missions/bribe.png",
		"ui_order": 6
	},

	"manipulate": {
		"id": "manipulate",
		"display_name": "Zmanipulovat doupě",
		"description": "Použij temná šeptání a kouzla k ovlivnění doupěte.",
		"base_chance": 0.50,
		"requirements": {
			"requires_lair": true
		},
		"cost": { "ap": 1, "mana": 8, "gold": 0 },
		"success": {
			"lair_influence": 7,
			"doom": 1,
		},
		"fail": {
			"heat": 4,
		},
		"ui_icon": "res://ui/icons/missions/manipulate.png",
		"ui_order": 7
	}
	
}

const DARK_ACTIONS = {
	"terrifying_whisper": {
		"display_name": "Zvěsti o hrůze",
		"description": "Vysílá šeptané zvěsti a zvyšuje strach v regionu. Mírně zvyšuje HEAT.",
		"type": "region",
		"mana_cost": 10,
		"ap_cost": 1,
		"cooldown": 2,
		"effects": { 
			"heat":2,  
			"tags": ["fear_boost"]}
	},
	"decoy": {
		"display_name": "Stínová návnada",
		"description": "Odvádí pozornost hrdinů do vybraného regionu. Zvyšuje šanci, že se AI zaměří sem.",
		"type": "region",
		"mana_cost": 10,
		"ap_cost": 1,
		"cooldown": 4,
		"effects": { 
			"heat": 3, 
			"tags": ["decoy"]}
	},
	"infernal_pact": {
		"display_name": "Démonický pakt",
		"description": "Uzavřeš pakt s pekelnými silami. Získáš trvalý bod temných akcí a příjem DOOMu, ale stupňuješ temnotu světa.",
		"type": "global",
		"mana_cost": 30,
		"ap_cost": 2,
		"cooldown": 5,
		"effects": { 
			"dark_actions": 1,
			"doom_income":1,
			"doom": 3, 
			"heat": 5,
			"infernal_pact": true},
	},
	"veil_of_shadows": {
		"display_name": "Závoj stínů",
		"description": "popis tbc.",
		"type": "global",
		"mana_cost": 20,
		"ap_cost": 1,
		"cooldown": 4,
		"effects": {
			"heat": -15,             # výrazně sníží pozornost
			"doom": 2                # ale popostrčí blíž apokalypse
		}
	},
	"soul_exchange": {
		"display_name": "Obchod s dušemi",
		"description": "popis tbc.",
		"type": "global",
		"mana_cost": 0,
		"ap_cost": 1,
		"cooldown": 3,
		"effects": {
			"gold": -20,
			"mana": 12,
			"doom": 1,         # temná magie se projeví
			"heat": 3
		}
	},
	"dark_tribute": {
		"display_name": "Temný tribut",
		"description": "popis tbc.",
		"type": "region",
		"mana_cost": 0,
		"ap_cost": 1,
		"cooldown": 3,

		# NOVÉ – požadavky
		"requirements": {
			"min_corruption_phase": 2  # potřebuješ aspoň fázi 2 (Zkažený)
		},

		"effects": {
			"gold": 25,          # vysaje zlato
			"mana": 10,          # i trochu many
			"heat": 5,           # svět si všimne
			"corruption": -20    # SPÁLÍ část korupce v regionu
		}
	
	},
}

const UNIT = {
	"orc_band": {
		"display_name": "Orčí banda",
		"type": "army",
		"power": 3,
		"recruit_cost": { "gold": 18 },
		"upkeep_cost": { "gold": 2 },
		"moves": 1,
		"can_do": ["raid","explore"],
		# NEW: AI profile (data-driven)
		"ai_profile": {
		  "policy": "raider",
		  "target": {
			"type": "region",
			"select": "nearest",
			"filters": {
			  "region_kind": "civilized",
			  "owner_rule": "not_self"
			}
		  },
		  "plan": [
			{ "mission_key": "raid" }
		  ]
		}
	},
	"vampire": {
		"display_name": "Upír",
		"type": "agent",
		"power": 2,
		"recruit_cost": { "mana": 15 },
		"upkeep_cost": { "mana": 2 },
		"moves": 2,
		"can_do": ["corrupt","sabotage","explore","bribe","manipulate"]
	},
	"homunculus": {
		"display_name": "Homunkulus",
		"type": "agent",
		"power": 1,
		"recruit_cost": { "mana": 10 },
		"upkeep_cost": { "mana": 1 },
		"moves": 2,
		"can_do": ["corrupt","sabotage","explore"]
	},
	"paladin_army": {
		"display_name": "Paladinská armáda",
		"type": "army",
		"power": 5,
		"recruit_cost": {},        # AI-only jednotka
		"upkeep_cost": {},
		"moves": 1,
		"can_do": [], 
		"aura": {
			"mission_success": -0.50,
			"mission_key": ["raid"],
			"affects": "enemies"
		},                 # hráč ji nikdy neovládá
		# NEW: AI profile
		#"ai_profile": {
		  #"policy": "defender",
		  #"target": {
			#"type": "region",
			#"select": "nearest",
			#"filters": {
			  #"occupied": "true",
			  #"owner_rule": "self"
			#},
		  #},
		  #"plan": [
			#{ "mission_key": "_none" }
		  #]
		#}
	},
	"inquisitor": {
		"display_name": "Inkvizitor",
		"type": "agent",
		"power": 1,
		"recruit_cost": {},
		"upkeep_cost": {},
		"moves": 2,
		"can_do": ["purge"],
		"aura": {
			"mission_success": -0.50,
			"mission_key": ["corrupt", "sabotage"],
			"affects": "enemies"
		}       # AI agent, dělá purge a loví agenty
	}
}

const REGION_TYPE = {
	"town": {
		"display_type_name": "Město",
		"defense": 5,
		"gold_income": 3,
		"mana_income": 1,
		"research_income": 1,
	},
	"plains": {
		"display_type_name": "Pláně",
		"defense": 0,
		"gold_income": 2,
		"mana_income": 0,
		"research_income": 0,
	},
	"forest": {
		"display_type_name": "Hvozd",
		"defense": 3,
		"gold_income": 1,
		"mana_income": 3,
		"research_income": 0,
	},
	"wasteland": {
		"display_type_name": "Divočina",
		"defense": 0,
		"gold_income": 1,
		"mana_income": 0,
		"research_income": 0,
	},
	"mountains": {
		"display_type_name": "Hory",
		"defense": 5,
		"gold_income": 0,
		"mana_income": 0,
		"research_income": 0,
	}
}

const HEAT_EVENTS = [
	{
		"threshold": 30,
		"once": true,
		"action": "spawn_army"   
	},
	{
		"threshold": 70,
		"once": true,
		"action": "spawn_army"
	},
	{
		"threshold": 100,
		"once": false,
		"action": "final_attack"
	}
]

const TAGS = {
	"raid": {
		"id": "raid",
		"display_name": "Vypleněno",
		"mul": { "gold_income": 0 },
		"duration": 2,
		"ticks_down": true,
		"visible": true,
		"source": "mission:raid",
	},

	"blockade": {
		"id": "blockade",
		"display_name": "Blokáda obchodu",
		"mul": { "gold_income": 0.5 },
		"duration": 3,
		"ticks_down": true,
		"visible": true,
		"source": "mission:sabotage",
	}, 

	"fear_boost": {
		"id": "fear_boost",
		"display_name": "Zvěsti o hrůze",
		"mul": { }, 
		"add": {"fear": 10},             # ekonomika beze změn
		"duration": 3,
		"ticks_down": true,
		"visible": true,
		"source": "dark_action",
	},

	"decoy": {
		"id": "decoy",
		"display_name": "Shadow Decoy",
		"mul": {},
		"add": {"ai_agent_priority": 50},    
		"duration": 2,
		"ticks_down": true,
		"visible": true,
		"source": "dark_action",
	},
	
	"ancient_knowledge": {
		"id": "ancient_knowledge",
		"display_name": "Prastaré vědění",
		"mul": {},
		"add": { "research_income": 1 },
		"duration": 5,
		"ticks_down": true,
		"visible": true,
		"source": "secret:ancient_ruins",
	}
}

const SECRET = {
	"ancient_ruins": {
		"id": "ancient_ruins",
		"display_name": "Prastaré ruiny",
		"category": "ruins",
		"difficulty": 20,
		"description": "Zbytky dávno ztracené civilizace skrývají zlomky zakázaného poznání.",
		"effects": {
			"gold": 15,
			"mana": 8,
			"heat": 2,
			"tags": ["ancient_knowledge"]
		}
	},

	"leyline_fracture": {
		"id": "leyline_fracture",
		"display_name": "Trhlina v ley-linii",
		"category": "arcane",
		"difficulty": 30,
		"description": "V podloží je narušená ley-linie. Magie tu pulzuje nestabilní silou.",
		"effects": {
			"mana": 15,
			"doom": 2,
			"heat": 3
		}
	}
}

const LAIR = {
	"orc_camp": {
		"display_name": "Orčí tábor",
		"spawn_unit": "orc_band",    # id z Balance.UNIT
		"spawn_rate": 1,             # zatím klidně “každé kolo 1 jednotka”
		"max_units": 2,              # maximální počet jednotek z lairu v regionu
		"faction_id": "orc",         # nebo "neutral_monsters" – podle toho, co máš
	},
}
