# scripts/data/Balance.gd
extends Node

const PLAYER_FACTION = "player"
const CORRUPTION_THRESHOLD = 50

const CORRUPTION_CONTROLLER_PHASE := 3

# Awareness
const AWARENESS_MAX = 100
const AWARENESS_STAGE_INQUISITOR: int = 50  # inkvizitor přechází z lokálního na globální pátrání

# Heat stage thresholdy
const HEAT_STAGE_1 = 25
const HEAT_STAGE_2 = 50
const HEAT_STAGE_3 = 85
const HEAT_MAX = 100  # stage 4 + podmínka prohry
const HEAT_DECAY_PER_TURN = 1  # přirozené snižování Heat každý tah

# Podmínka výhry
const WIN_REGIONS_REQUIRED = 6  # 2/3 z 8 civilizovaných regionů (zaokrouhleno nahoru)
const WIN_REGION_KIND = "civilized"  # pouze regiony s tímto kind se počítají pro výhru
const WIN_CORRUPTION_PHASE = 3       # minimální fáze korupce pro "pod kontrolou"

# Doupata
const LAIR_INFLUENCE_CONTROL_THRESHOLD = 20
const LAIR_INFLUENCE_DECAY: int = 2
const LAIR_INFLUENCE_LOSS_THRESHOLD: int = 0
const LAIR_DIRECTIVE_DEFENSIVE = "defensive"
const LAIR_DIRECTIVE_RAIDER = "raider"

# Mise
const MISSION_CHANCE_MIN = 0.05
const MISSION_CHANCE_MAX = 0.95

# Zranění
const WOUNDED_MISSION_PENALTY: int = 25
const WOUNDED_POWER_PENALTY: int = 2

const CORRUPTION_PHASE_NAMES: Dictionary = {
	0: "Cisty",
	1: "Naruseny",
	2: "Zkaženy",
	3: "Podvrzeny",
	4: "Dominovany"
}

