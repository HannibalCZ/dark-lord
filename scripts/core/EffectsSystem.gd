extends RefCounted
class_name EffectsSystem

func apply(e: Dictionary, ctx: EffectContext) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	if e == null or e.is_empty():
		return logs

	if ctx == null or ctx.game == null:
		# Bez game nejde aplikovat nic bezpečně.
		logs.append({"type":"warn", "text":"EffectsSystem.apply called with null context/game. Effects ignored."})
		return logs

	var gs := ctx.game
	var region := ctx.region
	var source := ctx.source_faction_id

	# ---- FACTION RESOURCES / FLAGS ----
	var fac := gs.faction_manager.get_faction(source)
	if fac == null:
		# jen warn pokud effecty vůbec míří na frakci
		if _has_any_faction_fields(e):
			logs.append({"type":"warn", "text":"Effects refer to missing faction_id='%s'. Faction part ignored." % source})
	else:
		_apply_faction(e, fac, logs)

	# ---- GLOBALS ----
	_apply_globals(e, gs, logs)

	# ---- REGION ----
	if region != null:
		_apply_region(e, region, source, gs, logs)
	else:
		# region-specific fields exist but no region provided
		if _has_any_region_fields(e):
			logs.append({"type":"warn", "text":"Effects contain region fields but region == null. Region part ignored. Effects=%s" % str(e)})

	# ---- TAGS ----
	_apply_tags(e, region, logs)

	return logs


# -----------------------
# Internal helpers
# -----------------------

func _apply_faction(e: Dictionary, fac: Faction, logs: Array[Dictionary]) -> void:
	# Resources (floats OK)
	if e.has("gold"):
		fac.change_resource("gold", float(e["gold"]))
	if e.has("mana"):
		fac.change_resource("mana", float(e["mana"]))
	if e.has("infamy"):
		fac.change_resource("infamy", float(e["infamy"]))

	# Infernal pact flag (example)
	if e.has("infernal_pact") and bool(e["infernal_pact"]):
		# Guard: properties exist?
		if fac.has_method("set") and fac.has_method("get"):
			# pokud máš tyto fields přímo, je to OK. Kdyby ne, aspoň to nespadne.
			if fac.has_variable("infernal_pact_count"):
				fac.infernal_pact_count += 1
			else:
				# fallback: dynamicky
				var v : Variant = fac.get("infernal_pact_count")
				fac.set("infernal_pact_count", int(v) + 1)

			if fac.has_variable("dark_actions_max"):
				fac.dark_actions_max += 1
			else:
				var m : Variant = fac.get("dark_actions_max")
				fac.set("dark_actions_max", int(m) + 1)
		else:
			logs.append({"type":"warn", "text":"Faction does not support infernal_pact fields; ignored."})


func _apply_globals(e: Dictionary, gs: GameStateSingleton, logs: Array[Dictionary]) -> void:
	if e.has("heat"):
		gs.heat += int(e["heat"])
	if e.has("doom"):
		gs.doom += int(e["doom"])
	if e.has("doom_income"):
		gs.doom_income += int(e["doom_income"])


func _apply_region(e: Dictionary, region: Region, source_faction_id: String, gs: GameStateSingleton, logs: Array[Dictionary]) -> void:
	# Defense
	if e.has("defense"):
		region.defense = max(0, region.defense + int(e["defense"]))

	# Corruption
	if e.has("corruption"):
		region.change_corruption(float(e["corruption"]), source_faction_id)

	# Purge all corruption levels (delta often negative)
	if e.has("purge_corruption_all"):
		var delta := float(e["purge_corruption_all"])
		# region.corruption_levels is expected Dictionary faction_id -> value
		if region.corruption_levels != null and typeof(region.corruption_levels) == TYPE_DICTIONARY:
			for fid in region.corruption_levels.keys():
				region.change_corruption(delta, String(fid))

	# Secret progress
	if e.has("secret_progress"):
		var delta_secret := int(e["secret_progress"])
		region.add_secret_progress(delta_secret)
		_check_secret_completion(region, source_faction_id, gs, logs)

	# Lair influence
	if e.has("lair_influence"):
		var delta_influence := int(e["lair_influence"])
		region.add_influence(delta_influence)
		_check_lair_influence(region, source_faction_id, gs, logs)


func _apply_tags(e: Dictionary, region: Region, logs: Array[Dictionary]) -> void:
	if not e.has("tags"):
		return

	if region == null:
		logs.append({"type":"warn", "text":"Effect contains tags but region == null. Tags ignored."})
		return

	var tags_val : Variant = e["tags"]
	if typeof(tags_val) != TYPE_ARRAY:
		logs.append({"type":"warn", "text":"Effect.tags must be Array. Got=%s" % type_string(typeof(tags_val))})
		return

	for tag_id in tags_val:
		# tag_id usually string, but allow int -> string
		var tid := String(tag_id)
		var t: Dictionary = Balance.TAGS.get(tid, {})
		if t.is_empty():
			logs.append({"type":"warn", "text":"Unknown tag_id in effects: %s" % tid})
			continue
		region.add_tag(t)


# -----------------------
# Completion checks (moved from GameState)
# -----------------------

func _check_secret_completion(region: Region, source_faction_id: String, gs: GameStateSingleton, logs: Array[Dictionary]) -> void:
	if not region.has_active_secret():
		return

	var secret_conf: Dictionary = Balance.SECRET.get(region.secret_id, {})
	if secret_conf.is_empty():
		return

	var difficulty: int = int(secret_conf.get("difficulty", 0))
	if difficulty <= 0:
		return

	if region.secret_progress >= difficulty:
		# Apply secret effects once.
		var eff: Dictionary = secret_conf.get("effects", {})
		if not eff.is_empty():
			# Recurse through EffectsSystem so secret effects can also contain global/faction/region fields.
			var ctx := EffectContext.make(gs, region, source_faction_id)
			var more_logs := apply(eff, ctx)
			logs.append_array(more_logs)

		region.secret_state = "resolved"
		logs.append({"type":"secret", "text":"🗝️ Tajemství odhaleno v regionu %s" % str(region.id)})

func _check_lair_influence(region: Region, source_faction_id: String, gs: GameStateSingleton, logs: Array[Dictionary]) -> void:
	if not region.has_lair():
		return

	# MVP rule (your original): influence >= 20 -> player controls lair
	if region.lair_influence >= 20 and region.lair_control != Balance.PLAYER_FACTION:
		region.lair_control = Balance.PLAYER_FACTION
		logs.append({"type":"lair", "text":"🕳️ Doupě v regionu %s přešlo pod vliv Temného pána." % str(region.id)})

# -----------------------
# Field presence helpers
# -----------------------

func _has_any_faction_fields(e: Dictionary) -> bool:
	return e.has("gold") or e.has("mana") or e.has("infamy") or e.has("infernal_pact")

func _has_any_region_fields(e: Dictionary) -> bool:
	return e.has("defense") or e.has("corruption") or e.has("purge_corruption_all") or e.has("secret_progress") or e.has("lair_influence")
