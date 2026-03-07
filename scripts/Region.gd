# scripts/core/Region.gd
extends Resource
class_name Region

@export var id: int
@export var name: String
@export var owner_faction_id: String
@export var controller_faction_id: String
@export var region_type: String
@export var fear: int = 0
@export var defense: int = 0
@export var gold_income: float = 0
@export var mana_income: float = 0
@export var research_income: float = 0
@export var ai_agent_priority: float = 0
@export var position: Vector2i = Vector2i.ZERO # později pro mapu

var tags: Array = []
var corruption_levels : Dictionary = {}   # { "darklord": 40, "elves": 15 }

# --- TYP REGIONU PRO MECHANIKY ---
# "civilized" – města/pláně/hory pod kontrolou frakcí (korupce, raid…)
# "wildlands" – divočina vhodná pro secrets, lairy, dominion
var region_kind: String = "civilized"

# --- SECRET MECHANIKA ---
var secret_id: String = ""          # odkaz do Balance.SECRET
var secret_known: bool = false      # hráč ví, že tu je tajemství ⇒ "?" na mapě
var secret_state: String = "none"   # "none", "in_progress", "resolved"
var secret_progress: int = 0        # kolik bodů odhalení bylo nasbíráno

# --- LAIR MECHANIKA ---
var lair_id: String = ""           # odkaz do Balance.LAIR
var lair_control: String = "neutral"  # "neutral", "player", "ai"…
var lair_influence: int = 0        # jednoduchý číselný ukazatel, jak moc je doupě na tvojí straně

func _init(_id: int, _name: String, _faction_id: String, _region_type: String):
	id = _id
	name = _name
	owner_faction_id = _faction_id
	controller_faction_id = _faction_id
	region_type = _region_type
	fear = 0
	
	var reg_temp = Balance.REGION_TYPE.get(_region_type,{})
	
	defense = reg_temp.get("defense", 0)
	gold_income = reg_temp.get("gold_income", 0)
	mana_income = reg_temp.get("mana_income", 0)
	research_income = reg_temp.get("research_income", 0)	
	position = Vector2i.ZERO

	match _region_type:
		"town", "plains", "mountains":
			region_kind = "civilized"
		"forest", "wasteland":
			region_kind = "wildlands"
		_:
			region_kind = "civilized" # fallback

# ---------------------------------------------------------------------------------------
# TAG MANAGEMENT

func add_tag(tag: Dictionary) -> void:
	# pokud tag se stejným ID už existuje, přepiš ho (no stacking by default)
	var inst = tag.duplicate(true)
	
	for i in range(tags.size()):
		if tags[i].get("id") == tag.get("id"):
			tags[i] = inst
			return
	tags.append(inst)

func tick_tags() -> void:
	for i in range(tags.size() - 1, -1, -1):
		var t = tags[i]
		if t.get("ticks_down", false) and t.has("duration"):
			t["duration"] -= 1
			if t["duration"] <= 0:
				tags.remove_at(i)

func remove_tag(id: String) -> void:
	for i in range(tags.size() - 1, -1, -1):
		if tags[i].get("id") == id:
			tags.remove_at(i)
			return

func has_secret() -> bool:
	return secret_id != ""

func has_active_secret() -> bool:
	return has_secret() and secret_state != "resolved"

func add_secret_progress(delta:int) -> void:
	if not has_active_secret():
		return

	secret_progress = max(0, secret_progress + delta)

	if secret_state == "none" and secret_progress > 0:
		secret_state = "in_progress"

func add_influence(delta:int) -> void:
	if not has_lair():
		return

	lair_influence = max(0, lair_influence + delta)

# ---------------------------------------------------------------------------------------
# INCOME COMPUTATION

func get_modified_stat(stat_name:String) -> float:
	var base = get(stat_name)   # vezme exportovanou proměnnou z Regionu
	var mul := 1.0
	var add := 0.0
	for t in tags:
		var tmul = t.get("mul", {})
		if tmul.has(stat_name):
			mul *= float(tmul[stat_name])
		var tadd = t.get("add", {})
		if tadd.has(stat_name):
			add += float(tadd[stat_name])
	return float(base) * mul + add