const CORRUPTION_PHASE_EFFECTS: Dictionary = {
	0: "",
	1: "+10% příjmu z regionu, +1 strach/tah",
	2: "+40% příjmu z regionu, +3 strach/tah",
	3: "+50% příjmu, +5 strach/tah, počítá se do vítězství",
	4: "+100% příjmu z regionu, +7 strach/tah"
}

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
		"success": { "heat":6, "gold":5, "defense":-15, "tags": ["blockade"] },
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
			"heat":10, "gold":12, "defense":-5,
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
	},

	"inspect": {
		"id":           "inspect",
		"display_name": "Inspekce organizace",
		"description":  "Agent navstivi organizaci a posili jeji loajalitu.",
		"base_chance":  0.85,
		"requirements": {
			"requires_org": true
		},
		"cost": { "ap": 1, "mana": 0, "gold": 0 },
		"success": { "org_loyalty": ORG_INSPECT_LOYALTY_BOOST },
		"fail":    { "heat": 2 },
		"ui_icon":  "res://ui/icons/missions/inspect.png",
		"ui_order": 8
	},

	"dismantle": {
		"id":           "dismantle",
		"display_name": "Rozpusteni organizace",
		"description":  "Agent znici organizaci v tomto regionu.",
		"base_chance":  0.70,
		"requirements": {
			"requires_org": true
		},
		"cost": { "ap": 1, "mana": 0, "gold": 0 },
		"success": {
			"destroy_org": true,
			"heat": 3
		},
		"fail": {
			"heat": 5,
			"awareness": 2
		},
		"ui_icon":  "res://ui/icons/missions/dismantle.png",
		"ui_order": 9
	},

	"eliminate": {
		"id":           "eliminate",
		"display_name": "Eliminace",
		"description":  "Agent zlikviduje nepratelskou jednotku v tomto regionu.",
		"base_chance":  0.60,
		"requirements": {
			# requires_enemy_unit: true — novy typ requirementu.
			# MissionManager.can_do_mission() ho zatim nezna (Task 3).
			# Mise bude validni pouze kdyz je v regionu
			# nepratela (agent nebo armada jine frakce).
			"requires_enemy_unit": true
		},
		"cost": { "ap": 1, "mana": 0, "gold": 0 },
		"success": {
			# kill_unit: true — novy typ efektu (Task 3).
			# EffectsSystem / MissionManager vybere cilovou jednotku
			# (priorita: pruzkumnik > inkvizitor > armada).
			"kill_unit": true,
			"heat":      5
		},
		"fail": {
			"heat":      8,
			"awareness": 3
		},
		"ui_icon":  "res://ui/icons/missions/eliminate.png",
		"ui_order": 10
	},

	"heal": {
		"id":           "heal",
		"display_name": "Léčení",
		"description":  "Jednotka se zotaví ze zranění a vrátí se do plné bojové pohotovosti.",
		"base_chance":  1,
		"requirements": {},
		"cost": { "ap": 1, "mana": 0, "gold": 0 },
		"success": { "heal_unit": true },
		"fail":    {},
		"ui_icon":  "res://ui/icons/missions/heal.png",
		"ui_order": 11
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
			"heat":3,
			"tags": ["fear_boost"]}
	},
	"decoy": {
		"display_name": "Stínová návnada",
		"description": "Odvádí pozornost hrdinů do vybraného regionu. Zvyšuje šanci, že se AI zaměří sem.",
		"type": "region",
		"mana_cost": 10,
		"ap_cost": 1,
		"cooldown": 5,
		"effects": {
			"heat": 4,
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
			"heat": -8,              # sníží pozornost
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

	# --- Zakládání organizací ---
	# agent_cost: true — první dostupný agent v regionu zmizí (state = "lost")
	# gold_cost / mana_cost — odečteny při vykonání (ne při zadání)
	"found_crime_syndicate": {
		"display_name": "Zaloz Zlocinecky syndikat",
		"description": "Obetuj agenta k vybudovani zlocinecke site v regionu.",
		"type": "region",
		"ap_cost": 1,
		"mana_cost": 0,
		"gold_cost": 20,
		"cooldown": 0,
		"agent_cost": true,
		"effects": { "found_org": "crime_syndicate" },
		"requirements": { "region_kind_in": ["city", "village"] }
	},
	"found_shadow_network": {
		"display_name": "Zaloz Stinovou organizaci",
		"description": "Obetuj agenta k vybudovani site informatoru v regionu.",
		"type": "region",
		"ap_cost": 1,
		"mana_cost": 0,
		"gold_cost": 15,
		"cooldown": 0,
		"agent_cost": true,
		"effects": { "found_org": "shadow_network" }
	},
	"found_cult": {
		"display_name": "Zaloz Kult",
		"description": "Obetuj agenta k vybudovani tajneho kultu v regionu.",
		"type": "region",
		"ap_cost": 1,
		"mana_cost": 15,
		"gold_cost": 0,
		"cooldown": 0,
		"agent_cost": true,
		"effects": { "found_org": "cult" }
	},

	"reinforce_loyalty": {
		"display_name": "Posil loajalitu",
		"description":  "Dark Lord osobne posili vazby s organizaci v tomto regionu.",
		"type":         "region",
		"mana_cost":    3,
		"ap_cost":      1,
		"cooldown":     4,
		"requirements": {
			"requires_org": true
		},
		"effects": {
			"org_loyalty": ORG_REINFORCE_LOYALTY_BOOST
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
		"resilient": false,
		"icon": "res://art/units/orc_band.png",
		# ai_profile záměrně chybí — _pick_profile() v AIManager řídí chování dynamicky
		# podle lair_control regionu lairu (defender vs lair_raider)
	},
	"vampire": {
		"display_name": "Upír",
		"type": "agent",
		"power": 2,
		"recruit_cost": { "mana": 15 },
		"upkeep_cost": { "mana": 2 },
		"moves": 2,
		"can_do": ["corrupt","sabotage","explore","manipulate","inspect","dismantle","eliminate","heal"],
		"resilient": true,
		"icon": "res://art/units/vampire.png",
	},
	"agent": {
		"display_name": "Agent",
		"type": "agent",
		"power": 1,
		"recruit_cost": { "gold": 10 },
		"upkeep_cost": { "gold": 1 },
		"moves": 2,
		"can_do": ["corrupt","sabotage","explore"],
		"resilient": false,
		"icon": "res://art/units/agent.png",
	},
	"paladin_army": {
		"display_name": "Paladinská armáda",
		"type": "army",
		"power": 5,
		"recruit_cost": {},        # AI-only jednotka
		"upkeep_cost": {},
		"moves": 1,
		"can_do": ["raid","heal"],
		"resilient": true,
		"icon": "res://art/units/paladin_army.png",
		"aura": {
			"mission_success": -0.50,
			"mission_key": ["raid"],
			"affects": "enemies"
		},                 # hráč ji nikdy neovládá
	},
	"inquisitor": {
		"display_name": "Inkvizitor",
		"type": "agent",
		"power": 1,
		"recruit_cost": {},
		"upkeep_cost": {},
		"moves": 2,
		"can_do": ["purge","dismantle","heal"],
		"resilient": true,
		"icon": "res://art/units/inquisitor.png",
		"aura": {
			"mission_success": -0.50,
			"mission_key": ["corrupt", "sabotage"],
			"affects": "enemies"
		}       # AI agent, dělá purge a loví agenty
	},
	"explorer": {
		"display_name": "Průzkumník",
		"type": "agent",
		"power": 1,
		"recruit_cost": {},   # AI-only jednotka
		"upkeep_cost": {},
		"moves": 1,
		"can_do": [],
		"resilient": false,
		"icon": "res://art/units/explorer.png",
		# Průzkumník nemá mise — pohybuje se automaticky
		# přes scout profil a generuje efekty při vstupu do regionu.
		"faction": "merchant",
		"ai_profile": "scout"
		# Fixní profil — _pick_profile() vrátí "scout" přes unit-level override.
	}
}

# --- AI PROFILY ---
# Odděleno od UNIT dat. Frakce vybírá profil podle heat flags,
# jednotka jen poskytuje can_do pro validaci akce.
const AI_PROFILE = {
	"defender": {
		"target": {
			"select": "nearest",
			"filters": { "owner_rule": "self" }
		},
		"move_towards_target": true,
		"action_at_target": null
		# defender stojí na vlastním území a bojuje implicitně
	},
	"raider": {
		"target": {
			"select": "nearest",
			"filters": { "region_kind": "civilized", "owner_rule": "not_self" }
		},
		"move_towards_target": true,
		"action_at_target": "raid"
	},
	"lair_hunter": {
		"target": {
			"select": "nearest",
			"filters": { "has_lair": true }
		},
		"move_towards_target": true,
		"action_at_target": "raid"
	},
	"investigator": {
		"target": {
			"select": "highest_corruption"
			# žádné filters — hledá v celém světě region s nejvyšší hráčskou korupcí
		},
		"move_towards_target": true,
		"action_at_target": "purge"
	},
	"investigator_local": {
		"target": {
			"select": "highest_corruption",
			"filters": { "owner_rule": "self" }
		},
		"move_towards_target": true,
		"action_at_target": "purge"
	},
	"lair_raider": {
		"target": {
			"select": "nearest",
			"filters": {
				"region_kind": "civilized",
				"owner_rule": "not_player_or_lair_faction"
			}
		},
		"move_towards_target": true,
		"action_at_target": "raid"
	},
	"lair_raider_active": {
		"target": {
			"select": "nearest",
			"filters": {
				"region_kind": "civilized",
				"no_tag": "raid"
			}
		},
		"move_towards_target": true,
		"action_at_target": "raid",
		"apply_raid_tag": true
	},
	# --- Scout profil — průzkumník obchodníků ---
	# Nepoužívá standardní target/move_towards_target systém.
	# AIManager._pick_profile() vrátí "scout" přes unit-level ai_profile override.
	# Pohybová logika bude v AIManager jako samostatná větev
	# podmíněná profilem "scout" (Task 5).
	"scout": {
		# Prioritizace pohybu (zpracovává AIManager, ne RegionQuery):
		# 1. soused s tajemstvím (secret_id != "")
		# 2. soused wilderness regionu
		# 3. nenavštívený soused (region_id not in unit.visited_regions)
		# 4. náhodný dostupný soused
		"movement": "priority_neighbors",

		# Efekty při vstupu do regionu (aplikuje AIManager, ne MissionManager):
		# - awareness += 1
		# - odhalí secret_id regionu (secret_known = true) pokud existuje
		# - odhalí přítomnost organizací v regionu (zaloguje pro Radu)
		"action_at_region": "explore_effects",

		# Průzkumník se nikdy nezastaví — vždy má kam jít
		"retreat_when_no_targets": false,

		# Průzkumník neutíká před bojem — nechá se porazit
		# Inkvizitor ho může eliminovat jako nepřátelskou jednotku
		"move_towards_target": false,
		"action_at_target": null
	}
}

# AI váhy pro rozhodnutí léčit se
const AI_HEAL_HEAT_THRESHOLD: int = 60  # heat pod touto hodnotou → AI zvažuje heal
const AI_HEAL_IGNORE_HEAT: int = 85     # heat nad touto hodnotou → AI léčení ignoruje

const REGION_DEFENCE_REGEN: int = 1
# Obnova defense per tah pokud region není dobýván

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
		"defense": 3,
		"gold_income": 2,
		"mana_income": 0,
		"research_income": 0,
	},
	"forest": {
		"display_type_name": "Hvozd",
		"defense": 4,
		"gold_income": 1,
		"mana_income": 3,
		"research_income": 0,
	},
	"wasteland": {
		"display_type_name": "Divočina",
		"defense": 2,
		"gold_income": 1,
		"mana_income": 0,
		"research_income": 0,
	},
	"mountains": {
		"display_type_name": "Hory",
		"defense": 6,
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
		"mul": { "gold_income": 0.5 },
		"duration": 3,
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
		"spawn_rate": 1,             # zatím klidně "každé kolo 1 jednotka"
		"max_units": 2,              # maximální počet jednotek z lairu v regionu
		"faction_id": "lair",        # nebo "neutral_monsters" – podle toho, co máš
	},
}

