extends GutTest
# Balance a AIProfiles jsou autoloady — přístupné přímo bez setupu


func test_kazdy_terrain_ma_povinne_klice():
	var required = ["defense_base", "pop_cap", "prosperity_cap", "base_gold_rate"]
	for terrain_key in Balance.TERRAIN.keys():
		for key in required:
			assert_true(
				Balance.TERRAIN[terrain_key].has(key),
				"Terrain '%s' chybí klíč '%s'" % [terrain_key, key]
			)


func test_kazda_mise_ma_povinne_klice():
	var required = ["category", "base_chance", "cost"]
	for mission_key in Balance.MISSION.keys():
		for key in required:
			assert_true(
				Balance.MISSION[mission_key].has(key),
				"Mise '%s' chybí klíč '%s'" % [mission_key, key]
			)


func test_kazdy_tag_ma_povinne_klice():
	var required = ["id", "display_name", "ticks_down", "duration"]
	for tag_key in Balance.TAGS.keys():
		for key in required:
			assert_true(
				Balance.TAGS[tag_key].has(key),
				"Tag '%s' chybí klíč '%s'" % [tag_key, key]
			)


func test_kazda_jednotka_ma_povinne_klice():
	var required = ["type", "power", "moves", "resilient", "icon"]
	for unit_key in Balance.UNIT.keys():
		for key in required:
			assert_true(
				Balance.UNIT[unit_key].has(key),
				"Jednotka '%s' chybí klíč '%s'" % [unit_key, key]
			)


func test_kazdy_network_profil_ma_akce():
	var required_actions = ["grow", "generate", "hide", "expand", "suppress"]
	var network_profiles = ["cult_network", "crime_syndicate_network", "shadow_network_network"]
	for profile_key in network_profiles:
		assert_true(
			AIProfiles.ACTORS.has(profile_key),
			"Chybí network profil '%s'" % profile_key
		)
		var actions = AIProfiles.ACTORS[profile_key].get("actions", {})
		for action in required_actions:
			assert_true(
				actions.has(action),
				"Profil '%s' chybí akce '%s'" % [profile_key, action]
			)