func get_income() -> Dictionary:
	return {
		"gold": get_modified_stat("gold_income"),
		"mana": get_modified_stat("mana_income"), 
		"research": get_modified_stat("research_income")
	}

func get_base_income() -> Dictionary:
	return {
		"gold": float(gold_income),
		"mana": float(mana_income),
		"research": float(research_income)
	}

func get_corruption_for(faction_id: String) -> float:
	return float(corruption_levels.get(faction_id, 0.0))

func get_corruption_phase_for(faction_id: String) -> int:
	var value: float = get_corruption_for(faction_id)

	for phase_def in Balance.CORRUPTION_PHASE_DATA:
		var min_val: float = float(phase_def["min"])
		var max_val: float = float(phase_def["max"])
		if value >= min_val and value <= max_val:
			return int(phase_def["id"])

	# fallback (nemělo by se stát)
	return 0

func has_lair() -> bool:
	return lair_id != ""

func get_corruption_phase_def_for(faction_id: String) -> Dictionary:
	var phase_id: int = get_corruption_phase_for(faction_id)
	for phase_def in Balance.CORRUPTION_PHASE_DATA:
		if int(phase_def["id"]) == phase_id:
			return phase_def
	return {}

func get_info_text() -> String:
	# 1) základní řádky o regionu
	var type_def: Dictionary = Balance.REGION_TYPE.get(region_type, {})
	var type_name: String = type_def.get("display_type_name", region_type)

	var line1 := "%s | %s | %s" % [
		name,
		owner_faction_id,
		type_name
	]

	var base := get_base_income()
	var base_gold: int = int(base["gold"])
	var base_mana: int = int(base["mana"])
	var base_research: int = int(base["research"])

	var line2 := "Obrana: %d | Strach: %d/100 | Příjem (základ): %dG / %dM / %dR" % [
		int(defense),
		int(fear),
		base_gold,
		base_mana,
		base_research
	]

	# 2) korupce hráče v regionu
	var player_corr: float = get_corruption_for(Balance.PLAYER_FACTION)
	#if player_corr <= 0.0:
		## žádná korupce → končíme zde
		#return line1 + "\n" + line2

	var phase_def: Dictionary = get_corruption_phase_def_for(Balance.PLAYER_FACTION)
	var phase_name: String = phase_def.get("display_name", "Neznámá fáze")
	var phase_id: int = phase_def.get("id", 0)

	var split := get_income_split_for_player()
	var owner_gold: float = split["owner_gold"]
	var player_gold: float = split["player_gold"]
	var owner_mana: float = split["owner_mana"]
	var player_mana: float = split["player_mana"]

	# 3) text o korupci a příjmech
	var line3 := "Korupce (Temný pán): %d%% — %s (fáze %d)" % [
		int(player_corr),
		phase_name,
		phase_id
	]

	var line4 := ""
	if owner_faction_id == Balance.PLAYER_FACTION:
		# vlastní region → pro jistotu explicitně
		line4 = "Tvůj příjem: %dG / %dM / %dR" % [
			int(player_gold),
			int(player_mana),
			int(split["player_research"])
		]
	else:
		line4 = "Příjem ownera: %dG / %dM | Tvůj skrytý příjem: %dG / %dM" % [
			int(owner_gold),
			int(owner_mana),
			int(player_gold),
			int(player_mana)
		]

	# ==== SEKCE: TAJEMSTVÍ ====
	var line5 := ""
	if secret_known and has_secret() and secret_state != "resolved":
		var sconf: Dictionary = Balance.SECRET.get(secret_id, {})
		var sname: String = sconf.get("display_name", secret_id)
		var difficulty: int = int(sconf.get("difficulty", 0))

		var progress_str := ""
		if difficulty > 0:
			var clamped_progress: int = min(secret_progress, difficulty)
			progress_str = "%d / %d" % [clamped_progress, difficulty]
		else:
			progress_str = str(secret_progress)

		line5 = "Tajemství: %s (%s)" % [sname,progress_str]

	elif secret_known and secret_state == "resolved":
		# volitelné – můžeš hráči říct, že tajemství už bylo dořešeno
		var sconf: Dictionary = Balance.SECRET.get(secret_id, {})
		var sname: String = sconf.get("display_name", secret_id)
		line5 = ("Tajemství: %s (vyřešeno)" % sname)

	var line6 := ""
	if has_lair():
		var lconf: Dictionary = Balance.LAIR.get(lair_id, {})
		var lname: String = lconf.get("display_name", lair_id)
		line6 = "Doupě: %s (vliv %s)" % [lname,lair_influence]

	return line1 + "\n" + line2 + "\n" + line3 + "\n" + line4 + "\n" + line5 + "\n" + line6
	