# --- Awareness zdroje ---
const MISSION_GLOBAL_SUCCESS_EFFECTS = {"awareness": 1}
const MISSION_GLOBAL_FAIL_EFFECTS    = {"awareness": 2}
const DARK_ACTION_GLOBAL_EFFECTS     = {"awareness": 1}
const AWARENESS_CORRUPTION_PH3       = 1
const AWARENESS_CORRUPTION_PH4       = 2
const AWARENESS_CORRUPTION_PHASE_MIN = 3

# --- Rada zasvěcených ---
const ADVISOR_KAPITAN = "kapitan"
const ADVISOR_VEZIR   = "vezir"
const ADVISOR_ZVEDKA  = "zvedka"
const ADVISOR_BOSS    = "boss"    # Zlocincky boss — aktivuje se pri zalozeni Crime Syndicate
const ADVISOR_MYSTIK  = "mystik"  # Mystik / Ritualista — aktivuje se pri zalozeni Kultu

const EVENT_CRITICAL  = "critical"
const EVENT_IMPORTANT = "important"
const EVENT_ROUTINE   = "routine"

const COUNCIL_MAX_CRITICAL  = 99  # zobraz vždy
const COUNCIL_MAX_IMPORTANT = 4   # max za tah
const COUNCIL_MAX_TOTAL     = 5   # celkový limit

# --- Organizace ---
const ORG_OWNER_PLAYER  = "player"
const ORG_OWNER_ROGUE   = "rogue"
const ORG_OWNER_NEUTRAL = "neutral"
const ORG_OWNER_RIVAL   = "rival_dark_lord"

const ORG = {
	"crime_syndicate": {
		"display_name": "Zlo\u010dineck\u00fd syndik\u00e1t",
		"cost": { "gold": 20, "mana": 0 },
		"default_doctrine": "extortion",
		"doctrines": {
			"extortion": {
				"display_name": "Vydírání",
				"effects": { "gold": 5, "heat": 1 }
			},
			"laundering": {
				"display_name": "Praní peněz",
				"effects": { "gold": 2 }
			}
		}
	},
	"shadow_network": {
		"display_name": "Stínová organizace",
		"cost": { "gold": 15, "mana": 0 },
		"default_doctrine": "informants",
		"doctrines": {
			"informants": {
				"display_name": "Síť informátorů",
				"effects": { "mission_bonus": 15 }
			},
			"disinfo": {
				"display_name": "Dezinformace",
				"effects": { "heat": -1, "awareness": -1 }
			}
		}
	},
	"cult": {
		"display_name": "Kult",
		"cost": { "gold": 0, "mana": 15 },
		"default_doctrine": "dark_rituals",
		"doctrines": {
			"dark_rituals": {
				"display_name": "Temné obřady",
				"effects": { "mana": 4, "awareness": 1 }
			},
			"ritual_empowerment": {
				"display_name": "Rituální posílení",
				"effects": { "mana": 2, "infamy": 1 }
			}
		}
	}
}