func get_tags_display_string() -> String:
	var names: Array[String] = []
	for t in tags:
		names.append(t.get("display_name","?"))
	return ", ".join(names)

func change_corruption(amount:float, faction_id:String) -> void:
	if not corruption_levels.has(faction_id):
		corruption_levels[faction_id] = 0.0

	corruption_levels[faction_id] = max (0, corruption_levels[faction_id] + amount)
	_check_corruption_gain()
	_check_corruption_loss()
	# tady přidáme:
	_update_controller_after_corruption(faction_id)
	
func _check_corruption_gain() -> void:
	for fid in corruption_levels.keys():
		if corruption_levels[fid] >= Balance.CORRUPTION_THRESHOLD:
			controller_faction_id = fid
			return

func _check_corruption_loss() -> void:
	# Pokud kdokoli má >= threshold → někdo furt drží → ignoruj
	for fid in corruption_levels.keys():
		if corruption_levels[fid] >= Balance.CORRUPTION_THRESHOLD:
			return

	# Nikdo už není nad threshold
	controller_faction_id = owner_faction_id

func _update_controller_after_corruption(faction_id: String) -> void:
	var phase_id: int = get_corruption_phase_for(faction_id)

	# když frakce dosáhne controller fáze a ještě není controllerem → stává se jím
	if phase_id >= Balance.CORRUPTION_CONTROLLER_PHASE and controller_faction_id != faction_id:
		controller_faction_id = faction_id
		# sem později můžeme poslat EventBus event: region_controller_changed

	# Volitelně: pokud bys chtěl, aby controller mohl ztratit kontrolu:
	# pokud phase klesne pod threshold a controller_faction_id == faction_id
	# můžeš controller_faction_id vrátit na null/owner
	# (zatím bych to nechal na PURGE logice ve F2.2)

func is_corrupted() -> bool:
	if controller_faction_id != owner_faction_id :
		return true
	else: return false

func get_controller_or_owner() -> String:
	if controller_faction_id != owner_faction_id :
		return controller_faction_id
	else : return owner_faction_id

func get_income_split_for_player() -> Dictionary:
	var base := get_base_income()
	var base_gold: float = base["gold"]
	var base_mana: float = base["mana"]
	var base_research: float = base["research"]

	# default – žádná korupce / fallback
	var owner_gold := base_gold
	var owner_mana := base_mana
	var owner_research := base_research

	var player_gold := 0.0
	var player_mana := 0.0
	var player_research := 0.0

	# hráč korumpuje jen cizí regiony
	if owner_faction_id == Balance.PLAYER_FACTION:
		# vlastní region → vše jde hráči
		player_gold = base_gold
		player_mana = base_mana
		player_research = base_research
	else:
		# cizí region → použijeme fázi korupce hráče
		var phase_def: Dictionary = get_corruption_phase_def_for(Balance.PLAYER_FACTION)
		var owner_mult: float = float(phase_def.get("owner_income_mult", 1.0))
		var ctrl_mult: float = float(phase_def.get("controller_income_mult", 0.0))

		owner_gold = base_gold * owner_mult
		owner_mana = base_mana * owner_mult
		owner_research = base_research * owner_mult

		player_gold = base_gold * ctrl_mult
		player_mana = base_mana * ctrl_mult
		player_research = base_research * ctrl_mult

	return {
		"base_gold": base_gold,
		"base_mana": base_mana,
		"base_research": base_research,

		"owner_gold": owner_gold,
		"owner_mana": owner_mana,
		"owner_research": owner_research,

		"player_gold": player_gold,
		"player_mana": player_mana,
		"player_research": player_research
	}