# --- Loajalita organizaci ---

# Vychozi loajalita nove organizace
const ORG_LOYALTY_START: int = 50

# Fazove prahy loajality
const ORG_LOYALTY_FAITHFUL:  int = 71  # 71-100
const ORG_LOYALTY_STABLE:    int = 31  # 31-70
const ORG_LOYALTY_UNSTABLE:  int = 1   # 1-30
# 0 = Rogue

# Multiplikatory efektu per faze
const ORG_LOYALTY_MULT_FAITHFUL:  float = 1.5
const ORG_LOYALTY_MULT_STABLE:    float = 1.0
const ORG_LOYALTY_MULT_UNSTABLE:  float = 0.5

# Pokles loajality per tah podle Infamy pasma
const ORG_LOYALTY_DECAY_LOW:      int = 10  # Infamy 0-20
const ORG_LOYALTY_DECAY_MID:      int = 7   # Infamy 21-50
const ORG_LOYALTY_DECAY_HIGH:     int = 4   # Infamy 51-80
const ORG_LOYALTY_DECAY_VERY_HIGH: int = 1  # Infamy 81+

# Infamy prahy pro vypocet decay
const ORG_INFAMY_LOW:  float = 20.0
const ORG_INFAMY_MID:  float = 50.0
const ORG_INFAMY_HIGH: float = 80.0

# Inspect mise - boost loajality
const ORG_INSPECT_LOYALTY_BOOST: int = 30

# Dark Action "Posil loajalitu" - boost loajality
const ORG_REINFORCE_LOYALTY_BOOST: int = 20

# Prah odhaleni organizace — soucet absolutnich hodnot efektu
# (gold, mana, heat, awareness, infamy) ktery zpusobi odhaleni.
# Organizace ve Verne fazi (loyalty >= ORG_LOYALTY_FAITHFUL)
# s celkovym dopadem >= ORG_REVEAL_THRESHOLD se stane visible.
const ORG_REVEAL_THRESHOLD: int = 8

# --- Efekty neutralnich a Rogue organizaci ---
# Aplikuji se kazdy tah dokud je org neutral nebo Rogue.
# Negativni efekty motivuji hrace je resit.
# mission_penalty neni EffectsSystem klic — cte se pouze v MissionManager.
const ORG_NEUTRAL_EFFECTS = {
	"crime_syndicate": { "heat": 1 },
	"shadow_network":  { "mission_penalty": 0.10 },
	"cult":            { "awareness": 1 }
}

# --- AI Spawning ---
const AI_SPAWN = {
	"paladin": {
		"unit_key":   "paladin_army",
		"trigger":    "heat",
		"threshold":  85,
		"spawn_rate": 4,
		"unit_limit": 3
	},
	"elf": {
		"unit_key":   "inquisitor",
		"trigger":    "awareness",
		"threshold":  50,       # sníženo z 70 — první inkvizitor přichází dříve
		"spawn_rate": 99,
		# spawn_rate 99 = workaround pro quasi-jednorázový spawn.
		# TODO Task 5: process_ai_spawning() přečte "one_shot": true
		# a po prvním spawnu nastaví faction.explorer_spawned_count
		# (nebo dedikovaný flag) tak aby se druhý inkvizitor
		# spawnul teprve při awareness >= threshold_2 (viz EXPLORER_SPAWN).
		"one_shot": true,
		"unit_limit": 2
	}
}

# --- Průzkumník (merchant) spawn podmínky ---
# Průzkumník se spawnuje jinak než ostatní AI jednotky:
# jednorázově v konkrétních okamžicích, ne přes spawn_rate smyčku.
# Logiku čte AIManager / GameState v Task 5 přes explorer_spawned_count
# na Faction objektu.
const EXPLORER_SPAWN = {
	"merchant": {
		"unit_key":          "explorer",
		"spawn_1_turn":      1,
		# První průzkumník spawne v tahu 1 (hned na začátku hry).
		"spawn_2_awareness": 35,
		# Druhý průzkumník spawne když Awareness dosáhne 35.
		# Oba spawny jsou jednorázové — kontroluje faction.explorer_spawned_count.
		"unit_limit":        2,
		# Celkový limit průzkumníků (live + dead se nepočítají — pouze stav != "lost").
		"heat_on_kill":      8
		# Heat boost aplikovaný na hráče když inkvizitor nebo agent eliminuje průzkumníka.
		# Obchodníci si všimnou zmizení svého zvěda.
	}
}

# Šance (v procentech) že průzkumník odhalí tajemství při průchodu regionem
# s dosud neznámým tajemstvím. Roll 1–100, úspěch pokud <= EXPLORER_SECRET_STEAL.
const EXPLORER_SECRET_STEAL: int = 50

static func get_org_effects(org_type: String, doctrine: String) -> Dictionary:
	return ORG[org_type]["doctrines"][doctrine]["effects"]

# KONVENCE PROGRESSION EFEKTŮ:
# TYP A — Modifikátory (mission_success, army_power...):
#   Mohou být kladné i záporné.
#   Odemčení uzlu → EffectsSystem změní faction.modifiers
#   Každý tah → příslušný manažer čte faction.modifiers
#   EffectsSystem se každý tah NEVOLÁ pro tyto modifikátory
#
# TYP B — Zdroje (gold, mana, heat...):
#   Odemčení uzlu → EffectsSystem aplikuje jednorázově
#   Každý tah → ProgressionManager volá EffectsSystem
#   faction.modifiers se pro tyto efekty NEPOUŽÍVÁ
const PROGRESSION = {
	# --- TIER 1 — Společný základ ---
	"dark_will": {
		"display_name": "Temna vule",
		"description":  "Zvysi osobni moc Dark Lorda.",
		"tier": 1, "branch": "common",
		"cost": { "rp": 3 },
		"unlock_conditions": {
			"requires_nodes": [], "excludes_nodes": [],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"shadow_lair": {
		"display_name": "Stinovy lair",
		"description":  "Posili lair Dark Lorda.",
		"tier": 1, "branch": "common",
		"cost": { "rp": 3 },
		"unlock_conditions": {
			"requires_nodes": [], "excludes_nodes": [],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"recruiter": {
		"display_name": "Recruiter",
		"description":  "Rozsiri kapacitu agentu.",
		"tier": 1, "branch": "common",
		"cost": { "rp": 4 },
		"unlock_conditions": {
			"requires_nodes": [], "excludes_nodes": [],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"dark_knowledge": {
		"display_name": "Temne znalosti",
		"description":  "Odemkne pokrocile organizace.",
		"tier": 1, "branch": "common",
		"cost": { "rp": 4 },
		"unlock_conditions": {
			"requires_nodes": [], "excludes_nodes": [],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},

	# --- TIER 2 — Společný základ ---
	"fear_as_weapon": {
		"display_name": "Strach jako zbran",
		"description":  "Korupce zacne pracovat pro Dark Lorda.",
		"tier": 2, "branch": "common",
		"cost": { "rp": 5 },
		"unlock_conditions": {
			"requires_nodes": [],
			"excludes_nodes": [],
			"game_condition": { "type": "regions_corrupted", "min": 2 }
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"dark_army": {
		"display_name": "Temna armada",
		"description":  "Vojenska sila Dark Lorda roste.",
		"tier": 2, "branch": "common",
		"cost": { "rp": 5 },
		"unlock_conditions": {
			"requires_nodes": [],
			"excludes_nodes": [],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"ritual_circle": {
		"display_name": "Ritualni kruh",
		"description":  "Posili magicke schopnosti.",
		"tier": 2, "branch": "common",
		"cost": { "rp": 5 },
		"unlock_conditions": {
			"requires_nodes": [],
			"excludes_nodes": [],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},

	# --- TIER 3 — Stínová větev ---
	"master_of_masks": {
		"display_name": "Mistr masek",
		"description":  "Agent prevezme identitu NPC.",
		"tier": 3, "branch": "shadow",
		"cost": { "rp": 7 },
		"unlock_conditions": {
			"requires_nodes": ["fear_as_weapon"],
			"excludes_nodes": ["whisper_network"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"whisper_network": {
		"display_name": "Sit septu",
		"description":  "Shadow Network reportuje pohyby AI.",
		"tier": 3, "branch": "shadow",
		"cost": { "rp": 7 },
		"unlock_conditions": {
			"requires_nodes": ["fear_as_weapon"],
			"excludes_nodes": ["master_of_masks"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},

	# --- TIER 3 — Válečnická větev ---
	"dark_general": {
		"display_name": "Temny general",
		"description":  "Armady ignoruji prvni Heat threshold.",
		"tier": 3, "branch": "military",
		"cost": { "rp": 7 },
		"unlock_conditions": {
			"requires_nodes": ["dark_army"],
			"excludes_nodes": ["fortress_lord"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"fortress_lord": {
		"display_name": "Hradni pan",
		"description":  "Lairy jsou tezko dobyvatelne.",
		"tier": 3, "branch": "military",
		"cost": { "rp": 7 },
		"unlock_conditions": {
			"requires_nodes": ["dark_army"],
			"excludes_nodes": ["dark_general"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},

	# --- TIER 3 — Mystická větev ---
	"seer": {
		"display_name": "Vestec",
		"description":  "Nahledni do budoucich akci AI.",
		"tier": 3, "branch": "mystic",
		"cost": { "rp": 7 },
		"unlock_conditions": {
			"requires_nodes": ["ritual_circle"],
			"excludes_nodes": ["dark_mirror"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"dark_mirror": {
		"display_name": "Temne zrcadlo",
		"description":  "Zkopiruje efekt nepratelske Dark Action.",
		"tier": 3, "branch": "mystic",
		"cost": { "rp": 7 },
		"unlock_conditions": {
			"requires_nodes": ["ritual_circle"],
			"excludes_nodes": ["seer"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},

	# --- TIER 4 — Specializace ---
	"invisible_hand": {
		"display_name": "Neviditelna ruka",
		"description":  "Korupce se siri automaticky.",
		"tier": 4, "branch": "shadow",
		"cost": { "rp": 10 },
		"unlock_conditions": {
			"requires_nodes": ["master_of_masks", "whisper_network"],
			"excludes_nodes": [],
			"game_condition": { "type": "orgs_active", "min": 3 }
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"fear_precedes": {
		"display_name": "Strach predchazi",
		"description":  "Obsazeni regionu bez odporu.",
		"tier": 4, "branch": "military",
		"cost": { "rp": 10 },
		"unlock_conditions": {
			"requires_nodes": ["dark_general", "fortress_lord"],
			"excludes_nodes": [],
			"game_condition": { "type": "regions_owned", "min": 3 }
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"ritual_nexus": {
		"display_name": "Ritualni nexus",
		"description":  "Dark Actions v Kult regionu zlevni.",
		"tier": 4, "branch": "mystic",
		"cost": { "rp": 10 },
		"unlock_conditions": {
			"requires_nodes": ["seer", "dark_mirror"],
			"excludes_nodes": [],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},

	# --- TIER 5 — Apotheóza ---
	"invisible_throne": {
		"display_name": "Neviditelny trun",
		"description":  "Dark Lord se stane systemem.",
		"tier": 5, "branch": "shadow",
		"cost": { "rp": 15 },
		"unlock_conditions": {
			"requires_nodes": ["invisible_hand"],
			"excludes_nodes": ["iron_throne", "eternal_ritual"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"iron_throne": {
		"display_name": "Zelezny trun",
		"description":  "Dark Lord se stane legendou.",
		"tier": 5, "branch": "military",
		"cost": { "rp": 15 },
		"unlock_conditions": {
			"requires_nodes": ["fear_precedes"],
			"excludes_nodes": ["invisible_throne", "eternal_ritual"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
	"eternal_ritual": {
		"display_name": "Vecny ritual",
		"description":  "Dark Lord prekona smrtelnost.",
		"tier": 5, "branch": "mystic",
		"cost": { "rp": 15 },
		"unlock_conditions": {
			"requires_nodes": ["ritual_nexus"],
			"excludes_nodes": ["invisible_throne", "iron_throne"],
			"game_condition": null
		},
		"one_time_effects": {},
		"passive_effects":  {}
	},
}

static func get_progression_node(node_key: String) -> Dictionary:
	return PROGRESSION.get(node_key, {})

static func get_progression_passive(node_key: String) -> Dictionary:
	var node: Dictionary = PROGRESSION.get(node_key, {})
	return node.get("passive_effects", {})

static func get_progression_one_time(node_key: String) -> Dictionary:
	var node: Dictionary = PROGRESSION.get(node_key, {})
	return node.get("one_time_effects", {})

# --- Proceduralni rozmisteni ---
# PROCEDURAL_GENERATION_ENABLED: true = proceduralni
# rozmisteni tajemstvi pri startu hry,
# false = pouzij data z JSON beze zmeny (fallback)
# --- Reputacni system ---

# Vychozi reputace per frakce
const REPUTATION_BASE = {
	"paladin":  15,
	"elf":      10,
	"merchant": 20,
	"orc":      40
}

# Fazove prahy
const REPUTATION_HOSTILE:     int = 25  # 0-25
const REPUTATION_NEUTRAL:     int = 50  # 26-50
const REPUTATION_INFILTRATED: int = 75  # 51-75
# 76-100 = Ovladnuta

# Vahy pro vypocet
const REPUTATION_WEIGHT_CORRUPTION: int   = 8
const REPUTATION_WEIGHT_SHADOW_NET: float = 0.30

# Efekt na Heat threshold per faze
const REPUTATION_HEAT_MOD_HOSTILE:     int = -10
const REPUTATION_HEAT_MOD_NEUTRAL:     int = 0
const REPUTATION_HEAT_MOD_INFILTRATED: int = 10
const REPUTATION_HEAT_MOD_CONTROLLED:  int = 99
# 99 = prakticky neomezeno — frakce nikdy
# neprekroci threshold

# --- Proceduralni rozmisteni ---
const PROCEDURAL_GENERATION_ENABLED: bool = true

# Seed pro reprodukovatelne vysledky.
# Zmen pro ruzne rozlozeni tajemstvi.
# 0 = nahodny seed pri kazdem spusteni.
const PROCEDURAL_SEED: int = 12345

# Hustota tajemstvi — jaka cast zpusobilych
# regionu dostane tajemstvi.
# Zpusobile regiony: region_kind == "wildlands"
# mimo startovni region hrace.
const PROCEDURAL_SECRET_DENSITY_MIN: float = 0.25
const PROCEDURAL_SECRET_DENSITY_MAX: float = 0.33
